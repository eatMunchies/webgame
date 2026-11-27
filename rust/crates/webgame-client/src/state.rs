//! What this player knows, kept up to date from server messages, and how each message reads
//! as a line of text.

use std::collections::BTreeMap;

use webgame_protocol::{
    ACTION_ROUNDS, Accepted, ChatChannel, ChatContext, ChatSender, DayStage, DeathCause,
    DeathReport, FightView, GameOverInfo, GamePhase, GameStart, JailStatus, LobbyInfo, Minigame,
    MinigameResult, Movement, NightAction, NightStage, Notice, Outcome, PlayerSlot, PlayerSummary,
    Role, RoleSlot, SaveReason, ServerMessage, TeamMember, UserId, Verdict, VoteEntry,
};

#[derive(Debug)]
pub struct State {
    pub user_id: Option<UserId>,
    pub lobby: Option<LobbyInfo>,
    pub me: Option<PlayerSlot>,
    pub role: Option<Role>,
    /// Joined the current game after it started: dead from the start, with no role.
    pub spectator: bool,
    /// Whether this is an app that shows the players, your role and your actions on screen (the
    /// Godot client), rather than a terminal. Its log then leaves out the role list, the player
    /// list, the role text and how to type commands, since the screen shows all of that.
    pub app: bool,
    pub players: Vec<PlayerSummary>,
    pub role_list: Vec<RoleSlot>,
    pub team: Vec<TeamMember>,
    pub executioner_target: Option<PlayerSlot>,
    pub will: String,
    pub phase: GamePhase,
    /// When the current phase ends, in Unix milliseconds. Zero when it doesn't.
    pub ends_at_ms: u64,
    pub jail: JailStatus,
    /// Where everyone else's character last was in the town.
    pub positions: BTreeMap<PlayerSlot, Movement>,
    /// What this player has chosen so far in the current phase, so buttons can show it.
    pub choices: Choices,
    /// This player's minigame in the current stage of the night. Between stages it's the last
    /// stage's, until the next one's arrives.
    pub minigame: Option<CurrentMinigame>,
    /// The roles of players whose role is public: the dead (revealed when they died) and,
    /// once the game is over, everyone.
    pub revealed: BTreeMap<PlayerSlot, Role>,
    /// The day votes as the server last counted them. Cleared when the phase changes, so they
    /// only describe the current vote.
    pub votes: Vec<VoteEntry>,
    /// How many votes put someone on trial, from the last count.
    pub votes_needed: u8,
}

/// A minigame being played, or just finished.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CurrentMinigame {
    pub game: Minigame,
    /// When the stage, and so the minigame, ends, in Unix milliseconds.
    pub ends_at_ms: u64,
    /// The fight as the server last sent it.
    pub fight: Option<FightView>,
    /// How it ended, once it has.
    pub result: Option<MinigameResult>,
    /// Whether the server decided it at random.
    pub rolled: bool,
}

/// This player's current choices, as the server confirmed them.
#[derive(Debug, Default)]
pub struct Choices {
    pub vote: Option<PlayerSlot>,
    pub verdict: Option<Verdict>,
    pub jail: Option<PlayerSlot>,
    pub night: Option<NightAction>,
    /// A Copycat's first pick, whose ability they will use. Kept here until they pick who to
    /// use it on, since the server takes both at once.
    pub copy_from: Option<PlayerSlot>,
    /// Who a lynched Jester may haunt tonight.
    pub haunt: Vec<PlayerSlot>,
}

impl Default for State {
    fn default() -> Self {
        State {
            user_id: None,
            lobby: None,
            me: None,
            role: None,
            spectator: false,
            app: false,
            players: Vec::new(),
            role_list: Vec::new(),
            team: Vec::new(),
            executioner_target: None,
            will: String::new(),
            phase: GamePhase::Lobby,
            ends_at_ms: 0,
            jail: JailStatus::Free,
            positions: BTreeMap::new(),
            choices: Choices::default(),
            minigame: None,
            revealed: BTreeMap::new(),
            votes: Vec::new(),
            votes_needed: 0,
        }
    }
}

impl State {
    pub fn in_game(&self) -> bool {
        self.me.is_some() && !matches!(self.phase, GamePhase::Lobby | GamePhase::GameOver)
    }

    /// Whether this player can whisper to `to` now: both alive, by day, and neither of them on
    /// trial.
    pub fn can_whisper(&self, to: PlayerSlot) -> bool {
        self.me.is_some_and(|me| {
            self.alive(me)
                && self.alive(to)
                && webgame_protocol::whisper_allowed(&self.phase, me, to)
        })
    }

