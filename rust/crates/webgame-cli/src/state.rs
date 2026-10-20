//! What this player knows, kept up to date from server messages, and how each message reads
//! as a line of text.

use webgame_protocol::{
    Accepted, ChatChannel, ChatContext, ChatSender, DayStage, DeathCause, DeathReport,
    GameOverInfo, GamePhase, GameStart, JailStatus, LobbyInfo, NightAction, Notice, Outcome,
    PlayerSlot, PlayerSummary, Role, RoleSlot, SaveReason, ServerMessage, TeamMember, UserId,
    VoteEntry,
};

#[derive(Debug)]
pub struct State {
    pub user_id: Option<UserId>,
    pub lobby: Option<LobbyInfo>,
    pub me: Option<PlayerSlot>,
    pub role: Option<Role>,
    pub players: Vec<PlayerSummary>,
    pub role_list: Vec<RoleSlot>,
    pub team: Vec<TeamMember>,
    pub executioner_target: Option<PlayerSlot>,
    pub will: String,
    pub phase: GamePhase,
    /// When the current phase ends, in Unix milliseconds. Zero when it doesn't.
    pub ends_at_ms: u64,
    pub jail: JailStatus,
}

impl Default for State {
    fn default() -> Self {
        State {
            user_id: None,
            lobby: None,
            me: None,
            role: None,
            players: Vec::new(),
            role_list: Vec::new(),
            team: Vec::new(),
            executioner_target: None,
            will: String::new(),
            phase: GamePhase::Lobby,
            ends_at_ms: 0,
            jail: JailStatus::Free,
        }
    }
}

impl State {
    pub fn in_game(&self) -> bool {
        self.me.is_some() && !matches!(self.phase, GamePhase::Lobby | GamePhase::GameOver)
    }

    fn alive(&self, slot: PlayerSlot) -> bool {
        self.players.iter().any(|p| p.slot == slot && p.alive)
    }

    /// The same chat rules the server uses, so plain text goes where it is allowed.
    pub fn chat_context(&self) -> Option<ChatContext> {
        let slot = self.me?;
        Some(ChatContext {
            phase: self.phase.clone(),
            slot,
            alive: self.alive(slot),
            role: self.role?,
            jail: self.jail,
        })
    }

    /// A player as `Name (3)`.
    pub fn name(&self, slot: PlayerSlot) -> String {
        let name = self
            .players
            .iter()
            .find(|p| p.slot == slot)
            .map(|p| p.name.clone())
            .or_else(|| {
                let lobby = self.lobby.as_ref()?;
                let member = lobby.members.iter().find(|m| m.slot == slot)?;
                Some(member.name.clone())
            })
            .unwrap_or_else(|| "?".into());
        format!("{name} ({slot})")
    }

    fn names(&self, slots: &[PlayerSlot]) -> String {
        if slots.is_empty() {
            return "nobody".into();
        }
        slots
            .iter()
            .map(|s| self.name(*s))
            .collect::<Vec<_>>()
            .join(", ")
    }

    /// A label for the current phase and the time left in it, like `Day 1 Voting 0:42`.
    pub fn clock(&self, now_ms: u64) -> String {
        let label = match &self.phase {
            GamePhase::Lobby => return "Lobby".into(),
            GamePhase::GameOver => return "Game over".into(),
            GamePhase::Night { night } => format!("Night {night}"),
            GamePhase::Day { day, stage } => {
                let stage = match stage {
                    DayStage::Discussion => "Discussion".to_string(),
                    DayStage::Voting { trials_left } => {
                        format!("Voting, {trials_left} trials left")
                    }
                    DayStage::Defense { accused } => format!("Defense of {}", self.name(*accused)),
                    DayStage::Judgement { accused } => {
                        format!("Judgement of {}", self.name(*accused))
                    }
                    DayStage::LastWords { accused } => {
                        format!("Last words of {}", self.name(*accused))
                    }
                };
                format!("Day {day} {stage}")
            }
        };
        let left = self.ends_at_ms.saturating_sub(now_ms).div_ceil(1000);
        format!("{label} {}:{:02}", left / 60, left % 60)
    }

