//! One lobby: its members, and the game they are playing.
//!
//! Each lobby runs as its own tokio task that owns all of its state, so nothing in it is shared
//! or locked. Sessions talk to it by sending [`LobbyCmd`]s; it talks back through each member's
//! outbox. The task sleeps until either a command arrives or the game next has something to
//! do: its current phase ends, or a move in a fight lands.

use std::sync::Arc;
use std::time::Duration;

use tokio::time::Instant;

use tokio::sync::{mpsc, oneshot};
use webgame_game::{Game, Input, Outgoing, Seat};
use webgame_protocol::{
    Appearance, ChatChannel, ChatMessage, ChatSender, ClientMessage, ErrorCode, LobbyCode,
    LobbyInfo, LobbyMember, MAX_CHAT_LEN, MAX_PLAYERS, MIN_PLAYERS, Movement, PlayerSlot,
    ServerError, ServerMessage, UserId,
};

use crate::db::Db;
use crate::{Config, now_ms};

/// Where a session receives the messages meant for it.
pub type Outbox = mpsc::UnboundedSender<ServerMessage>;

/// A live connection: its id (to tell a stale connection from a newer one for the same user)
/// and its outbox.
#[derive(Clone)]
pub struct Connection {
    pub id: u64,
    pub outbox: Outbox,
}

/// How long a seat waits for a player whose connection dropped, as when a phone puts the
/// browser in the background. Before a game they keep their place in the lobby for this long;
/// during one their seat waits for the whole game. A lobby closes once everyone has been gone
/// this long.
pub const RECONNECT_GRACE: Duration = Duration::from_secs(90);

pub enum LobbyCmd {
    Join {
        user: UserId,
        name: String,
        connection: Connection,
        reply: oneshot::Sender<Result<(), ServerError>>,
    },
    /// The player left on purpose, or their connection `dropped`.
    Leave {
        user: UserId,
        connection: u64,
        dropped: bool,
    },
    Message {
        user: UserId,
        message: ClientMessage,
    },
}

struct Member {
    user: UserId,
    name: String,
    slot: PlayerSlot,
    /// None while the player is disconnected; their seat waits for them (see
    /// [`RECONNECT_GRACE`]).
    connection: Option<Connection>,
    /// When their connection dropped, while it's down.
    dropped_at: Option<Instant>,
    appearance: Option<Appearance>,
    /// Where their character last was in the town, for players who join later. Movement is
    /// only relayed, never written to the database.
    movement: Option<Movement>,
}

/// A game and the bookkeeping for its database record.
struct Running {
    game: Game,
    id: i64,
    seq: i64,
}

pub struct Lobby {
    code: LobbyCode,
    host: UserId,
    members: Vec<Member>,
    running: Option<Running>,
    db: Db,
    config: Arc<Config>,
}

impl Lobby {
    /// A new lobby with its host as the only member.
    pub fn new(
        code: LobbyCode,
        host: UserId,
        name: String,
        connection: Connection,
        db: Db,
        config: Arc<Config>,
    ) -> Self {
        db.lobby_opened(&code, host);
        let lobby = Lobby {
            code,
            host,
            members: vec![Member {
                user: host,
                name,
                slot: PlayerSlot(0),
                connection: Some(connection),
                dropped_at: None,
                appearance: None,
                movement: None,
            }],
            running: None,
            db,
            config,
        };
        lobby.broadcast_lobby();
        lobby
    }

    /// Runs the lobby until everyone has left or disconnected.
    pub async fn run(mut self, mut inbox: mpsc::Receiver<LobbyCmd>) {
        loop {
            let deadline = self.running.as_ref().and_then(|r| r.game.wake_at());
            let phase_over = async {
                match deadline {
                    Some(deadline) => {
                        tokio::time::sleep(Duration::from_millis(deadline.saturating_sub(now_ms())))
                            .await
                    }
                    None => std::future::pending().await,
                }
            };
            let grace_end = self.next_grace_end();
            let grace_over = async {
                match grace_end {
                    Some(end) => tokio::time::sleep_until(end).await,
                    None => std::future::pending().await,
                }
            };
            tokio::select! {
                command = inbox.recv() => match command {
                    Some(command) => self.handle(command),
                    None => break,
                },
                () = grace_over => self.drop_gone(),
                () = phase_over => {
                    if let Some(running) = &mut self.running {
                        let out = running.game.tick(now_ms());
                        self.dispatch(out);
                    }
                }
            }
            // Also catches players whose grace ran out during a game that has since ended.
            self.drop_gone();
            if self.abandoned() {
                break;
            }
        }
        self.db.lobby_closed(&self.code);
    }

