//! Days, trials, chat visibility, and whole games, driven through `Game` with fake time.

use rand::seq::IndexedRandom;
use rand::{RngExt, SeedableRng};
use rand_chacha::ChaCha8Rng;
use webgame_game::{Audience, Game, Input, Outgoing, Seat, Timers};
use webgame_protocol::{
    ChatChannel, ChatSender, DayStage, DeathCause, ErrorCode, GameAction, GamePhase, NightAction,
    Notice, Outcome, PlayerSlot, Role, ServerMessage, UserId, Verdict,
};

/// Every phase lasts one second.
const PHASE: u64 = 1_000;

fn seats(count: usize) -> Vec<Seat> {
    (0..count)
        .map(|i| Seat {
            slot: PlayerSlot(i as u8),
            user_id: UserId(i as u64),
            name: format!("P{}", i + 1),
        })
        .collect()
}

fn slot(n: u8) -> PlayerSlot {
    PlayerSlot(n)
}

/// A game with fixed roles, and a clock to drive it.
struct Table {
    game: Game,
    now: u64,
    log: Vec<Outgoing>,
}

impl Table {
    fn new(roles: &[Role]) -> Self {
        let (game, log) =
            Game::with_roles(seats(roles.len()), roles, 1, Timers::uniform(PHASE), 0).unwrap();
        Table { game, now: 0, log }
    }

    fn act(&mut self, from: u8, action: GameAction) {
        let out = self
            .game
            .handle(slot(from), Input::Action(action), self.now)
            .unwrap();
        self.log.extend(out);
    }

    fn try_act(&mut self, from: u8, action: GameAction) -> Result<(), ErrorCode> {
        let out = self
            .game
            .handle(slot(from), Input::Action(action), self.now)
            .map_err(|e| e.code)?;
        self.log.extend(out);
        Ok(())
    }

    fn say(&mut self, from: u8, channel: ChatChannel, text: &str) -> Result<(), ErrorCode> {
        let out = self
            .game
            .handle(
                slot(from),
                Input::Chat {
                    channel,
                    text: text.into(),
                },
                self.now,
            )
            .map_err(|e| e.code)?;
        self.log.extend(out);
        Ok(())
    }

    /// Runs the clock to the end of the current phase.
    fn next_phase(&mut self) {
        self.now = self.game.deadline().expect("game is running");
        let out = self.game.tick(self.now);
        self.log.extend(out);
    }

    /// Runs the clock until the phase matches.
    fn until(&mut self, wanted: impl Fn(&GamePhase) -> bool) {
        for _ in 0..50 {
            if wanted(self.game.phase()) {
                return;
            }
            self.next_phase();
        }
        panic!("never reached the phase; stuck at {:?}", self.game.phase());
    }

    fn until_voting(&mut self) {
        self.until(|p| {
            matches!(
                p,
                GamePhase::Day {
                    stage: DayStage::Voting { .. },
                    ..
                }
            )
        });
    }

    fn until_night(&mut self) {
        self.until(|p| p.is_night());
    }

    /// Messages seen by one player since the log was last cleared.
    fn seen_by(&self, n: u8) -> Vec<&ServerMessage> {
        self.log
            .iter()
            .filter(|o| o.to.includes(slot(n)))
            .map(|o| &o.message)
            .collect()
    }

    fn put_on_trial(&mut self, accused: u8, voters: &[u8]) {
        for voter in voters {
            self.act(*voter, GameAction::Vote(Some(slot(accused))));
        }
        assert_eq!(self.game.phase().accused(), Some(slot(accused)));
    }
}

#[test]
fn phases_go_day_zero_then_night_one_then_day_one() {
    let mut table = Table::new(&[Role::Mafioso, Role::Sheriff, Role::Doctor, Role::Jester]);
    assert_eq!(
        table.game.phase(),
        &GamePhase::Day {
            day: 0,
            stage: DayStage::Discussion
        }
    );
    assert_eq!(table.game.deadline(), Some(PHASE));
    table.next_phase();
    assert_eq!(table.game.phase(), &GamePhase::Night { night: 1 });
    table.next_phase();
    assert_eq!(
        table.game.phase(),
        &GamePhase::Day {
            day: 1,
            stage: DayStage::Discussion
        }
    );
    table.next_phase();
    assert_eq!(
        table.game.phase(),
        &GamePhase::Day {
            day: 1,
            stage: DayStage::Voting { trials_left: 3 }
        }
    );
    table.next_phase();
    assert_eq!(table.game.phase(), &GamePhase::Night { night: 2 });
}