    pub fn players_text(&self) -> String {
        if self.players.is_empty() {
            let Some(lobby) = &self.lobby else {
                return "You aren't in a lobby.".into();
            };
            let mut lines = vec![format!("Lobby {}:", lobby.code)];
            for member in &lobby.members {
                let mut line = format!("  {}", self.name(member.slot));
                if member.user_id == lobby.host {
                    line.push_str(" host");
                }
                if !member.connected {
                    line.push_str(" (disconnected)");
                }
                lines.push(line);
            }
            return lines.join("\n");
        }
        let mut lines = vec!["Players:".to_string()];
        for player in &self.players {
            let mut line = format!("  {}", self.name(player.slot));
            if !player.alive {
                line.push_str(" dead");
            }
            if Some(player.slot) == self.me {
                line.push_str(" (you)");
            }
            if let Some(member) = self.team.iter().find(|t| t.slot == player.slot) {
                line.push_str(&format!(" [{}]", member.role));
            }
            if Some(player.slot) == self.executioner_target {
                line.push_str(" [your target]");
            }
            lines.push(line);
        }
        lines.join("\n")
    }

    pub fn role_text(&self) -> String {
        let Some(role) = self.role else {
            return "You don't have a role until the game starts.".into();
        };
        let mut lines = vec![
            format!("You are the {role} ({}).", role.category().name()),
            format!("  Ability: {}", role.ability()),
            format!("  Goal: {}", role.goal()),
        ];
        if let Some(target) = self.executioner_target {
            lines.push(format!("  Your target: {}", self.name(target)));
        }
        if !self.team.is_empty() {
            let team: Vec<String> = self
                .team
                .iter()
                .map(|t| {
                    let dead = if t.alive { "" } else { ", dead" };
                    format!("{} {}{dead}", self.name(t.slot), t.role)
                })
                .collect();
            lines.push(format!("  Team: {}", team.join("; ")));
        }
        if self.will.is_empty() {
            lines.push("  Last will: (empty, set it with /will text)".into());
        } else {
            lines.push(format!(
                "  Last will:\n    {}",
                self.will.replace('\n', "\n    ")
            ));
        }
        lines.join("\n")
    }

    pub fn roles_text(&self) -> String {
        if self.role_list.is_empty() {
            return "The role list is shown when the game starts.".into();
        }
        let slots: Vec<String> = self.role_list.iter().map(|r| format!("  {r}")).collect();
        format!("Role list:\n{}", slots.join("\n"))
    }

    /// Applies a message and returns the lines to show for it, if any.
    pub fn apply(&mut self, message: ServerMessage) -> Vec<String> {
        match message {
            ServerMessage::Welcome { user_id, username } => {
                self.user_id = Some(user_id);
                vec![format!("Connected as {username}. Type /help for commands.")]
            }
            ServerMessage::Error(err) => vec![format!("! {err}")],
            ServerMessage::Lobby(info) => {
                let first = self.lobby.as_ref().is_none_or(|l| l.code != info.code);
                let joined = self.lobby.as_ref().map(|l| l.members.len()).unwrap_or(0);
                let now = info.members.len();
                let ended = self.phase == GamePhase::GameOver && !info.in_game;
                self.lobby = Some(info);
                if ended {
                    self.reset_game();
                }
                if first || ended {
                    let code = &self.lobby.as_ref().unwrap().code;
                    let mut lines = vec![format!(
                        "In lobby {code}. Share the code; the host types /start with 4 or more players."
                    )];
                    lines.push(self.players_text());
                    lines
                } else if joined != now {
                    vec![self.players_text()]
                } else {
                    Vec::new()
                }
            }
            ServerMessage::LeftLobby => {
                self.lobby = None;
                self.reset_game();
                vec!["You left the lobby.".into()]
            }
            ServerMessage::GameStarted(start) => self.start(start),
            ServerMessage::Phase { phase, ends_at_ms } => {
                if phase.is_day() && !self.phase.is_day() {
                    self.jail = JailStatus::Free;
                }
                let changed = phase != self.phase;
                self.phase = phase;
                self.ends_at_ms = ends_at_ms;
                if !changed {
                    return Vec::new();
                }
                let hint = self.phase_hint();
                if hint.is_empty() {
                    Vec::new()
                } else {
                    vec![hint]
                }
            }
            ServerMessage::Chat(chat) => vec![self.chat_line(chat.channel, chat.from, &chat.text)],
            ServerMessage::Whispered { from, to } => {
                if Some(from) == self.me || Some(to) == self.me {
                    Vec::new()
                } else {
                    vec![format!(
                        "{} whispers to {}.",
                        self.name(from),
                        self.name(to)
                    )]
                }
            }
            ServerMessage::Notices(notices) => notices
                .iter()
                .map(|n| format!("* {}", self.notice(n)))
                .collect(),
            ServerMessage::Deaths(deaths) => self.deaths(deaths),
            ServerMessage::Votes { votes, needed } => vec![self.votes(&votes, needed)],
            ServerMessage::TrialResult {
                accused,
                votes,
                guilty,
                innocent,
                convicted,
            } => {
                let mut lines = vec![format!(
                    "The town voted {guilty} guilty, {innocent} innocent: {} is {}.",
                    self.name(accused),
                    if convicted { "convicted" } else { "spared" }
                )];
                for (voter, verdict) in votes {
                    lines.push(format!("  {} voted {verdict:?}", self.name(voter)));
                }
                lines
            }
            ServerMessage::RoleChanged { role } => {
                self.role = Some(role);
                vec![format!("* You are now the {role}. {}", role.ability())]
            }
            ServerMessage::Team(team) => {
                self.team = team;
                let mut lines = vec!["* Your team changed.".to_string()];
                lines.push(self.role_text());
                lines
            }
            ServerMessage::Remembered { role } => {
                vec![format!(
                    "An Amnesiac has remembered that they were the {role}."
                )]
            }
            ServerMessage::Accepted(accepted) => vec![self.accepted(accepted)],
            ServerMessage::GameOver(info) => self.game_over(info),
        }
    }

