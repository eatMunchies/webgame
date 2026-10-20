//! One lobby: its members, and the game they are playing.
//!
//! Each lobby runs as its own tokio task that owns all of its state, so nothing in it is shared
//! or locked. Sessions talk to it by sending [`LobbyCmd`]s; it talks back through each member's
//! outbox. The task sleeps until either a command arrives or the game next has something to
//! do: its current phase ends, or a move in a fight lands.

use std::sync::Arc;
use std::time::Duration;

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

pub enum LobbyCmd {
    Join {
        user: UserId,
        name: String,
        connection: Connection,
        reply: oneshot::Sender<Result<(), ServerError>>,
    },
    /// The player left on purpose, or their connection dropped.
    Leave { user: UserId, connection: u64 },
    Message {
        user: UserId,
        message: ClientMessage,
    },
}

struct Member {
    user: UserId,
    name: String,
    slot: PlayerSlot,
    /// None while a player in a running game is disconnected; their seat waits for them.
    connection: Option<Connection>,
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
            tokio::select! {
                command = inbox.recv() => match command {
                    Some(command) => self.handle(command),
                    None => break,
                },
                () = phase_over => {
                    if let Some(running) = &mut self.running {
                        let out = running.game.tick(now_ms());
                        self.dispatch(out);
                    }
                }
            }
            if self.members.iter().all(|m| m.connection.is_none()) {
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
            LobbyCmd::Leave { user, connection } => self.leave(user, connection),
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
            // The same user again, probably reconnecting: give them their seat back.
            if let Some(old) = member.connection.replace(connection) {
                let _ = old.outbox.send(ServerMessage::Error(ServerError::new(
                    ErrorCode::ConnectedElsewhere,
                    "You connected from somewhere else.",
                )));
            }
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
        if self.in_game() {
            return Err(ServerError::new(
                ErrorCode::GameInProgress,
                "That lobby is in the middle of a game.",
            ));
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
            name,
            slot,
            connection: Some(connection),
            appearance: None,
            movement: None,
        });
        self.members.sort_by_key(|m| m.slot);
        self.broadcast_lobby();
        self.send_positions(slot);
        Ok(())
    }

    fn leave(&mut self, user: UserId, connection: u64) {
        let Some(index) = self.members.iter().position(|m| {
            m.user == user && m.connection.as_ref().is_some_and(|c| c.id == connection)
        }) else {
            // Already replaced by a newer connection.
            return;
        };
        if self.in_game() {
            // Keep the seat so they can reconnect; the game carries on without them.
            self.members[index].connection = None;
        } else {
            self.members.remove(index);
            if self.host == user
                && let Some(next) = self.members.first()
            {
                self.host = next.user;
            }
        }
        self.broadcast_lobby();
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