#[test]
fn each_player_learns_only_their_own_role() {
    let table = Table::new(&[Role::Mafioso, Role::Sheriff, Role::Godfather, Role::Jester]);
    for (n, role) in [(0, Role::Mafioso), (1, Role::Sheriff)] {
        let starts: Vec<_> = table
            .seen_by(n)
            .into_iter()
            .filter_map(|m| match m {
                ServerMessage::GameStarted(start) => Some(start.clone()),
                _ => None,
            })
            .collect();
        assert_eq!(starts.len(), 1);
        assert_eq!(starts[0].role, role);
        // Only the Mafia see the team.
        assert_eq!(starts[0].team.len(), if n == 0 { 2 } else { 0 });
    }
}

#[test]
fn a_failed_trial_returns_to_voting_and_three_end_the_day() {
    let mut table = Table::new(&[
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Lookout,
        Role::Jester,
    ]);
    table.until_voting();
    for trial in 0..3u8 {
        // Three of five votes is a majority.
        table.put_on_trial(4, &[0, 1, 2]);
        table.next_phase(); // defense -> judgement
        table.act(0, GameAction::Judgement(Verdict::Innocent));
        table.next_phase(); // judgement -> verdict
        if trial < 2 {
            assert_eq!(
                table.game.phase(),
                &GamePhase::Day {
                    day: 1,
                    stage: DayStage::Voting {
                        trials_left: 2 - trial
                    }
                }
            );
        }
    }
    assert_eq!(table.game.phase(), &GamePhase::Night { night: 2 });
}

#[test]
fn voting_resumes_with_the_time_it_had_left() {
    let mut table = Table::new(&[Role::Mafioso, Role::Sheriff, Role::Doctor, Role::Lookout]);
    table.until_voting();
    table.now += 400;
    table.put_on_trial(0, &[1, 2, 3]);
    table.next_phase();
    table.next_phase(); // nobody judged: not guilty
    // 400 ms of voting were used before the trial, so 600 ms are left after it.
    assert_eq!(table.game.deadline(), Some(table.now + PHASE - 400));
}

#[test]
fn a_guilty_verdict_lynches_reveals_the_will_and_ends_the_day() {
    let mut table = Table::new(&[
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Lookout,
        Role::Survivor,
    ]);
    table.act(0, GameAction::SetLastWill("I was framed".into()));
    table.until_voting();
    table.put_on_trial(0, &[1, 2, 3]);
    assert!(
        table.say(1, ChatChannel::General, "hi").is_err(),
        "only the accused speaks in defense"
    );
    table.say(0, ChatChannel::General, "it wasn't me").unwrap();
    table.next_phase();
    for voter in [1, 2, 3] {
        table.act(voter, GameAction::Judgement(Verdict::Guilty));
    }
    assert_eq!(
        table.try_act(0, GameAction::Judgement(Verdict::Innocent)),
        Err(ErrorCode::NotAllowedNow)
    );
    table.log.clear();
    table.next_phase();
    assert!(matches!(
        table.game.phase(),
        GamePhase::Day {
            stage: DayStage::LastWords { .. },
            ..
        }
    ));
    assert!(table.log.iter().any(|o| matches!(
        o.message,
        ServerMessage::TrialResult {
            guilty: 3,
            convicted: true,
            ..
        }
    )));
    table.next_phase();
    let deaths = table.log.iter().find_map(|o| match &o.message {
        ServerMessage::Deaths(deaths) if !deaths.is_empty() => Some(deaths.clone()),
        _ => None,
    });
    let deaths = deaths.expect("a death report");
    assert_eq!(deaths[0].role, Role::Mafioso);
    assert_eq!(deaths[0].will, "I was framed");
    assert_eq!(deaths[0].causes, vec![DeathCause::Lynched]);
    // The only Mafia member is gone, so the Town (and the Survivor) win.
    let result = table.game.result().expect("game over");
    assert_eq!(result.outcome, Outcome::Town);
    assert!(result.winners.contains(&slot(4)));
    assert!(!result.winners.contains(&slot(0)));
}

