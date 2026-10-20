//! The actions this player can take right now, as buttons. Each one carries the typed command
//! it stands for, so a button press goes through the same parser as typing, and both clients
//! offer exactly what the server will accept.

use webgame_protocol::{
    DayStage, GamePhase, JailStatus, NightAction, PlayerSlot, Role, TargetRule, Verdict,
};

use crate::State;

/// One thing the player can do now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Action {
    /// The button text, like "Vote" or "Heal".
    pub label: String,
    /// What to submit when pressed, like `/vote 3`.
    pub command: String,
    /// The player it is aimed at, for buttons shown next to a player. None for buttons that
    /// stand alone, like Guilty or Alert.
    pub target: Option<PlayerSlot>,
    /// Whether this is the player's current choice.
    pub selected: bool,
}

impl Action {
    fn on(label: &str, command: &str, target: PlayerSlot, selected: bool) -> Action {
        Action {
            label: label.into(),
            command: format!("{command} {target}"),
            target: Some(target),
            selected,
        }
    }

    fn alone(label: &str, command: &str, selected: bool) -> Action {
        Action {
            label: label.into(),
            command: command.into(),
            target: None,
            selected,
        }
    }
}

impl State {
    /// Everything this player can do in the current phase, players' buttons in lot order and
    /// then the ones that stand alone.
    pub fn actions(&self) -> Vec<Action> {
        let (Some(me), Some(role)) = (self.me, self.role) else {
            return Vec::new();
        };
        if !self.in_game() {
            return Vec::new();
        }
        match &self.phase {
            GamePhase::Day { stage, .. } => self.day_actions(me, role, stage),
            GamePhase::Night { night } => self.night_actions(me, role, *night),
            GamePhase::Lobby | GamePhase::GameOver => Vec::new(),
        }
    }

    fn day_actions(&self, me: PlayerSlot, role: Role, stage: &DayStage) -> Vec<Action> {
        let mut out = Vec::new();
        if !self.alive(me) {
            return out;
        }
        let others = self.living_others(me);
        match stage {
            DayStage::Voting { .. } => {
                for &slot in &others {
                    out.push(Action::on(
                        "Vote",
                        "/vote",
                        slot,
                        self.choices.vote == Some(slot),
                    ));
                }
                if self.choices.vote.is_some() {
                    out.push(Action::alone("Unvote", "/unvote", false));
                }
            }
            DayStage::Judgement { accused } if *accused != me => {
                for (label, command, verdict) in [
                    ("Guilty", "/guilty", Verdict::Guilty),
                    ("Innocent", "/inno", Verdict::Innocent),
                    ("Abstain", "/abstain", Verdict::Abstain),
                ] {
                    let selected = self.choices.verdict == Some(verdict);
                    out.push(Action::alone(label, command, selected));
                }
            }
            _ => {}
        }
        if role == Role::Jailer {
            for &slot in &others {
                out.push(Action::on(
                    "Jail",
                    "/jail",
                    slot,
                    self.choices.jail == Some(slot),
                ));
            }
            if self.choices.jail.is_some() {
                out.push(Action::alone("Don't jail", "/jail", false));
            }
        }
        out
    }