    fn handle(&mut self, command: LobbyCmd) {
        match command {
            LobbyCmd::Join {
                user,
                name,
                connection,
                reply,
            } => {
                let result = self.join(user, name, connection);
                let _ = reply.send(result);
            }
            LobbyCmd::Leave {
                user,
                connection,
                dropped,
            } => self.leave(user, connection, dropped),
            LobbyCmd::Message { user, message } => {
                if let Err(err) = self.message(user, message) {
                    self.send_to_user(user, ServerMessage::Error(err));
                }
            }
        }
    }

    fn in_game(&self) -> bool {
        self.running.as_ref().is_some_and(|r| !r.game.is_over())
    }

    fn join(
        &mut self,
        user: UserId,
        name: String,
        connection: Connection,
    ) -> Result<(), ServerError> {
        if let Some(member) = self.members.iter_mut().find(|m| m.user == user) {
            // Names are the only identity, so a second connection under a name that is still
            // connected is someone else (or another window) and would share the seat.
            if member.connection.is_some() {
                return Err(ServerError::new(
                    ErrorCode::NameTaken,
                    format!("Someone named {} is already in that lobby.", member.name),
                ));
            }
            // A player whose connection dropped, coming back: give them their seat back.
            member.connection = Some(connection);
            member.dropped_at = None;
            let slot = member.slot;
            self.broadcast_lobby();
            self.send_positions(slot);
            if let Some(running) = &self.running {
                for message in running.game.snapshot(slot) {
                    self.send_to_slot(slot, message);
                }
            }
            return Ok(());
        }
        if self.members.len() >= MAX_PLAYERS {
            return Err(ServerError::new(
                ErrorCode::LobbyFull,
                "That lobby is full.",
            ));
        }
        // The lowest free lot, so lots fill in join order and a freed lot goes to the next person.
        let slot = (0..MAX_PLAYERS as u8)
            .map(PlayerSlot)
            .find(|slot| self.members.iter().all(|m| m.slot != *slot))
            .expect("checked the lobby isn't full");
        self.members.push(Member {
            user,
            name: name.clone(),
            slot,
            connection: Some(connection),
            dropped_at: None,
            appearance: None,
            movement: None,
        });
        self.members.sort_by_key(|m| m.slot);
        // Joining a game in progress seats them as a spectator: dead, watching with the dead.
        let spectating = self.in_game();
        if spectating && let Some(running) = &mut self.running {
            running.game.add_spectator(slot, user, name);
        }
        self.broadcast_lobby();
        self.send_positions(slot);
        if spectating && let Some(running) = &self.running {
            for message in running.game.snapshot(slot) {
                self.send_to_slot(slot, message);
            }
        }
        Ok(())
    }

    fn leave(&mut self, user: UserId, connection: u64, dropped: bool) {
        let Some(index) = self.members.iter().position(|m| {
            m.user == user && m.connection.as_ref().is_some_and(|c| c.id == connection)
        }) else {
            // Already replaced by a newer connection.
            return;
        };
        if self.in_game() || dropped {
            // Keep the seat so they can reconnect: for the rest of the game, or before one for
            // RECONNECT_GRACE (see drop_gone). The game carries on without them.
            self.members[index].connection = None;
            self.members[index].dropped_at = Some(Instant::now());
        } else {
            self.remove(index);
        }
        self.broadcast_lobby();
    }

    fn remove(&mut self, index: usize) {
        let user = self.members.remove(index).user;
        if self.host == user
            && let Some(next) = self.members.first()
        {
            self.host = next.user;
        }
    }

    /// When the next dropped player's grace runs out, if one is still running.
    fn next_grace_end(&self) -> Option<Instant> {
        let now = Instant::now();
        self.members
            .iter()
            .filter_map(|m| m.dropped_at)
            .map(|at| at + RECONNECT_GRACE)
            .filter(|end| *end > now)
            .min()
    }