#[test]
fn a_lynched_jester_wins_and_haunts_a_guilty_voter() {
    let mut table = Table::new(&[
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Lookout,
        Role::Jester,
        Role::Investigator,
    ]);
    table.until_voting();
    table.put_on_trial(4, &[1, 2, 3, 5]);
    table.next_phase();
    table.act(1, GameAction::Judgement(Verdict::Guilty));
    table.act(2, GameAction::Judgement(Verdict::Innocent));
    table.act(3, GameAction::Judgement(Verdict::Guilty));
    table.act(5, GameAction::Judgement(Verdict::Guilty));
    table.next_phase(); // -> last words
    table.log.clear();
    table.next_phase(); // -> lynch, night 2
    assert_eq!(table.game.phase(), &GamePhase::Night { night: 2 });
    assert!(table.game.player(slot(4)).unwrap().won);
    assert!(
        table
            .seen_by(4)
            .contains(&&ServerMessage::Notices(vec![Notice::ChooseHaunt {
                candidates: vec![slot(1), slot(3), slot(5)],
            }]))
    );
    // Only guilty voters can be haunted.
    assert_eq!(
        table.try_act(4, GameAction::Night(Some(NightAction::Target(slot(2))))),
        Err(ErrorCode::InvalidTarget)
    );
    table.act(4, GameAction::Night(Some(NightAction::Target(slot(3)))));
    table.next_phase();
    assert!(!table.game.player(slot(3)).unwrap().alive);
}

#[test]
fn executioner_wins_on_a_lynch_and_turns_jester_on_a_night_death() {
    // Executioners target the first Town member: seat 1, the Sheriff.
    let roles = [
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Lookout,
        Role::Executioner,
    ];
    let mut table = Table::new(&roles);
    table.until_voting();
    table.put_on_trial(1, &[0, 2, 3]);
    table.next_phase();
    for voter in [0, 2, 3, 4] {
        table.act(voter, GameAction::Judgement(Verdict::Guilty));
    }
    table.next_phase();
    table.next_phase();
    assert!(table.game.player(slot(4)).unwrap().won);

    let mut table = Table::new(&roles);
    table.until_night();
    table.act(0, GameAction::Night(Some(NightAction::Target(slot(1)))));
    table.log.clear();
    table.next_phase();
    assert_eq!(table.game.player(slot(4)).unwrap().role, Role::Jester);
    assert!(
        table
            .seen_by(4)
            .contains(&&ServerMessage::RoleChanged { role: Role::Jester })
    );
}

