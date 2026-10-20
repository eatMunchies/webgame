//! Real WebSocket clients against a real server on a random local port.

use std::collections::BTreeSet;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async};
use webgame_game::Timers;
use webgame_protocol::{
    ChatChannel, ClientMessage, ErrorCode, GameAction, GameOverInfo, GamePhase, LobbyCode,
    NightAction, Outcome, PROTOCOL_VERSION, PlayerSlot, Role, ServerMessage, decode, encode,
};
use webgame_server::db::Db;
use webgame_server::{Config, app};

async fn start_server(timers: Timers, seed: u64) -> (SocketAddr, Db, PathBuf) {
    let path = std::env::temp_dir().join(format!(
        "webgame-test-{}-{}.db",
        std::process::id(),
        webgame_server::now_ms() ^ seed.wrapping_mul(7919)
    ));
    let db = Db::open(&path).unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let router = app(
        db.clone(),
        Config {
            timers,
            seed: Some(seed),
        },
    );
    tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    (addr, db, path)
}

struct Client {
    ws: WebSocketStream<MaybeTlsStream<TcpStream>>,
    /// Everything received so far.
    seen: Vec<ServerMessage>,
}

impl Client {
    async fn connect(addr: SocketAddr, name: &str) -> Client {
        let (ws, _) = connect_async(format!("ws://{addr}/ws")).await.unwrap();
        let mut client = Client {
            ws,
            seen: Vec::new(),
        };
        client
            .send(ClientMessage::Hello {
                version: PROTOCOL_VERSION,
                username: name.into(),
            })
            .await;
        client
            .wait(|m| matches!(m, ServerMessage::Welcome { .. }))
            .await;
        client
    }

    async fn send(&mut self, message: ClientMessage) {
        self.ws
            .send(Message::Binary(encode(&message).into()))
            .await
            .unwrap();
    }

    async fn recv(&mut self) -> ServerMessage {
        loop {
            let frame = tokio::time::timeout(Duration::from_secs(10), self.ws.next())
                .await
                .expect("server went quiet")
                .expect("connection closed")
                .unwrap();
            if let Message::Binary(bytes) = frame {
                let message: ServerMessage = decode(&bytes).unwrap();
                self.seen.push(message.clone());
                return message;
            }
        }
    }

    /// Reads until a message matches, and returns it.
    async fn wait(&mut self, wanted: impl Fn(&ServerMessage) -> bool) -> ServerMessage {
        loop {
            let message = self.recv().await;
            if wanted(&message) {
                return message;
            }
        }
    }

    async fn error(&mut self) -> ErrorCode {
        match self.wait(|m| matches!(m, ServerMessage::Error(_))).await {
            ServerMessage::Error(err) => err.code,
            _ => unreachable!(),
        }
    }

    async fn create(&mut self) -> LobbyCode {
        self.send(ClientMessage::CreateLobby).await;
        match self.wait(|m| matches!(m, ServerMessage::Lobby(_))).await {
            ServerMessage::Lobby(info) => info.code,
            _ => unreachable!(),
        }
    }

    async fn join(&mut self, code: &LobbyCode) {
        self.send(ClientMessage::JoinLobby { code: code.clone() })
            .await;
        self.wait(|m| matches!(m, ServerMessage::Lobby(_))).await;
    }
}

/// Four players in one lobby, the first as host.
async fn lobby_of_four(addr: SocketAddr) -> (Vec<Client>, LobbyCode) {
    let mut host = Client::connect(addr, "Ada").await;
    let code = host.create().await;
    let mut clients = vec![host];
    for name in ["Bram", "Cleo", "Dev"] {
        let mut client = Client::connect(addr, name).await;
        client.join(&code).await;
        clients.push(client);
    }
    (clients, code)
}

/// A player who does nothing except, as the Mafioso, kill the lowest seat outside the Mafia
/// every night. Plays until the game ends.
async fn play(mut client: Client) -> (Client, GameOverInfo) {
    let mut role = None;
    let mut alive = BTreeSet::new();
    let mut mafia = BTreeSet::new();
    // The game may have started before this loop took over, so replay what already arrived.
    let mut backlog: Vec<ServerMessage> = client.seen.clone();
    loop {
        let message = if backlog.is_empty() {
            client.recv().await
        } else {
            backlog.remove(0)
        };
        match message {
            ServerMessage::GameStarted(start) => {
                role = Some(start.role);
                alive = start.players.iter().map(|p| p.slot).collect();
                mafia = start.team.iter().map(|t| t.slot).collect();
            }
            ServerMessage::RoleChanged { role: new } => role = Some(new),
            ServerMessage::Deaths(deaths) => {
                for death in deaths {
                    alive.remove(&death.slot);
                }
            }
            ServerMessage::Phase {
                phase: GamePhase::Night { .. },
                ..
            } if role == Some(Role::Mafioso) => {
                let victim = *alive.iter().find(|s| !mafia.contains(*s)).unwrap();
                client
                    .send(ClientMessage::Game(GameAction::Night(Some(
                        NightAction::Target(victim),
                    ))))
                    .await;
            }
            ServerMessage::GameOver(result) => return (client, result),
            _ => {}
        }
    }
}