    fn reset_game(&mut self) {
        self.me = None;
        self.role = None;
        self.players.clear();
        self.role_list.clear();
        self.team.clear();
        self.executioner_target = None;
        self.will.clear();
        self.phase = GamePhase::Lobby;
        self.ends_at_ms = 0;
        self.jail = JailStatus::Free;
    }

    fn start(&mut self, start: GameStart) -> Vec<String> {
        self.me = Some(start.you);
        self.role = Some(start.role);
        self.players = start.players;
        self.role_list = start.role_list;
        self.team = start.team;
        self.executioner_target = start.executioner_target;
        self.will = start.last_will;
        vec![
            "=== The game begins ===".into(),
            self.roles_text(),
            self.players_text(),
            self.role_text(),
        ]
    }

    /// A line announcing the phase that just began, with what this player can do in it.
    fn phase_hint(&self) -> String {
        let me = |slot: &PlayerSlot| Some(*slot) == self.me;
        let stage = match &self.phase {
            GamePhase::Night { .. } => return self.night_hint(),
            GamePhase::Lobby | GamePhase::GameOver => return String::new(),
            GamePhase::Day { stage, .. } => stage,
        };
        match stage {
            DayStage::Discussion => "A new day. Talk it over.".into(),
            DayStage::Voting { .. } => "Voting is open. Vote someone up with /vote N.".into(),
            DayStage::Defense { accused } if me(accused) => {
                "You are on trial. Make your defense; only you can talk.".into()
            }
            DayStage::Defense { accused } => {
                format!("{} is on trial. Hear their defense.", self.name(*accused))
            }
            DayStage::Judgement { accused } if me(accused) => "The town is judging you.".into(),
            DayStage::Judgement { accused } => {
                format!("Judge {}: /guilty, /inno or /abstain.", self.name(*accused))
            }
            DayStage::LastWords { accused } => {
                format!(
                    "{} has been convicted. Any last words?",
                    self.name(*accused)
                )
            }
        }
    }

    fn night_hint(&self) -> String {
        if self.me.is_some_and(|me| !self.alive(me)) {
            return "Night falls. Talk with the dead by typing.".into();
        }
        match self.jail {
            JailStatus::Prisoner => {
                return "You are in jail tonight. Talk to the Jailer by typing.".into();
            }
            JailStatus::Jailer { prisoner } => {
                return format!(
                    "You hold {} tonight. Talk to them by typing; /execute to execute.",
                    self.name(prisoner)
                );
            }
            JailStatus::Free => {}
        }
        let how = match self.role {
            Some(Role::Veteran) => "/alert to go on alert.",
            Some(Role::Survivor) => "/vest to put on a vest.",
            Some(Role::Arsonist) => "/target N to douse, or /ignite.",
            Some(Role::Copycat) => "/target N M to use N's ability on M.",
            Some(Role::Medium) => "Type to talk with the dead.",
            Some(Role::Jailer | Role::Executioner | Role::Jester) | None => "Wait for morning.",
            Some(_) => "/target N to use your ability.",
        };
        format!("Night falls. {how}")
    }