#[test]
fn chat_reaches_only_those_who_may_read_it() {
    let mut table = Table::new(&[
        Role::Mafioso,
        Role::Godfather,
        Role::Doctor,
        Role::Medium,
        Role::Sheriff,
        Role::Lookout,
        Role::Investigator,
    ]);
    table.log.clear();

    // A whisper: everyone sees that it happened, only the two see the text.
    table
        .say(2, ChatChannel::Whisper { to: slot(4) }, "I'm the doctor")
        .unwrap();
    let text_seen = |table: &Table, n: u8| {
        table
            .seen_by(n)
            .iter()
            .any(|m| matches!(m, ServerMessage::Chat(c) if c.text == "I'm the doctor"))
    };
    assert!(text_seen(&table, 2) && text_seen(&table, 4));
    assert!(!text_seen(&table, 0) && !text_seen(&table, 3));
    assert!(table.seen_by(0).contains(&&ServerMessage::Whispered {
        from: slot(2),
        to: slot(4)
    }));

    // Mafia chat is for the Mafia, at night.
    assert_eq!(
        table.say(0, ChatChannel::Mafia, "by day?"),
        Err(ErrorCode::NotAllowedNow)
    );
    table.until_night();
    table.log.clear();
    table
        .say(0, ChatChannel::Mafia, "kill the sheriff")
        .unwrap();
    assert_eq!(table.seen_by(1).len(), 1);
    assert!(table.seen_by(4).is_empty());
    assert_eq!(
        table.say(2, ChatChannel::Mafia, "let me in"),
        Err(ErrorCode::NotAllowedNow)
    );
    assert_eq!(
        table.say(2, ChatChannel::General, "anyone?"),
        Err(ErrorCode::NotAllowedNow)
    );

    // Kill the Sheriff; the dead talk to the dead, and the Medium hears them at night.
    table.act(0, GameAction::Night(Some(NightAction::Target(slot(4)))));
    table.next_phase();
    assert!(!table.game.player(slot(4)).unwrap().alive);
    assert_eq!(
        table.say(4, ChatChannel::General, "I was the sheriff"),
        Err(ErrorCode::NotAllowedNow)
    );
    table.until_night();
    table.log.clear();
    table.say(4, ChatChannel::Dead, "boo").unwrap();
    assert_eq!(
        table.seen_by(3).len(),
        1,
        "the Medium hears the dead at night"
    );
    assert!(table.seen_by(2).is_empty());
    table.log.clear();
    table.say(3, ChatChannel::Dead, "who killed you?").unwrap();
    let ServerMessage::Chat(message) = table.seen_by(4)[0] else {
        panic!()
    };
    assert_eq!(message.from, ChatSender::Medium);
}

#[test]
fn jailer_jails_by_day_and_talks_anonymously_at_night() {
    let mut table = Table::new(&[Role::Jailer, Role::Mafioso, Role::Doctor, Role::Sheriff]);
    table.act(0, GameAction::Jail(Some(slot(1))));
    table.next_phase(); // night 1
    assert!(
        table
            .seen_by(1)
            .contains(&&ServerMessage::Notices(vec![Notice::Jailed]))
    );
    assert_eq!(
        table.try_act(1, GameAction::Night(Some(NightAction::Target(slot(2))))),
        Err(ErrorCode::NotAllowedNow),
        "prisoners can't act"
    );
    assert_eq!(
        table.try_act(0, GameAction::Night(Some(NightAction::Activate))),
        Err(ErrorCode::NotAllowedNow),
        "no executions on night 1"
    );
    table.log.clear();
    table.say(0, ChatChannel::Jail, "why are you here").unwrap();
    let ServerMessage::Chat(message) = table.seen_by(1)[0] else {
        panic!()
    };
    assert_eq!(message.from, ChatSender::Jailer);
    assert!(table.seen_by(2).is_empty());

    table.until_voting();
    table.act(0, GameAction::Jail(Some(slot(1))));
    table.until_night();
    table.act(0, GameAction::Night(Some(NightAction::Activate)));
    table.next_phase();
    // The only Mafia member is executed: Town wins.
    assert_eq!(table.game.result().unwrap().outcome, Outcome::Town);
}

#[test]
fn night_actions_are_checked_against_the_role() {
    let mut table = Table::new(&[
        Role::Vigilante,
        Role::Mafioso,
        Role::Godfather,
        Role::Doctor,
        Role::Sheriff,
        Role::Lookout,
        Role::Investigator,
    ]);
    table.until_night();
    let night = |a| GameAction::Night(Some(a));
    assert_eq!(
        table.try_act(0, night(NightAction::Target(slot(1)))),
        Err(ErrorCode::NotAllowedNow)
    );
    assert_eq!(
        table.try_act(1, night(NightAction::Target(slot(2)))),
        Err(ErrorCode::InvalidTarget)
    );
    assert_eq!(
        table.try_act(1, night(NightAction::Target(slot(1)))),
        Err(ErrorCode::InvalidTarget)
    );
    assert_eq!(
        table.try_act(4, night(NightAction::Activate)),
        Err(ErrorCode::InvalidTarget)
    );
    table.act(3, night(NightAction::Target(slot(3))));
    table.act(1, night(NightAction::Target(slot(4))));
    table.next_phase();
    table.until_night();
    // The Doctor's one self-heal is spent.
    assert_eq!(
        table.try_act(3, night(NightAction::Target(slot(3)))),
        Err(ErrorCode::NoUsesLeft)
    );
    // The dead Sheriff can't act.
    assert_eq!(
        table.try_act(4, night(NightAction::Target(slot(1)))),
        Err(ErrorCode::NotAllowedNow)
    );
}