#[tokio::test]
async fn four_players_play_a_whole_game() {
    let (addr, db, path) = start_server(Timers::uniform(300), 42).await;
    let (mut clients, _code) = lobby_of_four(addr).await;

    clients[1].send(ClientMessage::StartGame).await;
    assert_eq!(clients[1].error().await, ErrorCode::NotHost);
    clients[0].send(ClientMessage::StartGame).await;

    // Day 0: a whisper from Ada to Bram. Everyone hears that it happened; only they see it.
    for client in clients.iter_mut() {
        client
            .wait(|m| matches!(m, ServerMessage::GameStarted(_)))
            .await;
    }
    clients[0]
        .send(ClientMessage::Chat {
            channel: ChatChannel::Whisper { to: PlayerSlot(1) },
            text: "psst".into(),
        })
        .await;

    let results = futures_util::future::join_all(clients.into_iter().map(play)).await;
    // With nobody but the Mafioso acting, it kills on nights 1 and 2 and wins.
    for (_, result) in &results {
        assert_eq!(result.outcome, Outcome::Mafia);
    }
    let saw_text = |client: &Client| {
        client
            .seen
            .iter()
            .any(|m| matches!(m, ServerMessage::Chat(c) if c.text == "psst"))
    };
    assert!(saw_text(&results[0].0) && saw_text(&results[1].0));
    assert!(!saw_text(&results[2].0) && !saw_text(&results[3].0));
    assert!(results[2].0.seen.contains(&ServerMessage::Whispered {
        from: PlayerSlot(0),
        to: PlayerSlot(1)
    }));

    // Every message the game sent is in the database, and the game has a result.
    db.flush();
    let sqlite = rusqlite::Connection::open(&path).unwrap();
    let events: i64 = sqlite
        .query_row("SELECT count(*) FROM game_events", [], |r| r.get(0))
        .unwrap();
    let finished: i64 = sqlite
        .query_row(
            "SELECT count(*) FROM games WHERE result IS NOT NULL",
            [],
            |r| r.get(0),
        )
        .unwrap();
    let users: i64 = sqlite
        .query_row("SELECT count(*) FROM users", [], |r| r.get(0))
        .unwrap();
    assert!(events > 10, "only {events} events logged");
    assert_eq!(finished, 1);
    assert_eq!(users, 4);
    let _ = std::fs::remove_file(path);
}

#[tokio::test]
async fn a_player_who_reconnects_gets_their_seat_back() {
    let (addr, _db, path) = start_server(Timers::uniform(60_000), 7).await;
    let (mut clients, code) = lobby_of_four(addr).await;
    clients[0].send(ClientMessage::StartGame).await;
    let ServerMessage::GameStarted(before) = clients[2]
        .wait(|m| matches!(m, ServerMessage::GameStarted(_)))
        .await
    else {
        unreachable!()
    };

    // Cleo's connection drops, and they come back under the same name.
    let cleo = clients.remove(2);
    drop(cleo);
    let mut cleo = Client::connect(addr, "cleo").await;
    cleo.join(&code).await;
    let ServerMessage::GameStarted(after) = cleo
        .wait(|m| matches!(m, ServerMessage::GameStarted(_)))
        .await
    else {
        unreachable!()
    };
    assert_eq!(after.you, before.you);
    assert_eq!(after.role, before.role);

    // Someone new can't join mid-game.
    let mut late = Client::connect(addr, "Edie").await;
    late.send(ClientMessage::JoinLobby { code }).await;
    assert_eq!(late.error().await, ErrorCode::GameInProgress);
    let _ = std::fs::remove_file(path);
}

#[tokio::test]
async fn bad_requests_get_clear_errors() {
    let (addr, _db, path) = start_server(Timers::uniform(60_000), 1).await;

    let (mut ws, _) = connect_async(format!("ws://{addr}/ws")).await.unwrap();
    let hello = ClientMessage::Hello {
        version: PROTOCOL_VERSION + 1,
        username: "Ada".into(),
    };
    ws.send(Message::Binary(encode(&hello).into()))
        .await
        .unwrap();
    let mut old = Client {
        ws,
        seen: Vec::new(),
    };
    assert_eq!(old.error().await, ErrorCode::VersionMismatch);
    old.send(ClientMessage::CreateLobby).await;
    assert_eq!(old.error().await, ErrorCode::NotIdentified);

    let mut ada = Client::connect(addr, "Ada").await;
    ada.send(ClientMessage::JoinLobby {
        code: LobbyCode::parse("ZZZZZZ").unwrap(),
    })
    .await;
    assert_eq!(ada.error().await, ErrorCode::LobbyNotFound);
    ada.create().await;
    ada.send(ClientMessage::StartGame).await;
    assert_eq!(ada.error().await, ErrorCode::NotEnoughPlayers);
    ada.send(ClientMessage::Game(GameAction::Vote(None))).await;
    assert_eq!(ada.error().await, ErrorCode::NotAllowedNow);
    let _ = std::fs::remove_file(path);
}
