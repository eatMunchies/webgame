use std::collections::{BTreeMap, BTreeSet};

use rand::seq::IndexedRandom;
use rand::{RngExt, SeedableRng};
use rand_chacha::ChaCha8Rng;
use webgame_protocol::{
    Accepted, ChatChannel, ChatContext, ChatMessage, ChatSender, DayStage, DeathCause, DeathReport,
    ErrorCode, FIGHT_ROUNDS, GameAction, GameOverInfo, GamePhase, GameStart, JailStatus,
    MAX_CHAT_LEN, MAX_PLAYERS, MAX_WILL_LEN, MIN_PLAYERS, Minigame, MinigamePlay, MinigameResult,
    NightAction, NightStage, Notice, PlayerSlot, PlayerSummary, Role, RoleSlot, ServerError,
    ServerMessage, TRIALS_PER_DAY, TargetRule, TeamMember, Verdict, VoteEntry,
};

use crate::duel::Duel;
use crate::night::{self, Jail, Stage};
use crate::{Audience, Outgoing, Player, Seat, Timers, setup, win};

/// How likely a rolled skill check is to pass.
pub const ROLL_PASS_CHANCE: f64 = 0.75;
/// How likely the attacker is to win a rolled fight.
pub const FIGHT_ROLL_CHANCE: f64 = 0.5;

/// Something a player does in a game: chat, or one of the game actions.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Input {
    Chat { channel: ChatChannel, text: String },
    Action(GameAction),
}

/// One game, from dealing roles to the win.
///
/// The phase sequence is Day 0 (discussion only), Night 1, Day 1, Night 2, and so on. Each day
/// runs Discussion, then Voting. Enough votes on one player put them on trial (Defense, then
/// Judgement); a guilty verdict leads to LastWords and the lynch, which ends the day. Otherwise
/// voting picks up where it left off, until [`TRIALS_PER_DAY`] trials have been held or voting
/// time runs out.
///
/// Each night runs the [`NightStage`]s. Actions are picked while Choosing and locked after. At
/// the start of every later stage each living player is given a minigame for it, from
/// [`night::plan`]: a skill check, a fight, or a passive game. A skill check nobody reports by
/// the end of its stage fails, and a fight still going then is the victim's. The night is
/// resolved after the last stage, from those results.
pub struct Game {
    players: Vec<Player>,
    role_list: Vec<RoleSlot>,
    phase: GamePhase,
    deadline: Option<u64>,
    timers: Timers,
    rng: ChaCha8Rng,
    /// Day votes, voter to target.
    votes: BTreeMap<PlayerSlot, PlayerSlot>,
    /// Judgement votes in the current trial.
    verdicts: BTreeMap<PlayerSlot, Verdict>,
    /// Trials still allowed today.
    trials_left: u8,
    /// Voting time left when the current trial started, to resume with if it fails.
    voting_left: u64,
    /// Who the Jailer picked today, to jail tonight.
    jail_choice: Option<PlayerSlot>,
    /// Tonight's jailing.
    jail: Option<Jail>,
    night_actions: BTreeMap<PlayerSlot, NightAction>,
    /// The night after a Jester is lynched: who they may haunt (those who voted guilty).
    haunt_candidates: Vec<PlayerSlot>,
    lynched_today: bool,
    /// Day and night cycles in a row with no deaths.
    quiet_cycles: u32,
    result: Option<GameOverInfo>,
    /// Whether players may have the server decide their minigames at random.
    rolls: bool,
    /// How tonight's minigames have gone so far.
    results: night::Results,
    /// Each player's minigame in the current stage of the night.
    minigames: BTreeMap<PlayerSlot, Play>,
    /// The fights in the current stage of the night.
    duels: Vec<Duel>,
    /// Tonight's Kill stage minigames, by round, worked out when it starts.
    kill_rounds: Vec<Vec<Assigned>>,
    /// The latest time the game has been given, for timing fight views.
    last_tick: u64,
}

/// A player's minigame in the current stage of the night.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Play {
    Check,
    /// An index into the stage's fights.
    Fight(usize),
    Passive,
}

/// A minigame that decides something.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Assigned {
    Check(PlayerSlot),
    Fight {
        attacker: PlayerSlot,
        victim: PlayerSlot,
    },
}

impl Assigned {
    fn players(self) -> Vec<PlayerSlot> {
        match self {
            Assigned::Check(player) => vec![player],
            Assigned::Fight { attacker, victim } => vec![attacker, victim],
        }
    }
}

fn error(code: ErrorCode, message: &str) -> ServerError {
    ServerError::new(code, message)
}

impl Game {
    /// Starts a game: deals roles from the list for this many players and begins Day 0.
    /// `seed` decides the roles and every other random choice, so a game can be replayed.
    pub fn new(
        seats: Vec<Seat>,
        seed: u64,
        timers: Timers,
        now: u64,
    ) -> Result<(Game, Vec<Outgoing>), ServerError> {
        let mut rng = ChaCha8Rng::seed_from_u64(seed);
        let list = setup::role_list(seats.len());
        let mut players = Self::seat_players(seats, Role::Survivor)?;
        setup::deal(&mut players, &list, &mut rng);
        Ok(Self::begin(players, list, rng, timers, now))
    }