    fn night_actions(&self, me: PlayerSlot, role: Role, night: u32) -> Vec<Action> {
        let mut out = Vec::new();
        let chosen = |slot: PlayerSlot| self.choices.night == Some(NightAction::Target(slot));
        let activated = self.choices.night == Some(NightAction::Activate);
        if !self.alive(me) {
            // Only a lynched Jester acts after death.
            for &slot in &self.choices.haunt {
                out.push(Action::on("Haunt", "/target", slot, chosen(slot)));
            }
            return self.with_cancel(out);
        }
        match self.jail {
            JailStatus::Prisoner => return out,
            JailStatus::Jailer { .. } if night > 1 => {
                out.push(Action::alone("Execute", "/execute", activated));
                return self.with_cancel(out);
            }
            JailStatus::Jailer { .. } | JailStatus::Free => {}
        }
        if role == Role::Vigilante && night <= 1 {
            return out;
        }
        let verb = verb(role);
        let others = self.living_others(me);
        match role.target_rule() {
            TargetRule::None | TargetRule::Execute => {}
            TargetRule::Other => {
                for &slot in &others {
                    out.push(Action::on(verb, "/target", slot, chosen(slot)));
                }
            }
            TargetRule::OtherNotMafia => {
                for &slot in others.iter().filter(|s| !self.on_team(**s)) {
                    out.push(Action::on(verb, "/target", slot, chosen(slot)));
                }
            }
            TargetRule::AnyAlive => {
                for slot in self.players.iter().filter(|p| p.alive).map(|p| p.slot) {
                    out.push(Action::on(verb, "/target", slot, chosen(slot)));
                }
            }
            TargetRule::SelfOnly => {
                let command = if role == Role::Veteran {
                    "/alert"
                } else {
                    "/vest"
                };
                out.push(Action::alone(verb, command, activated));
            }
            TargetRule::Dead => {
                for slot in self.players.iter().filter(|p| !p.alive).map(|p| p.slot) {
                    out.push(Action::on(verb, "/target", slot, chosen(slot)));
                }
            }
            TargetRule::TwoAlive => out.extend(self.copycat_actions(&others)),
            TargetRule::DouseOrIgnite => {
                for &slot in &others {
                    out.push(Action::on(verb, "/target", slot, chosen(slot)));
                }
                out.push(Action::alone("Ignite", "/ignite", activated));
            }
        }
        self.with_cancel(out)
    }

    /// A Copycat picks in two steps: whose ability to copy (any other living player), then who
    /// to use it on (any living player), which sends both.
    fn copycat_actions(&self, others: &[PlayerSlot]) -> Vec<Action> {
        let mut out = Vec::new();
        match self.choices.copy_from {
            None => {
                let copied = match self.choices.night {
                    Some(NightAction::TwoTargets(copied, _)) => Some(copied),
                    _ => None,
                };
                for &slot in others {
                    out.push(Action::on("Copy", "/copy", slot, copied == Some(slot)));
                }
            }
            Some(copied) => {
                for slot in self.players.iter().filter(|p| p.alive).map(|p| p.slot) {
                    let selected =
                        self.choices.night == Some(NightAction::TwoTargets(copied, slot));
                    out.push(Action {
                        label: "Use on".into(),
                        command: format!("/target {copied} {slot}"),
                        target: Some(slot),
                        selected,
                    });
                }
            }
        }
        out
    }

    /// Adds a Cancel button when there is something to take back.
    fn with_cancel(&self, mut out: Vec<Action>) -> Vec<Action> {
        if self.choices.night.is_some() || self.choices.copy_from.is_some() {
            out.push(Action::alone("Cancel", "/cancel", false));
        }
        out
    }

    fn living_others(&self, me: PlayerSlot) -> Vec<PlayerSlot> {
        self.players
            .iter()
            .filter(|p| p.alive && p.slot != me)
            .map(|p| p.slot)
            .collect()
    }

    fn on_team(&self, slot: PlayerSlot) -> bool {
        self.team.iter().any(|t| t.slot == slot)
    }
}

/// What a role's night button says.
fn verb(role: Role) -> &'static str {
    use Role::*;
    match role {
        Sheriff => "Interrogate",
        Investigator => "Investigate",
        Lookout => "Watch",
        Tracker => "Track",
        Spy => "Bug",
        Barkeep => "Block",
        Trapper => "Trap",
        Vigilante => "Shoot",
        Doctor => "Heal",
        Bodyguard => "Guard",
        Veteran => "Alert",
        Survivor => "Vest",
        Godfather | Mafioso | SerialKiller => "Kill",
        Ambusher => "Ambush",
        Poisoner => "Poison",
        Consigliere => "Check",
        Escort => "Distract",
        Disguiser => "Disguise",
        Copycat => "Copy",
        Amnesiac => "Remember",
        Arsonist => "Douse",
        Jailer | Medium | Executioner | Jester => "",
    }
}

#[cfg(test)]
mod tests {
    use webgame_protocol::{Accepted, GameStart, PlayerSummary, ServerMessage, TeamMember};

    use super::*;

    fn game(role: Role, team: Vec<TeamMember>) -> State {
        let mut state = State::default();
        let players = (0..5)
            .map(|n| PlayerSummary {
                slot: PlayerSlot(n),
                name: format!("P{}", n + 1),
                alive: n != 4,
            })
            .collect();
        state.apply(ServerMessage::GameStarted(GameStart {
            you: PlayerSlot(0),
            role,
            players,
            role_list: Vec::new(),
            team,
            executioner_target: None,
            last_will: String::new(),
        }));
        state
    }