    fn chat_line(&self, channel: ChatChannel, from: ChatSender, text: &str) -> String {
        let from = match from {
            ChatSender::Player(slot) => self.name(slot),
            ChatSender::Jailer => "Jailer".into(),
            ChatSender::Medium => "Medium".into(),
        };
        match channel {
            ChatChannel::Lobby | ChatChannel::General => format!("{from}: {text}"),
            ChatChannel::Whisper { to } => format!("[whisper to {}] {from}: {text}", self.name(to)),
            ChatChannel::Jail => format!("[jail] {from}: {text}"),
            ChatChannel::Mafia => format!("[mafia] {from}: {text}"),
            ChatChannel::Dead => format!("[dead] {from}: {text}"),
        }
    }

    fn deaths(&mut self, deaths: Vec<DeathReport>) -> Vec<String> {
        if deaths.is_empty() && self.phase.is_night() {
            return vec!["Nobody died last night.".into()];
        }
        let mut lines = Vec::new();
        for death in deaths {
            if let Some(player) = self.players.iter_mut().find(|p| p.slot == death.slot) {
                player.alive = false;
            }
            let causes: Vec<&str> = death.causes.iter().map(|c| cause(*c)).collect();
            lines.push(format!(
                "{} died ({}). They were the {}.",
                self.name(death.slot),
                causes.join(", "),
                death.role
            ));
            if death.will.trim().is_empty() {
                lines.push("  We couldn't find a last will.".into());
            } else {
                lines.push(format!(
                    "  Last will:\n    {}",
                    death.will.replace('\n', "\n    ")
                ));
            }
            if Some(death.slot) == self.me {
                lines.push("You are dead. You can talk with the dead by typing.".into());
            }
        }
        lines
    }

    fn votes(&self, votes: &[VoteEntry], needed: u8) -> String {
        let mut tally: Vec<(PlayerSlot, usize)> = Vec::new();
        for vote in votes {
            match tally.iter_mut().find(|(t, _)| *t == vote.target) {
                Some((_, count)) => *count += 1,
                None => tally.push((vote.target, 1)),
            }
        }
        if tally.is_empty() {
            return format!("Votes: none yet ({needed} needed to put someone on trial).");
        }
        let counts: Vec<String> = tally
            .iter()
            .map(|(target, count)| format!("{} {count}", self.name(*target)))
            .collect();
        format!("Votes: {} ({needed} needed)", counts.join(", "))
    }

    fn accepted(&mut self, accepted: Accepted) -> String {
        match accepted {
            Accepted::LastWill => "Last will saved.".into(),
            Accepted::Verdict(verdict) => format!("You voted {verdict:?}."),
            Accepted::Jail(Some(slot)) => format!("You will jail {} tonight.", self.name(slot)),
            Accepted::Jail(None) => "You won't jail anyone tonight.".into(),
            Accepted::Night(None) => "You will stay home tonight.".into(),
            Accepted::Night(Some(NightAction::Target(slot))) => {
                format!("Tonight you target {}.", self.name(slot))
            }
            Accepted::Night(Some(NightAction::TwoTargets(a, b))) => {
                format!("Tonight you target {} and {}.", self.name(a), self.name(b))
            }
            Accepted::Night(Some(NightAction::Activate)) => "Tonight you use your ability.".into(),
        }
    }