    /// Starts a game with chosen roles, given in seat order, instead of rolled ones. Executioners
    /// target the first Town member other than the Jailer, if there is one.
    pub fn with_roles(
        seats: Vec<Seat>,
        roles: &[Role],
        seed: u64,
        timers: Timers,
        now: u64,
    ) -> Result<(Game, Vec<Outgoing>), ServerError> {
        if roles.len() != seats.len() {
            return Err(error(ErrorCode::BadMessage, "one role per seat"));
        }
        let mut players = Self::seat_players(seats, Role::Survivor)?;
        for (player, role) in players.iter_mut().zip(roles) {
            player.become_role(*role);
        }
        let first_town = players
            .iter()
            .find(|p| p.faction() == webgame_protocol::Faction::Town && p.role != Role::Jailer)
            .map(|p| p.slot);
        for player in players.iter_mut().filter(|p| p.role == Role::Executioner) {
            player.executioner_target = first_town;
        }
        let list = roles.iter().map(|role| RoleSlot::Exact(*role)).collect();
        Ok(Self::begin(
            players,
            list,
            ChaCha8Rng::seed_from_u64(seed),
            timers,
            now,
        ))
    }

    fn seat_players(seats: Vec<Seat>, role: Role) -> Result<Vec<Player>, ServerError> {
        if seats.len() < MIN_PLAYERS {
            return Err(error(
                ErrorCode::NotEnoughPlayers,
                &format!("A game needs at least {MIN_PLAYERS} players."),
            ));
        }
        if seats.len() > MAX_PLAYERS {
            return Err(error(
                ErrorCode::LobbyFull,
                "Too many players for one game.",
            ));
        }
        let mut players: Vec<Player> = seats
            .into_iter()
            .map(|seat| Player::new(seat.slot, seat.user_id, seat.name, role))
            .collect();
        players.sort_by_key(|p| p.slot);
        if players.windows(2).any(|pair| pair[0].slot == pair[1].slot) {
            return Err(error(ErrorCode::BadMessage, "two players share a seat"));
        }
        Ok(players)
    }

    fn begin(
        players: Vec<Player>,
        role_list: Vec<RoleSlot>,
        rng: ChaCha8Rng,
        timers: Timers,
        now: u64,
    ) -> (Game, Vec<Outgoing>) {
        let mut game = Game {
            players,
            role_list,
            phase: GamePhase::Lobby,
            deadline: None,
            timers,
            rng,
            votes: BTreeMap::new(),
            verdicts: BTreeMap::new(),
            trials_left: TRIALS_PER_DAY,
            voting_left: 0,
            jail_choice: None,
            jail: None,
            night_actions: BTreeMap::new(),
            haunt_candidates: Vec::new(),
            lynched_today: false,
            quiet_cycles: 0,
            result: None,
            rolls: false,
            results: night::Results::default(),
            minigames: BTreeMap::new(),
            duels: Vec::new(),
            kill_rounds: Vec::new(),
            last_tick: now,
        };
        let mut out: Vec<Outgoing> = game
            .players
            .iter()
            .map(|p| Outgoing::one(p.slot, ServerMessage::GameStarted(game.start_for(p.slot))))
            .collect();
        game.set_phase(
            GamePhase::Day {
                day: 0,
                stage: DayStage::Discussion,
            },
            now + timers.day_zero,
            &mut out,
        );
        (game, out)
    }

    /// Lets players send [`MinigamePlay::Roll`] to have the server decide their minigames at
    /// random, for clients with no way to show them. Off unless turned on.
    pub fn allow_rolls(&mut self, allow: bool) {
        self.rolls = allow;
    }

    pub fn phase(&self) -> &GamePhase {
        &self.phase
    }

    /// When the current phase ends, in the same milliseconds passed to [`Game::tick`]. None once
    /// the game is over.
    pub fn deadline(&self) -> Option<u64> {
        self.deadline
    }

    /// When [`Game::tick`] next has something to do: the end of the phase, or sooner when a
    /// move in a fight lands.
    pub fn wake_at(&self) -> Option<u64> {
        [self.deadline, self.next_landing()]
            .into_iter()
            .flatten()
            .min()
    }

    pub fn players(&self) -> &[Player] {
        &self.players
    }

    pub fn player(&self, slot: PlayerSlot) -> Option<&Player> {
        self.players.iter().find(|p| p.slot == slot)
    }

    pub fn result(&self) -> Option<&GameOverInfo> {
        self.result.as_ref()
    }

    pub fn is_over(&self) -> bool {
        self.result.is_some()
    }

    /// Everything a player needs to pick up a game after reconnecting.
    pub fn snapshot(&self, slot: PlayerSlot) -> Vec<ServerMessage> {
        let mut messages = vec![
            ServerMessage::GameStarted(self.start_for(slot)),
            ServerMessage::Phase {
                phase: self.phase.clone(),
                ends_at_ms: self.deadline.unwrap_or(0),
            },
        ];
        if matches!(
            self.phase,
            GamePhase::Day {
                stage: DayStage::Voting { .. },
                ..
            }
        ) {
            messages.push(self.votes_message());
        }
        if let Some(result) = &self.result {
            messages.push(ServerMessage::GameOver(result.clone()));
        }
        if let Some(play) = self.minigames.get(&slot).copied()
            && !self.minigame_over(slot, play)
        {
            messages.push(ServerMessage::Minigame {
                game: self.minigame_kind(slot, play),
                ends_at_ms: self.deadline.unwrap_or(0),
            });
            if let Play::Fight(i) = play
                && let Some(view) = self.duels[i].view(slot, self.last_tick)
            {
                messages.push(ServerMessage::Fight(view));
            }
        }
        messages
    }

    /// Moves through every phase whose deadline is at or before `now`, landing fight moves due
    /// on the way.
    pub fn tick(&mut self, now: u64) -> Vec<Outgoing> {
        let mut out = Vec::new();
        self.last_tick = self.last_tick.max(now);
        loop {
            if let Some(at) = self.next_landing()
                && at <= now
                && self.deadline.is_none_or(|deadline| at < deadline)
            {
                self.land(at, &mut out);
                continue;
            }
            match self.deadline {
                // The next phase is timed from when this one was due to end, not from `now`,
                // so a late tick doesn't stretch the game.
                Some(deadline) if now >= deadline => self.advance(deadline, &mut out),
                _ => break,
            }
        }
        out
    }

