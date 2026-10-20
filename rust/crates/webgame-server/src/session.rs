//! One WebSocket connection: who it is, and which lobby it is in.
//!
//! A session decodes each binary frame into a [`ClientMessage`]. It handles identifying and
//! moving between lobbies itself, and forwards everything else to its lobby's task. Messages
//! for the client arrive on the session's outbox and are encoded back into binary frames.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::{mpsc, oneshot};
use webgame_protocol::{
    ClientMessage, ErrorCode, LobbyCode, PROTOCOL_VERSION, ServerError, ServerMessage, UserId,
    decode, encode, validate_username,
};

use crate::lobby::{Connection, LobbyCmd, Outbox};
use crate::registry::{LobbyHandle, Registry};

static NEXT_CONNECTION: AtomicU64 = AtomicU64::new(1);

struct Session {
    registry: Arc<Registry>,
    connection: Connection,
    user: Option<(UserId, String)>,
    lobby: Option<(LobbyCode, LobbyHandle)>,
}

/// Runs a connection until the client closes it or it drops.
pub async fn run(socket: WebSocket, registry: Arc<Registry>) {
    let (mut sink, mut stream) = socket.split();
    let (outbox, mut outgoing) = mpsc::unbounded_channel::<ServerMessage>();
    let writer = tokio::spawn(async move {
        while let Some(message) = outgoing.recv().await {
            if sink
                .send(Message::Binary(encode(&message).into()))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    let mut session = Session {
        registry,
        connection: Connection {
            id: NEXT_CONNECTION.fetch_add(1, Ordering::Relaxed),
            outbox,
        },
        user: None,
        lobby: None,
    };
    while let Some(Ok(frame)) = stream.next().await {
        match frame {
            Message::Binary(bytes) => match decode::<ClientMessage>(&bytes) {
                Ok(message) => session.handle(message).await,
                Err(err) => session.error(ErrorCode::BadMessage, err.to_string()),
            },
            Message::Close(_) => break,
            // Text frames aren't part of the protocol; pings are answered by axum.
            _ => {}
        }
    }
    session.leave_lobby().await;
    writer.abort();
}

impl Session {
    fn send(&self, message: ServerMessage) {
        let _ = self.connection.outbox.send(message);
    }

    fn error(&self, code: ErrorCode, message: impl Into<String>) {
        self.send(ServerMessage::Error(ServerError::new(code, message)));
    }

    fn outbox(&self) -> &Outbox {
        &self.connection.outbox
    }

    async fn handle(&mut self, message: ClientMessage) {
        if let ClientMessage::Hello { version, username } = message {
            return self.hello(version, &username);
        }
        let Some((user, name)) = self.user.clone() else {
            return self.error(ErrorCode::NotIdentified, "Say hello first.");
        };
        match message {
            ClientMessage::Hello { .. } => unreachable!("handled above"),
            ClientMessage::CreateLobby => {
                if self.lobby.is_some() {
                    return self.error(ErrorCode::AlreadyInLobby, "Leave your lobby first.");
                }
                let connection = Connection {
                    id: self.connection.id,
                    outbox: self.outbox().clone(),
                };
                self.lobby = Some(self.registry.create(user, name, connection));
            }
            ClientMessage::JoinLobby { code } => {
                if self.lobby.is_some() {
                    return self.error(ErrorCode::AlreadyInLobby, "Leave your lobby first.");
                }
                let not_found = || {
                    ServerError::new(ErrorCode::LobbyNotFound, "There's no lobby with that code.")
                };
                let result = match self.registry.find(&code) {
                    None => Err(not_found()),
                    Some(handle) => {
                        let (reply, answer) = oneshot::channel();
                        let join = LobbyCmd::Join {
                            user,
                            name,
                            connection: Connection {
                                id: self.connection.id,
                                outbox: self.outbox().clone(),
                            },
                            reply,
                        };
                        // A lobby that closes between the lookup and the join drops the reply.
                        match handle.send(join).await {
                            Ok(()) => answer
                                .await
                                .unwrap_or_else(|_| Err(not_found()))
                                .map(|()| handle),
                            Err(_) => Err(not_found()),
                        }
                    }
                };
                match result {
                    Ok(handle) => self.lobby = Some((code, handle)),
                    Err(err) => self.send(ServerMessage::Error(err)),
                }
            }
            ClientMessage::LeaveLobby => {
                if self.lobby.is_none() {
                    return self.error(ErrorCode::NotInLobby, "You aren't in a lobby.");
                }
                self.leave_lobby().await;
                self.send(ServerMessage::LeftLobby);
            }
            other => {
                let Some((_, handle)) = &self.lobby else {
                    return self.error(ErrorCode::NotInLobby, "Join a lobby first.");
                };
                if handle
                    .send(LobbyCmd::Message {
                        user,
                        message: other,
                    })
                    .await
                    .is_err()
                {
                    self.lobby = None;
                    self.error(ErrorCode::LobbyNotFound, "Your lobby closed.");
                }
            }
        }
    }

    fn hello(&mut self, version: u32, username: &str) {
        if self.user.is_some() {
            return self.error(ErrorCode::AlreadyIdentified, "You already said hello.");
        }
        if version != PROTOCOL_VERSION {
            return self.error(
                ErrorCode::VersionMismatch,
                format!("The server speaks protocol {PROTOCOL_VERSION}, you sent {version}. Update the game."),
            );
        }
        let username = match validate_username(username) {
            Ok(name) => name,
            Err(err) => return self.error(ErrorCode::InvalidName, err.to_string()),
        };
        let user_id = UserId::from_username(&username);
        self.registry.db().user_seen(user_id, &username);
        self.user = Some((user_id, username.clone()));
        self.send(ServerMessage::Welcome { user_id, username });
    }

    async fn leave_lobby(&mut self) {
        if let (Some((_, handle)), Some((user, _))) = (self.lobby.take(), &self.user) {
            let _ = handle
                .send(LobbyCmd::Leave {
                    user: *user,
                    connection: self.connection.id,
                })
                .await;
        }
    }
}