    /// Outside a game, gives up on players whose connection has been down for
    /// RECONNECT_GRACE. In a game their seat keeps waiting.
    fn drop_gone(&mut self) {
        if self.in_game() {
            return;
        }
        let now = Instant::now();
        let before = self.members.len();
        while let Some(index) = self
            .members
            .iter()
            .position(|m| m.dropped_at.is_some_and(|at| now >= at + RECONNECT_GRACE))
        {
            self.remove(index);
        }
        if self.members.len() != before {
            self.broadcast_lobby();
        }
    }

    /// Whether the lobby should close: everyone is gone, and has been for RECONNECT_GRACE.
    fn abandoned(&self) -> bool {
        let now = Instant::now();
        self.members.iter().all(|m| {
            m.connection.is_none() && m.dropped_at.is_none_or(|at| now >= at + RECONNECT_GRACE)
        })
    }

    fn message(&mut self, user: UserId, message: ClientMessage) -> Result<(), ServerError> {
        let slot = self
            .members
            .iter()
            .find(|m| m.user == user)
            .map(|m| m.slot)
            .ok_or_else(|| ServerError::new(ErrorCode::NotInLobby, "You aren't in this lobby."))?;
        match message {
            ClientMessage::StartGame => self.start_game(user),
            ClientMessage::Chat {
                channel: ChatChannel::Lobby,
                text,
            } => {
                if self.in_game() {
                    return Err(ServerError::new(
                        ErrorCode::NotAllowedNow,
                        "The lobby chat is closed during a game.",
                    ));
                }
                let text = text.trim().to_string();
                if text.is_empty() || text.chars().count() > MAX_CHAT_LEN {
                    return Err(ServerError::new(
                        ErrorCode::TooLong,
                        "Messages are 1 to 300 characters.",
                    ));
                }
                let chat = ServerMessage::Chat(ChatMessage {
                    channel: ChatChannel::Lobby,
                    from: ChatSender::Player(slot),
                    text,
                });
                for member in &self.members {
                    send(member, chat.clone());
                }
                Ok(())
            }
            ClientMessage::Chat { channel, text } => {
                self.game_input(slot, Input::Chat { channel, text })
            }
            ClientMessage::Game(action) => self.game_input(slot, Input::Action(action)),
            ClientMessage::Move(movement) => self.moved(slot, movement),
            ClientMessage::SetAppearance(appearance) => self.set_appearance(slot, appearance),
            ClientMessage::Hello { .. }
            | ClientMessage::CreateLobby
            | ClientMessage::JoinLobby { .. }
            | ClientMessage::LeaveLobby => Err(ServerError::new(
                ErrorCode::BadMessage,
                "That message is handled by the session.",
            )),
        }
    }

    /// Remembers where a player's character is and tells everyone else.
    fn moved(&mut self, slot: PlayerSlot, movement: Movement) -> Result<(), ServerError> {
        if !movement.is_valid() {
            return Err(ServerError::new(
                ErrorCode::BadMessage,
                "That position is outside the town.",
            ));
        }
        let member = self.member_mut(slot);
        if member.movement == Some(movement) {
            return Ok(());
        }
        member.movement = Some(movement);
        let moved = ServerMessage::Moved { slot, movement };
        for other in self.members.iter().filter(|m| m.slot != slot) {
            send(other, moved.clone());
        }
        Ok(())
    }

    fn set_appearance(
        &mut self,
        slot: PlayerSlot,
        appearance: Appearance,
    ) -> Result<(), ServerError> {
        appearance
            .validate()
            .map_err(|message| ServerError::new(ErrorCode::TooLong, message))?;
        let member = self.member_mut(slot);
        if member.appearance.as_ref() != Some(&appearance) {
            member.appearance = Some(appearance);
            self.broadcast_lobby();
        }
        Ok(())
    }

    /// Tells a player who just joined or reconnected where everyone else's character is.
    fn send_positions(&self, slot: PlayerSlot) {
        for other in self.members.iter().filter(|m| m.slot != slot) {
            if let Some(movement) = other.movement {
                self.send_to_slot(
                    slot,
                    ServerMessage::Moved {
                        slot: other.slot,
                        movement,
                    },
                );
            }
        }
    }