    /// Applies one player's input. Returns the messages it causes, or why it was refused.
    pub fn handle(
        &mut self,
        from: PlayerSlot,
        input: Input,
        now: u64,
    ) -> Result<Vec<Outgoing>, ServerError> {
        if self.player(from).is_none() {
            return Err(error(ErrorCode::NotAllowedNow, "You aren't in this game."));
        }
        let mut out = self.tick(now);
        match input {
            Input::Chat { channel, text } => self.chat(from, channel, text, &mut out)?,
            Input::Action(action) => self.action(from, action, now, &mut out)?,
        }
        Ok(out)
    }

    // ----- Chat -----

    fn chat_context(&self, slot: PlayerSlot) -> ChatContext {
        let player = self.player(slot).expect("checked by the caller");
        let jail = match self.jail {
            Some(jail) if jail.jailer == slot => JailStatus::Jailer {
                prisoner: jail.prisoner,
            },
            Some(jail) if jail.prisoner == slot => JailStatus::Prisoner,
            _ => JailStatus::Free,
        };
        ChatContext {
            phase: self.phase.clone(),
            slot,
            alive: player.alive,
            role: player.role,
            jail,
        }
    }

    fn chat(
        &mut self,
        from: PlayerSlot,
        channel: ChatChannel,
        text: String,
        out: &mut Vec<Outgoing>,
    ) -> Result<(), ServerError> {
        let text = text.trim().to_string();
        if text.is_empty() {
            return Err(error(ErrorCode::BadMessage, "Say something."));
        }
        if text.chars().count() > MAX_CHAT_LEN {
            return Err(error(ErrorCode::TooLong, "That message is too long."));
        }
        let me = self.chat_context(from);
        if !me.can_send(channel) {
            return Err(error(
                ErrorCode::NotAllowedNow,
                "You can't talk there right now.",
            ));
        }
        let (sender, to) = match channel {
            ChatChannel::Whisper { to } => {
                if !self.player(to).is_some_and(|p| p.alive) {
                    return Err(error(
                        ErrorCode::InvalidTarget,
                        "You can only whisper to the living.",
                    ));
                }
                out.push(Outgoing::all(ServerMessage::Whispered { from, to }));
                (ChatSender::Player(from), Audience::Many(vec![from, to]))
            }
            ChatChannel::Jail => {
                let jail = self.jail.expect("can_send checked there is a jail");
                let sender = if from == jail.jailer {
                    ChatSender::Jailer
                } else {
                    ChatSender::Player(from)
                };
                (sender, Audience::Many(vec![jail.jailer, jail.prisoner]))
            }
            ChatChannel::Dead if me.alive => (ChatSender::Medium, self.readers(channel)),
            _ => (ChatSender::Player(from), self.readers(channel)),
        };
        out.push(Outgoing {
            to,
            message: ServerMessage::Chat(ChatMessage {
                channel,
                from: sender,
                text,
            }),
        });
        Ok(())
    }

    fn readers(&self, channel: ChatChannel) -> Audience {
        if channel == ChatChannel::General {
            return Audience::All;
        }
        Audience::Many(
            self.players
                .iter()
                .map(|p| p.slot)
                .filter(|slot| self.chat_context(*slot).can_read(channel))
                .collect(),
        )
    }

    // ----- Actions -----