    pub(crate) fn alive(&self, slot: PlayerSlot) -> bool {
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

    /// How many votes are on each player right now, during voting. Empty in other stages.
    pub fn vote_tally(&self) -> BTreeMap<PlayerSlot, usize> {
        let mut tally = BTreeMap::new();
        for vote in &self.votes {
            *tally.entry(vote.target).or_insert(0) += 1;
        }
        tally
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
            GamePhase::Night { night, stage } => {
                let stage = match stage {
                    NightStage::Choosing => "Choosing".to_string(),
                    NightStage::Roleblock => "Roleblocks".to_string(),
                    NightStage::Actions { round } => format!("Actions {round}/{ACTION_ROUNDS}"),
                };
                format!("Night {night} {stage}")
            }
            GamePhase::Day { day, stage } => {
                let stage = match stage {
                    DayStage::Morning => "Morning".to_string(),
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
                    DayStage::Execution { accused } => {
                        format!("Execution of {}", self.name(*accused))
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
                if member.ready {
                    line.push_str(" ready");
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
        if self.spectator {
            return "You're a spectator: you joined after the game started.".into();
        }
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

    /// Remembers a Copycat's first pick and says what to do next.
    pub fn copy_from(&mut self, slot: PlayerSlot) -> String {
        self.choices.copy_from = Some(slot);
        format!("Now pick who to use {}'s ability on.", self.name(slot))
    }

    /// Applies a message and returns the lines to show for it, if any.
    pub fn apply(&mut self, message: ServerMessage) -> Vec<String> {
        match message {
            ServerMessage::Welcome { user_id, username } => {
                self.user_id = Some(user_id);
                if self.app {
                    vec![format!("Connected as {username}.")]
                } else {
                    vec![format!("Connected as {username}. Type /help for commands.")]
                }
            }
            ServerMessage::Error(err) => vec![format!("! {err}")],
            ServerMessage::Lobby(info) => {
                let first = self.lobby.as_ref().is_none_or(|l| l.code != info.code);
                let joined = self.lobby.as_ref().map(|l| l.members.len()).unwrap_or(0);
                // The app shows the lobby on screen, so its log only says who came and went.
                let arrivals = if self.app && !first {
                    let before = self
                        .lobby
                        .as_ref()
                        .map(|l| l.members.clone())
                        .unwrap_or_default();
                    let came = info
                        .members
                        .iter()
                        .filter(|m| !before.iter().any(|b| b.user_id == m.user_id))
                        .map(|m| format!("{} joined.", m.name));
                    let went = before
                        .iter()
                        .filter(|b| !info.members.iter().any(|m| m.user_id == b.user_id))
                        .map(|b| format!("{} left.", b.name));
                    came.chain(went).collect()
                } else {
                    Vec::new()
                };
                // Who readied up or took it back, by name, between games.
                let readiness: Vec<String> = match &self.lobby {
                    Some(before) if !first && !info.in_game => info
                        .members
                        .iter()
                        .filter(|m| {
                            before
                                .members
                                .iter()
                                .any(|b| b.user_id == m.user_id && b.ready != m.ready)
                        })
                        .map(|m| {
                            if m.ready {
                                format!("{} is ready.", m.name)
                            } else {
                                format!("{} isn't ready.", m.name)
                            }
                        })
                        .collect(),
                    _ => Vec::new(),
                };
                let now = info.members.len();
                let ended = self.phase == GamePhase::GameOver && !info.in_game;
                self.positions
                    .retain(|slot, _| info.members.iter().any(|m| m.slot == *slot));
                self.lobby = Some(info);
                if ended {
                    self.reset_game();
                }
                if self.app && (first || ended) {
                    let code = &self.lobby.as_ref().unwrap().code;
                    vec![format!("In lobby {code}.")]
                } else if self.app {
                    arrivals.into_iter().chain(readiness).collect()
                } else if first || ended {
                    let code = &self.lobby.as_ref().unwrap().code;
                    let mut lines = vec![format!(
                        "In lobby {code}. Share the code; type /ready when you're ready, and the host types /start once 4 or more players all are."
                    )];
                    lines.push(self.players_text());
                    lines
                } else if joined != now {
                    vec![self.players_text()]
                } else {
                    readiness
                }
            }
            ServerMessage::LeftLobby => {
                self.lobby = None;
                self.positions.clear();
                self.reset_game();
                vec!["You left the lobby.".into()]
            }
            ServerMessage::GameStarted(start) => self.start(start),
            ServerMessage::Phase { phase, ends_at_ms } => {
                if phase.is_day() && !self.phase.is_day() {
                    self.jail = JailStatus::Free;
                    self.choices.jail = None;
                    self.choices.haunt.clear();
                }
                let changed = phase != self.phase;
                // Night actions hold through the night's stages.
                let same_night = matches!(
                    (&phase, &self.phase),
                    (GamePhase::Night { night: a, .. }, GamePhase::Night { night: b, .. }) if a == b
                );
                if changed && !same_night {
                    self.choices.vote = None;
                    self.choices.verdict = None;
                    self.choices.night = None;
                    self.choices.copy_from = None;
                }
                // The night's next stage sends its own minigame right after its phase, so the
                // last one stays until then. A practice game shown for it keeps going rather
                // than closing and starting over between stages.
                if changed && !same_night {
                    self.minigame = None;
                    self.votes.clear();
                }
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
            ServerMessage::Notices(notices) => {
                for notice in &notices {
                    if let Notice::ChooseHaunt { candidates } = notice {
                        self.choices.haunt = candidates.clone();
                    }
                }
                notices
                    .iter()
                    .map(|n| format!("* {}", self.notice(n)))
                    .collect()
            }
            ServerMessage::Deaths(deaths) => self.deaths(deaths),
            ServerMessage::Votes { votes, needed } => {
                self.choices.vote = votes
                    .iter()
                    .find(|v| Some(v.voter) == self.me)
                    .map(|v| v.target);
                let tally = self.votes(&votes, needed);
                let line = match self.vote_change(&votes) {
                    Some(change) => format!("{change} {tally}"),
                    None => tally,
                };
                self.votes = votes;
                self.votes_needed = needed;
                vec![line]
            }
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
            ServerMessage::Moved { slot, movement } => {
                self.positions.insert(slot, movement);
                Vec::new()
            }
            ServerMessage::Minigame { game, ends_at_ms } => {
                self.minigame = Some(CurrentMinigame {
                    game,
                    ends_at_ms,
                    fight: None,
                    result: None,
                    rolled: false,
                });
                match game {
                    Minigame::SkillCheck => {
                        vec!["* Skill check! Your night action only works if you pass.".into()]
                    }
                    Minigame::Fight { attacking: true } => {
                        vec!["* Fight! Win it for your attack to reach your target.".into()]
                    }
                    Minigame::Fight { attacking: false } => {
                        vec!["* You're attacked! Knock out your attacker to survive.".into()]
                    }
                    Minigame::Passive => Vec::new(),
                }
            }
            ServerMessage::Fight(view) => {
                if let Some(minigame) = &mut self.minigame {
                    minigame.fight = Some(view);
                }
                Vec::new()
            }
            ServerMessage::MinigameOver { result, rolled } => {
                if let Some(minigame) = &mut self.minigame {
                    minigame.result = Some(result);
                    minigame.rolled = rolled;
                }
                let line = match result {
                    MinigameResult::Passed => "* You passed the skill check.",
                    MinigameResult::Failed => {
                        "* You failed the skill check. Your action won't work tonight."
                    }
                    MinigameResult::Won => "* You won the fight.",
                    MinigameResult::Lost => "* You lost the fight.",
                };
                let rolled = if rolled { " (rolled)" } else { "" };
                vec![format!("{line}{rolled}")]
            }
        }
    }

    fn reset_game(&mut self) {
        self.me = None;
        self.role = None;
        self.spectator = false;
        self.players.clear();
        self.role_list.clear();
        self.team.clear();
        self.executioner_target = None;
        self.will.clear();
        self.phase = GamePhase::Lobby;
        self.ends_at_ms = 0;
        self.jail = JailStatus::Free;
        self.choices = Choices::default();
        self.minigame = None;
        self.revealed.clear();
        self.votes.clear();
        self.votes_needed = 0;
    }

    fn start(&mut self, start: GameStart) -> Vec<String> {
        self.me = Some(start.you);
        self.spectator = start.spectator;
        self.role = (!start.spectator).then_some(start.role);
        self.players = start.players;
        self.role_list = start.role_list;
        self.team = start.team;
        self.executioner_target = start.executioner_target;
        self.will = start.last_will;
        self.revealed.clear();
        self.votes.clear();
        if self.app {
            return vec![if self.spectator {
                "You joined a game in progress, as a spectator: dead from the start.".into()
            } else {
                "The game begins.".into()
            }];
        }
        if self.spectator {
            return vec![
                "=== You joined a game in progress ===".into(),
                "You're a spectator: dead from the start. Watch, and talk with the dead.".into(),
                self.roles_text(),
                self.players_text(),
            ];
        }
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
            GamePhase::Night {
                stage: NightStage::Choosing,
                ..
            } => return self.night_hint(),
            GamePhase::Night {
                stage: NightStage::Roleblock,
                ..
            } => return "Actions are locked in. The minigames begin.".into(),
            GamePhase::Night { .. } => return String::new(),
            GamePhase::Lobby | GamePhase::GameOver => return String::new(),
            GamePhase::Day { stage, .. } => stage,
        };
        match stage {
            DayStage::Morning => "Morning. The town gathers for the night's dead.".into(),
            DayStage::Discussion => "A new day. Talk it over.".into(),
            DayStage::Voting { .. } if self.app => "Voting is open.".into(),
            DayStage::Voting { .. } => "Voting is open. Vote someone up with /vote N.".into(),
            DayStage::Defense { accused } if me(accused) => {
                "You are on trial. Make your defense; only you can talk.".into()
            }
            DayStage::Defense { accused } => {
                format!("{} is on trial. Hear their defense.", self.name(*accused))
            }
            DayStage::Judgement { accused } if me(accused) => "The town is judging you.".into(),
            DayStage::Judgement { accused } if self.app => {
                format!("Judge {}.", self.name(*accused))
            }
            DayStage::Judgement { accused } => {
                format!("Judge {}: /guilty, /inno or /abstain.", self.name(*accused))
            }
            DayStage::LastWords { accused } => {
                format!(
                    "{} has been convicted. Any last words?",
                    self.name(*accused)
                )
            }
            DayStage::Execution { accused } => {
                format!("{} is led to the guillotine.", self.name(*accused))
            }
        }
    }

    fn night_hint(&self) -> String {
        if self.app {
            return match self.jail {
                JailStatus::Prisoner if self.me.is_some_and(|me| self.alive(me)) => {
                    "Night falls. You are in jail tonight.".into()
                }
                JailStatus::Jailer { prisoner } => {
                    format!("Night falls. You hold {} tonight.", self.name(prisoner))
                }
                _ => "Night falls.".into(),
            };
        }
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
            self.revealed.insert(death.slot, death.role);
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

    /// Who just voted for whom, when `votes` differs from the last tally by one player's vote,
    /// as it does after each vote or unvote. A bigger difference (a new round of voting, or
    /// catching up after a reconnect) isn't one player's doing, so it gets no line.
    fn vote_change(&self, votes: &[VoteEntry]) -> Option<String> {
        let target =
            |list: &[VoteEntry], voter| list.iter().find(|v| v.voter == voter).map(|v| v.target);
        let mut voters: Vec<PlayerSlot> = self.votes.iter().chain(votes).map(|v| v.voter).collect();
        voters.sort();
        voters.dedup();
        let mut changed = voters
            .into_iter()
            .filter(|&voter| target(&self.votes, voter) != target(votes, voter));
        let voter = changed.next()?;
        if changed.next().is_some() {
            return None;
        }
        Some(match target(votes, voter) {
            Some(target) => format!("{} voted for {}.", self.name(voter), self.name(target)),
            None => format!("{} took back their vote.", self.name(voter)),
        })
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
            Accepted::Verdict(verdict) => self.choices.verdict = Some(verdict),
            Accepted::Jail(target) => self.choices.jail = target,
            Accepted::Night(action) => {
                self.choices.night = action;
                self.choices.copy_from = None;
            }
            Accepted::LastWill => {}
        }
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
        self.revealed.extend(info.roles.iter().copied());
        for (slot, role) in &info.roles {
            lines.push(format!("  {} was the {role}", self.name(*slot)));
        }
        lines.push("Everyone can talk now. The host can /start again.".into());
        lines
    }
}

/// How a cause of death reads in a sentence, like "killed by the Mafia".
pub fn cause(cause: DeathCause) -> &'static str {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn game() -> State {
        let mut state = State::default();
        let players = (0..4)
            .map(|n| PlayerSummary {
                slot: PlayerSlot(n),
                name: format!("P{}", n + 1),
                alive: true,
            })
            .collect();
        state.apply(ServerMessage::GameStarted(GameStart {
            you: PlayerSlot(0),
            spectator: false,
            role: Role::Sheriff,
            players,
            role_list: Vec::new(),
            team: Vec::new(),
            executioner_target: None,
            last_will: String::new(),
        }));
        state
    }

    fn day(stage: DayStage) -> ServerMessage {
        ServerMessage::Phase {
            phase: GamePhase::Day { day: 2, stage },
            ends_at_ms: 0,
        }
    }

    #[test]
    fn vote_tally_counts_the_current_vote_only() {
        let mut state = game();
        state.apply(day(DayStage::Voting { trials_left: 3 }));
        let vote = |voter, target| VoteEntry {
            voter: PlayerSlot(voter),
            target: PlayerSlot(target),
        };
        let lines = state.apply(ServerMessage::Votes {
            votes: vec![vote(0, 2), vote(1, 2), vote(3, 1)],
            needed: 3,
        });
        // A whole new list is a catch-up, not one player's vote, so nobody is named.
        assert!(lines.iter().all(|line| !line.contains("voted for")));
        let tally = state.vote_tally();
        assert_eq!(tally[&PlayerSlot(2)], 2);
        assert_eq!(tally[&PlayerSlot(1)], 1);
        assert_eq!(state.votes_needed, 3);

        state.apply(day(DayStage::Defense {
            accused: PlayerSlot(2),
        }));
        assert!(state.vote_tally().is_empty());
    }

    #[test]
    fn the_chat_says_who_voted_for_whom() {
        let mut state = game();
        state.apply(day(DayStage::Voting { trials_left: 3 }));
        let vote = |voter, target| VoteEntry {
            voter: PlayerSlot(voter),
            target: PlayerSlot(target),
        };
        let mut votes = |votes| {
            state
                .apply(ServerMessage::Votes { votes, needed: 3 })
                .join("\n")
        };
        let line = votes(vec![vote(0, 2)]);
        assert!(
            line.starts_with("P1 (1) voted for P3 (3). Votes:"),
            "{line}"
        );
        let line = votes(vec![vote(0, 2), vote(1, 2)]);
        assert!(line.starts_with("P2 (2) voted for P3 (3)."), "{line}");
        let line = votes(vec![vote(0, 1), vote(1, 2)]);
        assert!(line.starts_with("P1 (1) voted for P2 (2)."), "{line}");
        let line = votes(vec![vote(0, 1)]);
        assert!(line.starts_with("P2 (2) took back their vote."), "{line}");
    }

    #[test]
    fn deaths_and_game_over_reveal_roles() {
        let mut state = game();
        state.apply(ServerMessage::Deaths(vec![DeathReport {
            slot: PlayerSlot(2),
            role: Role::Doctor,
            will: String::new(),
            causes: vec![DeathCause::Mafia],
        }]));
        assert_eq!(state.revealed.get(&PlayerSlot(2)), Some(&Role::Doctor));
        assert_eq!(state.revealed.get(&PlayerSlot(1)), None);

        state.apply(ServerMessage::GameOver(GameOverInfo {
            outcome: Outcome::Town,
            winners: Vec::new(),
            roles: vec![(PlayerSlot(1), Role::Mafioso)],
        }));
        assert_eq!(state.revealed.get(&PlayerSlot(1)), Some(&Role::Mafioso));
    }

    fn night(stage: NightStage) -> ServerMessage {
        ServerMessage::Phase {
            phase: GamePhase::Night { night: 1, stage },
            ends_at_ms: 0,
        }
    }

    #[test]
    fn a_minigame_lasts_until_the_next_stage_sends_one_and_ends_at_dawn() {
        let mut state = game();
        state.apply(night(NightStage::Roleblock));
        state.apply(ServerMessage::Minigame {
            game: Minigame::Passive,
            ends_at_ms: 10,
        });
        state.apply(night(NightStage::Actions { round: 1 }));
        let kept = state.minigame.as_ref().map(|m| (m.game, m.ends_at_ms));
        assert_eq!(kept, Some((Minigame::Passive, 10)));
        state.apply(ServerMessage::Minigame {
            game: Minigame::Passive,
            ends_at_ms: 20,
        });
        assert_eq!(state.minigame.as_ref().map(|m| m.ends_at_ms), Some(20));
        state.apply(day(DayStage::Discussion));
        assert_eq!(state.minigame, None);
    }
}