    fn member_mut(&mut self, slot: PlayerSlot) -> &mut Member {
        self.members
            .iter_mut()
            .find(|m| m.slot == slot)
            .expect("the slot was looked up from a member")
    }

    fn start_game(&mut self, user: UserId) -> Result<(), ServerError> {
        if user != self.host {
            return Err(ServerError::new(
                ErrorCode::NotHost,
                "Only the host can start the game.",
            ));
        }
        if self.in_game() {
            return Err(ServerError::new(
                ErrorCode::GameInProgress,
                "A game is already running.",
            ));
        }
        if self.members.len() < MIN_PLAYERS {
            return Err(ServerError::new(
                ErrorCode::NotEnoughPlayers,
                format!("A game needs at least {MIN_PLAYERS} players."),
            ));
        }
        let seats: Vec<Seat> = self
            .members
            .iter()
            .map(|m| Seat {
                slot: m.slot,
                user_id: m.user,
                name: m.name.clone(),
            })
            .collect();
        let seed = self.config.seed.unwrap_or_else(rand::random);
        let (mut game, out) = Game::new(seats, seed, self.config.timers, now_ms())?;
        game.allow_rolls(self.config.rolls);
        // Positive, so it reads the same as a signed SQLite integer.
        let id = (rand::random::<u64>() >> 1) as i64;
        let players: Vec<_> = self
            .members
            .iter()
            .map(|m| (m.slot.0, m.user, m.name.clone()))
            .collect();
        self.db.game_started(id, &self.code, seed, &players);
        self.running = Some(Running { game, id, seq: 0 });
        self.broadcast_lobby();
        self.dispatch(out);
        Ok(())
    }

    fn game_input(&mut self, slot: PlayerSlot, input: Input) -> Result<(), ServerError> {
        let running = self
            .running
            .as_mut()
            .ok_or_else(|| ServerError::new(ErrorCode::NotAllowedNow, "No game is running."))?;
        let out = running.game.handle(slot, input, now_ms())?;
        self.dispatch(out);
        Ok(())
    }

    /// Delivers a game's messages to the connected members allowed to see them, and logs them.
    fn dispatch(&mut self, out: Vec<Outgoing>) {
        let Some(running) = &mut self.running else {
            return;
        };
        let mut ended = false;
        for outgoing in out {
            running.seq += 1;
            self.db
                .game_event(running.id, running.seq, &outgoing.to, &outgoing.message);
            if let ServerMessage::GameOver(result) = &outgoing.message {
                self.db.game_ended(running.id, result);
                ended = true;
            }
            for member in self.members.iter().filter(|m| outgoing.to.includes(m.slot)) {
                send(member, outgoing.message.clone());
            }
        }
        if ended {
            // Players who left mid-game don't come back to the lobby.
            self.members.retain(|m| m.connection.is_some());
            if !self.members.iter().any(|m| m.user == self.host)
                && let Some(next) = self.members.first()
            {
                self.host = next.user;
            }
            self.broadcast_lobby();
        }
    }

    fn info(&self) -> LobbyInfo {
        LobbyInfo {
            code: self.code.clone(),
            host: self.host,
            members: self
                .members
                .iter()
                .map(|m| LobbyMember {
                    user_id: m.user,
                    name: m.name.clone(),
                    slot: m.slot,
                    connected: m.connection.is_some(),
                    appearance: m.appearance.clone(),
                })
                .collect(),
            in_game: self.in_game(),
        }
    }

    fn broadcast_lobby(&self) {
        let info = ServerMessage::Lobby(self.info());
        for member in &self.members {
            send(member, info.clone());
        }
    }

    fn send_to_slot(&self, slot: PlayerSlot, message: ServerMessage) {
        if let Some(member) = self.members.iter().find(|m| m.slot == slot) {
            send(member, message);
        }
    }

    fn send_to_user(&self, user: UserId, message: ServerMessage) {
        if let Some(member) = self.members.iter().find(|m| m.user == user) {
            send(member, message);
        }
    }
}

fn send(member: &Member, message: ServerMessage) {
    if let Some(connection) = &member.connection {
        // A closed outbox means the session is going away; its Leave is on the way.
        let _ = connection.outbox.send(message);
    }
}