    fn notice(&self, notice: &Notice) -> String {
        match notice {
            Notice::Jailed => "You were hauled off to jail.".into(),
            Notice::JailedSomeone { prisoner } => format!("You jailed {}.", self.name(*prisoner)),
            Notice::LostExecutions => {
                "You executed a Town member and can't execute anymore.".into()
            }
            Notice::Roleblocked => "Someone occupied your night. You were roleblocked.".into(),
            Notice::RoleblockImmune => "Someone tried to roleblock you, but you're immune.".into(),
            Notice::Attacked { saved } => format!(
                "You were attacked, but {}.",
                match saved {
                    SaveReason::Defense => "your defense was too strong",
                    SaveReason::Healed => "a Doctor healed you",
                    SaveReason::Guarded => "a Bodyguard fought off your attacker",
                    SaveReason::Trapped => "a trap caught your attacker",
                    SaveReason::Jailed => "you were safe in jail",
                }
            ),
            Notice::TargetAttacked { target } => {
                format!("{} was attacked tonight.", self.name(*target))
            }
            Notice::TrapTriggered { target } => {
                format!("Your trap at {}'s house went off.", self.name(*target))
            }
            Notice::ShotVisitor => "You shot someone who visited you.".into(),
            Notice::Doused => "You were doused in gas.".into(),
            Notice::Poisoned => {
                "You were poisoned. You'll die tomorrow night unless healed.".into()
            }
            Notice::PoisonCured => "A Doctor cured your poison.".into(),
            Notice::SheriffResult { target, suspicious } => format!(
                "{} is {}.",
                self.name(*target),
                if *suspicious {
                    "suspicious"
                } else {
                    "not suspicious"
                }
            ),
            Notice::InvestigatorResult { target, roles } => {
                let roles: Vec<String> = roles.iter().map(Role::to_string).collect();
                format!("{} could be a {}.", self.name(*target), roles.join(", "))
            }
            Notice::ConsigliereResult { target, role } => {
                format!("{} is the {role}.", self.name(*target))
            }
            Notice::LookoutResult { target, visitors } => format!(
                "{} was visited by {}.",
                self.name(*target),
                self.names(visitors)
            ),
            Notice::TrackerResult { target, visited } => {
                format!("{} visited {}.", self.name(*target), self.names(visited))
            }
            Notice::SpyMafiaVisits { targets } => {
                format!("The Mafia visited {}.", self.names(targets))
            }
            Notice::SpyBug { target, heard } => {
                let heard: Vec<String> = heard.iter().map(|n| self.notice(n)).collect();
                if heard.is_empty() {
                    format!("Your bug on {} heard nothing.", self.name(*target))
                } else {
                    format!(
                        "Your bug on {} heard: {}",
                        self.name(*target),
                        heard.join(" ")
                    )
                }
            }
            Notice::CopycatLearned {
                target,
                role,
                copied,
            } => {
                if *copied {
                    format!(
                        "{} is the {role}. You used their ability.",
                        self.name(*target)
                    )
                } else {
                    format!(
                        "{} is the {role}, whose ability you can't copy.",
                        self.name(*target)
                    )
                }
            }
            Notice::SawAmbusher { ambusher } => {
                format!(
                    "You saw {} lying in wait. They're the Ambusher.",
                    self.name(*ambusher)
                )
            }
            Notice::ChooseHaunt { candidates } => format!(
                "You were lynched! Haunt one of the guilty voters with /target N: {}.",
                self.names(candidates)
            ),
        }
    }

    fn game_over(&mut self, info: GameOverInfo) -> Vec<String> {
        self.phase = GamePhase::GameOver;
        let outcome = match info.outcome {
            Outcome::Town => "The Town wins!".to_string(),
            Outcome::Mafia => "The Mafia wins!".to_string(),
            Outcome::Solo(role) => format!("The {role} wins!"),
            Outcome::Draw => "It's a draw.".to_string(),
        };
        let mut lines = vec![format!("=== Game over. {outcome} ===")];
        lines.push(format!("Winners: {}", self.names(&info.winners)));
        for (slot, role) in &info.roles {
            lines.push(format!("  {} was the {role}", self.name(*slot)));
        }
        lines.push("Everyone can talk now. The host can /start again.".into());
        lines
    }
}

fn cause(cause: DeathCause) -> &'static str {
    match cause {
        DeathCause::Lynched => "lynched by the town",
        DeathCause::Mafia => "killed by the Mafia",
        DeathCause::SerialKiller => "stabbed by a Serial Killer",
        DeathCause::Arsonist => "burned by an Arsonist",
        DeathCause::Vigilante => "shot by a Vigilante",
        DeathCause::Veteran => "shot by a Veteran",
        DeathCause::Jailer => "executed by the Jailer",
        DeathCause::Bodyguard => "killed by a Bodyguard",
        DeathCause::Trap => "caught in a trap",
        DeathCause::Poison => "poisoned",
        DeathCause::Haunted => "haunted by a Jester",
        DeathCause::Guilt => "died of guilt",
    }
}