    fn action(
        &mut self,
        from: PlayerSlot,
        action: GameAction,
        now: u64,
        out: &mut Vec<Outgoing>,
    ) -> Result<(), ServerError> {
        let player = self.player(from).expect("checked by the caller").clone();
        match action {
            GameAction::SetLastWill(will) => {
                if !player.alive || self.is_over() {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "Your will is already read.",
                    ));
                }
                if will.chars().count() > MAX_WILL_LEN {
                    return Err(error(ErrorCode::TooLong, "That will is too long."));
                }
                self.player_mut(from).will = will;
                out.push(Outgoing::one(
                    from,
                    ServerMessage::Accepted(Accepted::LastWill),
                ));
            }
            GameAction::Vote(target) => {
                let GamePhase::Day {
                    stage: DayStage::Voting { .. },
                    ..
                } = self.phase
                else {
                    return Err(error(ErrorCode::NotAllowedNow, "It isn't time to vote."));
                };
                if !player.alive {
                    return Err(error(ErrorCode::NotAllowedNow, "The dead can't vote."));
                }
                match target {
                    Some(target) => {
                        if target == from || !self.is_alive(target) {
                            return Err(error(
                                ErrorCode::InvalidTarget,
                                "Vote for someone else who is alive.",
                            ));
                        }
                        self.votes.insert(from, target);
                    }
                    None => {
                        self.votes.remove(&from);
                    }
                }
                out.push(Outgoing::all(self.votes_message()));
                if let Some(target) = target
                    && self.votes.values().filter(|t| **t == target).count() >= self.votes_needed()
                {
                    self.start_trial(target, now, out);
                }
            }
            GameAction::Judgement(verdict) => {
                let Some(accused) = self.phase.accused() else {
                    return Err(error(ErrorCode::NotAllowedNow, "Nobody is on trial."));
                };
                let judging = matches!(
                    self.phase,
                    GamePhase::Day {
                        stage: DayStage::Judgement { .. },
                        ..
                    }
                );
                if !judging || !player.alive || from == accused {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "You can't judge right now.",
                    ));
                }
                self.verdicts.insert(from, verdict);
                out.push(Outgoing::one(
                    from,
                    ServerMessage::Accepted(Accepted::Verdict(verdict)),
                ));
            }
            GameAction::Jail(target) => {
                if player.role != Role::Jailer || !player.alive || !self.phase.is_day() {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "Only a living Jailer picks a prisoner, by day.",
                    ));
                }
                if let Some(target) = target
                    && (target == from || !self.is_alive(target))
                {
                    return Err(error(
                        ErrorCode::InvalidTarget,
                        "Jail someone else who is alive.",
                    ));
                }
                self.jail_choice = target;
                out.push(Outgoing::one(
                    from,
                    ServerMessage::Accepted(Accepted::Jail(target)),
                ));
            }
            GameAction::Night(action) => {
                if !self.phase.is_night() {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "Night actions are for the night.",
                    ));
                }
                if !self.phase.is_choosing() {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "Tonight's actions are locked in.",
                    ));
                }
                match action {
                    Some(action) => {
                        self.check_night_action(&player, action)?;
                        self.night_actions.insert(from, action);
                    }
                    None => {
                        self.night_actions.remove(&from);
                    }
                }
                out.push(Outgoing::one(
                    from,
                    ServerMessage::Accepted(Accepted::Night(action)),
                ));
            }
            GameAction::Minigame(play) => self.minigame(from, play, now, out)?,
        }
        Ok(())
    }

    fn check_night_action(&self, player: &Player, action: NightAction) -> Result<(), ServerError> {
        let invalid = || {
            error(
                ErrorCode::InvalidTarget,
                "That isn't a valid target for your role.",
            )
        };
        let no_uses = || error(ErrorCode::NoUsesLeft, "You have no uses of that left.");
        let night = match self.phase {
            GamePhase::Night { night, .. } => night,
            _ => 0,
        };
        let me = player.slot;
        let alive = |slot: PlayerSlot| self.is_alive(slot);
        let other = |slot: PlayerSlot| slot != me && alive(slot);

        if !player.alive {
            let haunting =
                player.role == Role::Jester && player.won && !self.haunt_candidates.is_empty();
            return match action {
                NightAction::Target(t) if haunting && self.haunt_candidates.contains(&t) => Ok(()),
                _ if haunting => Err(error(
                    ErrorCode::InvalidTarget,
                    "Haunt someone who voted guilty.",
                )),
                _ => Err(error(ErrorCode::NotAllowedNow, "The dead can't act.")),
            };
        }
        if self.jail.is_some_and(|jail| jail.prisoner == me) {
            return Err(error(ErrorCode::NotAllowedNow, "You are in jail tonight."));
        }
        if player.role == Role::Vigilante {
            if night <= 1 {
                return Err(error(
                    ErrorCode::NotAllowedNow,
                    "You can't shoot on the first night.",
                ));
            }
            if player.uses == 0 {
                return Err(no_uses());
            }
        }
        match (player.role.target_rule(), action) {
            (TargetRule::None, _) => Err(error(
                ErrorCode::NotAllowedNow,
                "Your role has no night action.",
            )),
            (TargetRule::Other, NightAction::Target(t)) if other(t) => Ok(()),
            (TargetRule::OtherNotMafia, NightAction::Target(t))
                if other(t) && !self.player(t).is_some_and(|p| p.is_mafia()) =>
            {
                Ok(())
            }
            (TargetRule::AnyAlive, NightAction::Target(t)) if alive(t) => {
                if t == me && player.uses == 0 {
                    Err(no_uses())
                } else {
                    Ok(())
                }
            }
            (TargetRule::SelfOnly, NightAction::Activate) => {
                if player.uses == 0 {
                    Err(no_uses())
                } else {
                    Ok(())
                }
            }
            (TargetRule::Dead, NightAction::Target(t))
                if self.player(t).is_some_and(|p| !p.alive) =>
            {
                if player.uses == 0 {
                    Err(no_uses())
                } else {
                    Ok(())
                }
            }
            (TargetRule::TwoAlive, NightAction::TwoTargets(copied, target))
                if other(copied) && alive(target) =>
            {
                Ok(())
            }
            (TargetRule::DouseOrIgnite, NightAction::Target(t)) if other(t) => Ok(()),
            (TargetRule::DouseOrIgnite, NightAction::Activate) => Ok(()),
            (TargetRule::Execute, NightAction::Activate) => {
                if !self.jail.is_some_and(|jail| jail.jailer == me) {
                    Err(error(
                        ErrorCode::NotAllowedNow,
                        "You didn't jail anyone tonight.",
                    ))
                } else if night <= 1 {
                    Err(error(
                        ErrorCode::NotAllowedNow,
                        "You can't execute on the first night.",
                    ))
                } else if player.uses == 0 {
                    Err(no_uses())
                } else {
                    Ok(())
                }
            }
            _ => Err(invalid()),
        }
    }

    // ----- Phases -----

    fn set_phase(&mut self, phase: GamePhase, deadline: u64, out: &mut Vec<Outgoing>) {
        self.phase = phase.clone();
        self.deadline = Some(deadline);
        out.push(Outgoing::all(ServerMessage::Phase {
            phase,
            ends_at_ms: deadline,
        }));
    }

    fn advance(&mut self, at: u64, out: &mut Vec<Outgoing>) {
        let timers = self.timers;
        match self.phase.clone() {
            GamePhase::Day { day: 0, .. } => self.start_night(1, at, out),
            GamePhase::Day {
                day,
                stage: DayStage::Discussion,
            } => {
                self.trials_left = TRIALS_PER_DAY;
                self.votes.clear();
                self.set_phase(
                    GamePhase::Day {
                        day,
                        stage: DayStage::Voting {
                            trials_left: self.trials_left,
                        },
                    },
                    at + timers.voting,
                    out,
                );
                out.push(Outgoing::all(self.votes_message()));
            }
            GamePhase::Day {
                day,
                stage: DayStage::Voting { .. },
            } => self.start_night(day + 1, at, out),
            GamePhase::Day {
                day,
                stage: DayStage::Defense { accused },
            } => {
                self.verdicts.clear();
                self.set_phase(
                    GamePhase::Day {
                        day,
                        stage: DayStage::Judgement { accused },
                    },
                    at + timers.judgement,
                    out,
                );
            }
            GamePhase::Day {
                day,
                stage: DayStage::Judgement { accused },
            } => {
                self.finish_judgement(day, accused, at, out);
            }
            GamePhase::Day {
                day,
                stage: DayStage::LastWords { accused },
            } => {
                self.lynch(accused, out);
                if !self.finish_if_over(out) {
                    self.start_night(day + 1, at, out);
                }
            }
            GamePhase::Night { night, stage } => self.next_night_stage(night, stage, at, out),
            GamePhase::Lobby | GamePhase::GameOver => self.deadline = None,
        }
    }

    fn start_trial(&mut self, accused: PlayerSlot, now: u64, out: &mut Vec<Outgoing>) {
        let GamePhase::Day { day, .. } = self.phase else {
            return;
        };
        self.voting_left = self.deadline.unwrap_or(now).saturating_sub(now);
        self.trials_left = self.trials_left.saturating_sub(1);
        self.set_phase(
            GamePhase::Day {
                day,
                stage: DayStage::Defense { accused },
            },
            now + self.timers.defense,
            out,
        );
    }

    fn finish_judgement(
        &mut self,
        day: u32,
        accused: PlayerSlot,
        at: u64,
        out: &mut Vec<Outgoing>,
    ) {
        // Only living players other than the accused count, in case someone died mid-trial.
        let votes: Vec<(PlayerSlot, Verdict)> = self
            .verdicts
            .iter()
            .filter(|(voter, _)| **voter != accused && self.is_alive(**voter))
            .map(|(voter, verdict)| (*voter, *verdict))
            .collect();
        let count = |wanted| votes.iter().filter(|(_, v)| *v == wanted).count() as u8;
        let (guilty, innocent) = (count(Verdict::Guilty), count(Verdict::Innocent));
        let convicted = guilty > innocent;
        out.push(Outgoing::all(ServerMessage::TrialResult {
            accused,
            votes,
            guilty,
            innocent,
            convicted,
        }));
        if convicted {
            self.set_phase(
                GamePhase::Day {
                    day,
                    stage: DayStage::LastWords { accused },
                },
                at + self.timers.last_words,
                out,
            );
        } else if self.trials_left == 0 {
            self.start_night(day + 1, at, out);
        } else {
            self.votes.clear();
            self.set_phase(
                GamePhase::Day {
                    day,
                    stage: DayStage::Voting {
                        trials_left: self.trials_left,
                    },
                },
                at + self.voting_left,
                out,
            );
            out.push(Outgoing::all(self.votes_message()));
        }
    }

    fn lynch(&mut self, accused: PlayerSlot, out: &mut Vec<Outgoing>) {
        let guilty_voters: Vec<PlayerSlot> = self
            .verdicts
            .iter()
            .filter(|(voter, verdict)| **verdict == Verdict::Guilty && self.is_alive(**voter))
            .map(|(voter, _)| *voter)
            .collect();
        let victim = self.player_mut(accused);
        victim.alive = false;
        let report = DeathReport {
            slot: accused,
            role: victim.role,
            will: victim.will.clone(),
            causes: vec![DeathCause::Lynched],
        };
        if victim.role == Role::Jester {
            victim.won = true;
            self.haunt_candidates = guilty_voters;
        }
        for executioner in self.players.iter_mut().filter(|p| {
            p.alive && p.role == Role::Executioner && p.executioner_target == Some(accused)
        }) {
            executioner.won = true;
        }
        self.lynched_today = true;
        out.push(Outgoing::all(ServerMessage::Deaths(vec![report])));
        self.after_deaths(&[], &[accused], out);
    }

    fn start_night(&mut self, night: u32, at: u64, out: &mut Vec<Outgoing>) {
        self.votes.clear();
        self.night_actions.clear();
        self.jail = self.jail_choice.take().and_then(|prisoner| {
            let jailer = self
                .players
                .iter()
                .find(|p| p.alive && p.role == Role::Jailer)?;
            self.is_alive(prisoner).then_some(Jail {
                jailer: jailer.slot,
                prisoner,
            })
        });
        self.results = night::Results::default();
        self.minigames.clear();
        self.duels.clear();
        self.kill_rounds.clear();
        self.set_phase(
            GamePhase::Night {
                night,
                stage: NightStage::Choosing,
            },
            at + self.timers.choosing,
            out,
        );
        if let Some(jail) = self.jail {
            out.push(Outgoing::one(
                jail.prisoner,
                ServerMessage::Notices(vec![Notice::Jailed]),
            ));
            out.push(Outgoing::one(
                jail.jailer,
                ServerMessage::Notices(vec![Notice::JailedSomeone {
                    prisoner: jail.prisoner,
                }]),
            ));
        }
        if !self.haunt_candidates.is_empty()
            && let Some(jester) = self
                .players
                .iter()
                .find(|p| p.role == Role::Jester && p.won && !p.alive)
        {
            out.push(Outgoing::one(
                jester.slot,
                ServerMessage::Notices(vec![Notice::ChooseHaunt {
                    candidates: self.haunt_candidates.clone(),
                }]),
            ));
        }
    }

    /// Ends one stage of the night and starts the next, or dawn after the last.
    fn next_night_stage(
        &mut self,
        night: u32,
        stage: NightStage,
        at: u64,
        out: &mut Vec<Outgoing>,
    ) {
        if stage == NightStage::Choosing {
            self.lock_actions();
        } else {
            self.close_minigames(out);
        }
        match stage.next() {
            Some(next) => self.begin_night_stage(night, next, at, out),
            None => self.end_night(night, at, out),
        }
    }

    /// Fills in what's missing once actions can no longer change: a lynched Jester who didn't
    /// pick haunts someone anyway.
    fn lock_actions(&mut self) {
        if let Some(jester) = self
            .players
            .iter()
            .find(|p| p.role == Role::Jester && p.won && !p.alive)
            && !self.haunt_candidates.is_empty()
            && !self.night_actions.contains_key(&jester.slot)
        {
            let jester = jester.slot;
            let living: Vec<PlayerSlot> = self
                .haunt_candidates
                .iter()
                .copied()
                .filter(|s| self.is_alive(*s))
                .collect();
            if let Some(victim) = living.choose(&mut self.rng) {
                self.night_actions
                    .insert(jester, NightAction::Target(*victim));
            }
        }
    }

    /// Starts a minigame stage: works out who plays what in it and tells each player.
    fn begin_night_stage(
        &mut self,
        night: u32,
        stage: NightStage,
        at: u64,
        out: &mut Vec<Outgoing>,
    ) {
        self.set_phase(
            GamePhase::Night { night, stage },
            at + self.timers.night_stage(stage),
            out,
        );
        let assigned = match stage {
            NightStage::Choosing => Vec::new(),
            NightStage::Roleblock => self.planned(night, Stage::Roleblock),
            NightStage::Kill { round } => {
                if round == 1 {
                    self.kill_rounds = self.schedule_kill(night);
                }
                self.kill_rounds
                    .get(usize::from(round) - 1)
                    .cloned()
                    .unwrap_or_default()
            }
            NightStage::Protect => self.planned(night, Stage::Protect),
            NightStage::Investigate => self.planned(night, Stage::Investigate),
        };
        self.minigames.clear();
        self.duels.clear();
        for assigned in assigned {
            match assigned {
                Assigned::Check(player) => {
                    self.minigames.insert(player, Play::Check);
                }
                Assigned::Fight { attacker, victim } => {
                    let i = self.duels.len();
                    self.duels.push(Duel::new(attacker, victim));
                    self.minigames.insert(attacker, Play::Fight(i));
                    self.minigames.insert(victim, Play::Fight(i));
                }
            }
        }
        for player in self.players.iter().filter(|p| p.alive) {
            self.minigames.entry(player.slot).or_insert(Play::Passive);
        }
        let ends_at_ms = self.deadline.unwrap_or(at);
        for (&slot, &play) in &self.minigames {
            out.push(Outgoing::one(
                slot,
                ServerMessage::Minigame {
                    game: self.minigame_kind(slot, play),
                    ends_at_ms,
                },
            ));
        }
        for i in 0..self.duels.len() {
            self.send_fight(i, at, out);
        }
    }

    /// The skill checks and fights of a stage other than Kill, given the results so far.
    fn planned(&self, night: u32, stage: Stage) -> Vec<Assigned> {
        let plan = night::plan(
            &self.players,
            &self.night_actions,
            night,
            self.jail,
            &self.results,
        );
        let (checks, fights) = plan.stage(stage);
        fights
            .iter()
            .filter(|f| f.attacker != f.victim)
            .map(|f| Assigned::Fight {
                attacker: f.attacker,
                victim: f.victim,
            })
            .chain(checks.iter().map(|c| Assigned::Check(c.player)))
            .collect()
    }

    /// Spreads the Kill stage's minigames over its rounds so nobody plays two at once: each
    /// fight, then each skill check, goes in the first round where its players are free. Any
    /// that don't fit are decided at random, as if rolled.
    fn schedule_kill(&mut self, night: u32) -> Vec<Vec<Assigned>> {
        let wanted = self.planned(night, Stage::Kill);
        let rounds = usize::from(FIGHT_ROUNDS);
        let mut schedule: Vec<Vec<Assigned>> = vec![Vec::new(); rounds];
        let mut busy: Vec<BTreeSet<PlayerSlot>> = vec![BTreeSet::new(); rounds];
        for assigned in wanted {
            let players = assigned.players();
            let free = (0..rounds).find(|r| players.iter().all(|p| !busy[*r].contains(p)));
            match (free, assigned) {
                (Some(r), _) => {
                    busy[r].extend(players);
                    schedule[r].push(assigned);
                }
                (None, Assigned::Check(player)) => {
                    let passed = self.rng.random_bool(ROLL_PASS_CHANCE);
                    self.results.check(player, passed);
                }
                (None, Assigned::Fight { attacker, victim }) => {
                    let won = self.rng.random_bool(FIGHT_ROLL_CHANCE);
                    self.results.fight(attacker, victim, won);
                }
            }
        }
        schedule
    }

    /// Ends the stage's minigames: unreported skill checks fail, and fights still going are
    /// won by the victim.
    fn close_minigames(&mut self, out: &mut Vec<Outgoing>) {
        let checks: Vec<PlayerSlot> = self
            .minigames
            .iter()
            .filter(|(slot, play)| **play == Play::Check && self.results.checked(**slot).is_none())
            .map(|(slot, _)| *slot)
            .collect();
        for slot in checks {
            self.results.check(slot, false);
            out.push(Outgoing::one(
                slot,
                ServerMessage::MinigameOver {
                    result: MinigameResult::Failed,
                    rolled: false,
                },
            ));
        }
        for i in 0..self.duels.len() {
            if !self.duels[i].is_over() {
                self.duels[i].finish(false);
                self.duel_over(i, false, out);
            }
        }
        self.minigames.clear();
        self.duels.clear();
    }

    /// What a player's minigame is, as they are told it.
    fn minigame_kind(&self, slot: PlayerSlot, play: Play) -> Minigame {
        match play {
            Play::Check => Minigame::SkillCheck,
            Play::Passive => Minigame::Passive,
            Play::Fight(i) => Minigame::Fight {
                attacking: self.duels[i].attacker == slot,
            },
        }
    }

    fn minigame_over(&self, slot: PlayerSlot, play: Play) -> bool {
        match play {
            Play::Check => self.results.checked(slot).is_some(),
            Play::Fight(i) => self.duels[i].is_over(),
            Play::Passive => false,
        }
    }

    /// A move in a player's minigame.
    fn minigame(
        &mut self,
        from: PlayerSlot,
        play: MinigamePlay,
        now: u64,
        out: &mut Vec<Outgoing>,
    ) -> Result<(), ServerError> {
        let Some(current) = self.minigames.get(&from).copied() else {
            return Err(error(
                ErrorCode::NotAllowedNow,
                "You have no minigame right now.",
            ));
        };
        if play == MinigamePlay::Roll && !self.rolls {
            return Err(error(
                ErrorCode::NotAllowedNow,
                "This server doesn't roll minigames for you.",
            ));
        }
        match (current, play) {
            // Nothing rides on a passive game, so there is nothing to report.
            (Play::Passive, MinigamePlay::Roll | MinigamePlay::Check { .. }) => {}
            (Play::Check, MinigamePlay::Roll | MinigamePlay::Check { .. }) => {
                if self.results.checked(from).is_some() {
                    return Err(error(
                        ErrorCode::NotAllowedNow,
                        "You already played your skill check.",
                    ));
                }
                let (passed, rolled) = match play {
                    MinigamePlay::Check { passed } => (passed, false),
                    _ => (self.rng.random_bool(ROLL_PASS_CHANCE), true),
                };
                self.results.check(from, passed);
                out.push(Outgoing::one(
                    from,
                    ServerMessage::MinigameOver {
                        result: if passed {
                            MinigameResult::Passed
                        } else {
                            MinigameResult::Failed
                        },
                        rolled,
                    },
                ));
            }
            // Both fighters may roll; the first decides it.
            (Play::Fight(i), MinigamePlay::Roll) if !self.duels[i].is_over() => {
                let won = self.rng.random_bool(FIGHT_ROLL_CHANCE);
                self.duels[i].finish(won);
                self.duel_over(i, true, out);
            }
            (Play::Fight(_), MinigamePlay::Roll) => {}
            (Play::Fight(i), MinigamePlay::Move(_) | MinigamePlay::Guard(_)) => {
                if self.duels[i].play(from, play, now) {
                    self.send_fight(i, now, out);
                }
            }
            (Play::Fight(_), MinigamePlay::Check { .. }) => {
                return Err(error(
                    ErrorCode::BadMessage,
                    "You're in a fight, not a skill check.",
                ));
            }
            (Play::Check | Play::Passive, MinigamePlay::Move(_) | MinigamePlay::Guard(_)) => {
                return Err(error(ErrorCode::BadMessage, "You aren't in a fight."));
            }
        }
        Ok(())
    }

    fn next_landing(&self) -> Option<u64> {
        self.duels.iter().filter_map(Duel::next_landing).min()
    }

    /// Lands the fight moves due at `at`.
    fn land(&mut self, at: u64, out: &mut Vec<Outgoing>) {
        for i in 0..self.duels.len() {
            if self.duels[i].next_landing().is_some_and(|due| due <= at) {
                self.duels[i].land(at);
                self.send_fight(i, at, out);
                if self.duels[i].is_over() {
                    self.duel_over(i, false, out);
                }
            }
        }
    }

    fn send_fight(&self, i: usize, now: u64, out: &mut Vec<Outgoing>) {
        let duel = &self.duels[i];
        for slot in [duel.attacker, duel.victim] {
            if let Some(view) = duel.view(slot, now) {
                out.push(Outgoing::one(slot, ServerMessage::Fight(view)));
            }
        }
    }

    /// Records a fight that just ended and tells both fighters.
    fn duel_over(&mut self, i: usize, rolled: bool, out: &mut Vec<Outgoing>) {
        let duel = &self.duels[i];
        let won = duel.attacker_won.unwrap_or(false);
        self.results.fight(duel.attacker, duel.victim, won);
        let result = |win: bool| {
            if win {
                MinigameResult::Won
            } else {
                MinigameResult::Lost
            }
        };
        for (slot, win) in [(duel.attacker, won), (duel.victim, !won)] {
            out.push(Outgoing::one(
                slot,
                ServerMessage::MinigameOver {
                    result: result(win),
                    rolled,
                },
            ));
        }
    }

    fn end_night(&mut self, night: u32, at: u64, out: &mut Vec<Outgoing>) {
        let actions = std::mem::take(&mut self.night_actions);
        let outcome = night::resolve(
            &mut self.players,
            &actions,
            night,
            self.jail,
            &self.results,
            &mut self.rng,
        );
        self.haunt_candidates.clear();
        self.jail = None;

        let mut reports = Vec::new();
        for (slot, causes) in &outcome.deaths {
            let player = self.player_mut(*slot);
            if !player.alive {
                continue;
            }
            player.alive = false;
            reports.push(DeathReport {
                slot: *slot,
                role: player.role,
                will: player.will.clone(),
                causes: causes.clone(),
            });
        }
        let died: Vec<PlayerSlot> = reports.iter().map(|r| r.slot).collect();
        let quiet = died.is_empty() && !self.lynched_today;
        self.quiet_cycles = if quiet { self.quiet_cycles + 1 } else { 0 };
        self.lynched_today = false;

        out.push(Outgoing::all(ServerMessage::Deaths(reports)));
        for (slot, notices) in outcome.notices {
            out.push(Outgoing::one(slot, ServerMessage::Notices(notices)));
        }
        for (slot, role) in &outcome.remembered {
            out.push(Outgoing::all(ServerMessage::Remembered { role: *role }));
            out.push(Outgoing::one(
                *slot,
                ServerMessage::RoleChanged { role: *role },
            ));
        }
        self.after_deaths(&outcome.remembered, &died, out);
        if !self.finish_if_over(out) {
            self.set_phase(
                GamePhase::Day {
                    day: night,
                    stage: DayStage::Discussion,
                },
                at + self.timers.discussion,
                out,
            );
        }
    }

    /// Follow-ups to deaths: Executioners whose target died some other way become Jesters, and
    /// the Mafia promotes a new Godfather or Mafioso. `changed` lists role changes that already
    /// happened (Amnesiacs), so the Mafia hears about new members.
    fn after_deaths(
        &mut self,
        changed: &[(PlayerSlot, Role)],
        died: &[PlayerSlot],
        out: &mut Vec<Outgoing>,
    ) {
        let mut team_changed = changed
            .iter()
            .any(|(_, role)| role.faction() == webgame_protocol::Faction::Mafia);
        for executioner in self.players.iter_mut().filter(|p| {
            p.alive
                && p.role == Role::Executioner
                && !p.won
                && p.executioner_target.is_some_and(|t| died.contains(&t))
        }) {
            // A lynched target is a win (set by lynch()), so reaching here means another death.
            executioner.become_role(Role::Jester);
            out.push(Outgoing::one(
                executioner.slot,
                ServerMessage::RoleChanged { role: Role::Jester },
            ));
        }
        let alive_as =
            |players: &[Player], role: Role| players.iter().any(|p| p.alive && p.role == role);
        let godfather_died = died.iter().any(|slot| {
            self.player(*slot)
                .is_some_and(|p| p.role == Role::Godfather)
        });
        if godfather_died && !alive_as(&self.players, Role::Godfather) {
            team_changed |= self.promote(|p| p.role == Role::Mafioso, Role::Godfather, out);
        }
        if !alive_as(&self.players, Role::Mafioso) {
            team_changed |= self.promote(
                |p| p.is_mafia() && p.role != Role::Godfather,
                Role::Mafioso,
                out,
            );
        }
        if team_changed
            || died
                .iter()
                .any(|slot| self.player(*slot).is_some_and(|p| p.is_mafia()))
        {
            out.push(Outgoing {
                to: Audience::Many(self.mafia()),
                message: ServerMessage::Team(self.team()),
            });
        }
    }

    /// Gives the first living player who matches `pick` a new role. Returns whether anyone was.
    fn promote(
        &mut self,
        pick: impl Fn(&Player) -> bool,
        to: Role,
        out: &mut Vec<Outgoing>,
    ) -> bool {
        let Some(player) = self.players.iter_mut().find(|p| p.alive && pick(p)) else {
            return false;
        };
        player.become_role(to);
        out.push(Outgoing::one(
            player.slot,
            ServerMessage::RoleChanged { role: to },
        ));
        true
    }

    fn finish_if_over(&mut self, out: &mut Vec<Outgoing>) -> bool {
        let Some(result) = win::check(&self.players, self.quiet_cycles) else {
            return false;
        };
        self.phase = GamePhase::GameOver;
        self.deadline = None;
        out.push(Outgoing::all(ServerMessage::Phase {
            phase: GamePhase::GameOver,
            ends_at_ms: 0,
        }));
        out.push(Outgoing::all(ServerMessage::GameOver(result.clone())));
        self.result = Some(result);
        true
    }

    // ----- Helpers -----

    fn player_mut(&mut self, slot: PlayerSlot) -> &mut Player {
        self.players
            .iter_mut()
            .find(|p| p.slot == slot)
            .expect("slot is in the game")
    }

    fn is_alive(&self, slot: PlayerSlot) -> bool {
        self.player(slot).is_some_and(|p| p.alive)
    }

    fn votes_needed(&self) -> usize {
        self.players.iter().filter(|p| p.alive).count() / 2 + 1
    }

    fn votes_message(&self) -> ServerMessage {
        ServerMessage::Votes {
            votes: self
                .votes
                .iter()
                .map(|(voter, target)| VoteEntry {
                    voter: *voter,
                    target: *target,
                })
                .collect(),
            needed: self.votes_needed() as u8,
        }
    }

    /// Every Mafia member, alive or dead (the dead still see the team list update).
    fn mafia(&self) -> Vec<PlayerSlot> {
        self.players
            .iter()
            .filter(|p| p.is_mafia())
            .map(|p| p.slot)
            .collect()
    }

    fn team(&self) -> Vec<TeamMember> {
        self.players
            .iter()
            .filter(|p| p.is_mafia())
            .map(|p| TeamMember {
                slot: p.slot,
                role: p.role,
                alive: p.alive,
            })
            .collect()
    }

    fn start_for(&self, slot: PlayerSlot) -> GameStart {
        let me = self.player(slot).expect("slot is in the game");
        GameStart {
            you: slot,
            role: me.role,
            players: self
                .players
                .iter()
                .map(|p| PlayerSummary {
                    slot: p.slot,
                    name: p.name.clone(),
                    alive: p.alive,
                })
                .collect(),
            role_list: self.role_list.clone(),
            team: if me.is_mafia() {
                self.team()
            } else {
                Vec::new()
            },
            executioner_target: me
                .executioner_target
                .filter(|_| me.role == Role::Executioner),
            last_will: me.will.clone(),
        }
    }
}