#[test]
fn the_mafioso_takes_over_when_the_godfather_dies() {
    let mut table = Table::new(&[
        Role::Godfather,
        Role::Mafioso,
        Role::Consigliere,
        Role::Vigilante,
        Role::Doctor,
        Role::Sheriff,
        Role::Lookout,
    ]);
    table.until_voting();
    table.put_on_trial(0, &[3, 4, 5, 6]);
    table.next_phase();
    for voter in [3, 4, 5, 6] {
        table.act(voter, GameAction::Judgement(Verdict::Guilty));
    }
    table.next_phase();
    table.next_phase();
    assert_eq!(table.game.player(slot(1)).unwrap().role, Role::Godfather);
    assert_eq!(table.game.player(slot(2)).unwrap().role, Role::Mafioso);
}

/// Plays many games with random roles and random (often invalid) inputs, checking that every
/// game ends and nobody sees another player's private messages.
#[test]
fn random_games_always_finish() {
    for seed in 0..150u64 {
        let mut rng = ChaCha8Rng::seed_from_u64(seed);
        let count = rng.random_range(webgame_protocol::MIN_PLAYERS..=webgame_protocol::MAX_PLAYERS);
        let (mut game, mut log) = Game::new(seats(count), seed, Timers::uniform(PHASE), 0).unwrap();
        let mut now = 0;
        let mut phases = 0;
        while !game.is_over() {
            phases += 1;
            assert!(phases < 400, "seed {seed} never finished");
            let all: Vec<PlayerSlot> = game.players().iter().map(|p| p.slot).collect();
            for from in &all {
                let pick = *all.choose(&mut rng).unwrap();
                let other = *all.choose(&mut rng).unwrap();
                let action = match rng.random_range(0..8) {
                    0 => GameAction::Vote(Some(pick)),
                    1 => GameAction::Judgement(
                        *[Verdict::Guilty, Verdict::Innocent, Verdict::Abstain]
                            .choose(&mut rng)
                            .unwrap(),
                    ),
                    2 => GameAction::Jail(Some(pick)),
                    3 => GameAction::Night(Some(NightAction::Activate)),
                    4 => GameAction::Night(Some(NightAction::TwoTargets(pick, other))),
                    5 => GameAction::SetLastWill(format!("seed {seed}")),
                    _ => GameAction::Night(Some(NightAction::Target(pick))),
                };
                if let Ok(out) = game.handle(*from, Input::Action(action), now) {
                    log.extend(out);
                }
                let _ = game
                    .handle(
                        *from,
                        Input::Chat {
                            channel: ChatChannel::Mafia,
                            text: "x".into(),
                        },
                        now,
                    )
                    .map(|out| log.extend(out));
            }
            now = game.deadline().unwrap_or(now);
            log.extend(game.tick(now));
        }
        // Private messages always go to exactly one player, or the right group.
        for outgoing in &log {
            match &outgoing.message {
                ServerMessage::GameStarted(start) => {
                    assert_eq!(outgoing.to, Audience::One(start.you))
                }
                ServerMessage::Notices(_)
                | ServerMessage::Accepted(_)
                | ServerMessage::RoleChanged { .. } => {
                    assert!(matches!(outgoing.to, Audience::One(_)), "{outgoing:?}")
                }
                ServerMessage::Chat(chat) if chat.channel == ChatChannel::Mafia => {
                    let Audience::Many(readers) = &outgoing.to else {
                        panic!("mafia chat to all")
                    };
                    // Readers are the living Mafia at the time it was sent; none can be Town now
                    // unless an Amnesiac changed sides, which only adds Mafia.
                    assert!(
                        readers
                            .iter()
                            .all(|r| game.player(*r).unwrap().role.faction()
                                != webgame_protocol::Faction::Town)
                    );
                }
                _ => {}
            }
        }
    }
}