    fn at(state: &mut State, phase: GamePhase) {
        state.apply(ServerMessage::Phase {
            phase,
            ends_at_ms: 0,
        });
    }

    fn commands(state: &State) -> Vec<String> {
        state.actions().into_iter().map(|a| a.command).collect()
    }

    #[test]
    fn voting_offers_every_other_living_player() {
        let mut state = game(Role::Sheriff, Vec::new());
        let voting = DayStage::Voting { trials_left: 3 };
        at(
            &mut state,
            GamePhase::Day {
                day: 1,
                stage: voting,
            },
        );
        assert_eq!(commands(&state), ["/vote 2", "/vote 3", "/vote 4"]);

        state.apply(ServerMessage::Votes {
            votes: vec![webgame_protocol::VoteEntry {
                voter: PlayerSlot(0),
                target: PlayerSlot(2),
            }],
            needed: 3,
        });
        let actions = state.actions();
        assert!(actions.iter().any(|a| a.command == "/vote 3" && a.selected));
        assert_eq!(actions.last().unwrap().command, "/unvote");
    }

    #[test]
    fn the_accused_doesnt_judge_themself() {
        let mut state = game(Role::Doctor, Vec::new());
        let judging = |accused| GamePhase::Day {
            day: 1,
            stage: DayStage::Judgement { accused },
        };
        at(&mut state, judging(PlayerSlot(0)));
        assert!(state.actions().is_empty());
        at(&mut state, judging(PlayerSlot(1)));
        assert_eq!(commands(&state), ["/guilty", "/inno", "/abstain"]);
    }

    #[test]
    fn mafia_dont_target_their_own() {
        let team = vec![
            TeamMember {
                slot: PlayerSlot(0),
                role: Role::Mafioso,
                alive: true,
            },
            TeamMember {
                slot: PlayerSlot(2),
                role: Role::Godfather,
                alive: true,
            },
        ];
        let mut state = game(Role::Mafioso, team);
        at(&mut state, GamePhase::Night { night: 1 });
        assert_eq!(commands(&state), ["/target 2", "/target 4"]);

        state.apply(ServerMessage::Accepted(Accepted::Night(Some(
            NightAction::Target(PlayerSlot(1)),
        ))));
        let actions = state.actions();
        assert!(actions[0].selected && actions[0].label == "Kill");
        assert_eq!(actions.last().unwrap().command, "/cancel");
    }

    #[test]
    fn doctors_can_heal_themselves_and_amnesiacs_pick_the_dead() {
        let mut doctor = game(Role::Doctor, Vec::new());
        at(&mut doctor, GamePhase::Night { night: 1 });
        assert_eq!(doctor.actions().len(), 4);

        let mut amnesiac = game(Role::Amnesiac, Vec::new());
        at(&mut amnesiac, GamePhase::Night { night: 1 });
        assert_eq!(commands(&amnesiac), ["/target 5"]);
    }

    #[test]
    fn a_vigilante_waits_for_the_second_night() {
        let mut state = game(Role::Vigilante, Vec::new());
        at(&mut state, GamePhase::Night { night: 1 });
        assert!(state.actions().is_empty());
        at(&mut state, GamePhase::Night { night: 2 });
        assert_eq!(state.actions().len(), 3);
    }

    #[test]
    fn a_copycat_picks_in_two_steps() {
        let mut state = game(Role::Copycat, Vec::new());
        at(&mut state, GamePhase::Night { night: 1 });
        assert_eq!(commands(&state), ["/copy 2", "/copy 3", "/copy 4"]);

        state.choices.copy_from = Some(PlayerSlot(2));
        assert_eq!(
            commands(&state),
            [
                "/target 3 1",
                "/target 3 2",
                "/target 3 3",
                "/target 3 4",
                "/cancel"
            ]
        );
    }

    #[test]
    fn a_jailer_jails_by_day() {
        let mut state = game(Role::Jailer, Vec::new());
        at(
            &mut state,
            GamePhase::Day {
                day: 1,
                stage: DayStage::Discussion,
            },
        );
        assert_eq!(commands(&state), ["/jail 2", "/jail 3", "/jail 4"]);
    }
}
