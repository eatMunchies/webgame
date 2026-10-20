//! The SQLite record of users, lobbies, and games.
//!
//! Writes go to a background thread over a channel, so a lobby's task never waits on the disk.
//! Nothing here is read back while the server runs: live games live in memory, and the
//! database is the record of what happened (see `migrations/0001_init.sql`).

use std::path::Path;
use std::sync::mpsc;
use std::thread;

use rusqlite::{Connection, params};
use webgame_game::Audience;
use webgame_protocol::{GameOverInfo, LobbyCode, ServerMessage, UserId};

use crate::now_ms;

enum Op {
    UserSeen {
        id: UserId,
        username: String,
        at: u64,
    },
    LobbyOpened {
        code: LobbyCode,
        host: UserId,
        at: u64,
    },
    LobbyClosed {
        code: LobbyCode,
        at: u64,
    },
    GameStarted {
        id: i64,
        lobby: LobbyCode,
        seed: u64,
        players: String,
        at: u64,
    },
    Event {
        game: i64,
        seq: i64,
        at: u64,
        audience: String,
        message: String,
    },
    GameEnded {
        id: i64,
        result: String,
        at: u64,
    },
    Flush(mpsc::Sender<()>),
}

/// A handle to the database writer. Clones share one writer thread.
#[derive(Clone)]
pub struct Db {
    ops: mpsc::Sender<Op>,
}

impl Db {
    /// Opens (or creates) the database at `path` and starts its writer thread. `:memory:`
    /// gives a throwaway database.
    pub fn open(path: impl AsRef<Path>) -> rusqlite::Result<Db> {
        let connection = Connection::open(path)?;
        connection.execute_batch(include_str!("../migrations/0001_init.sql"))?;
        let (ops, inbox) = mpsc::channel();
        thread::Builder::new()
            .name("db-writer".into())
            .spawn(move || write_loop(connection, inbox))
            .expect("can spawn the database thread");
        Ok(Db { ops })
    }

    fn send(&self, op: Op) {
        // The writer only stops when every handle is gone, so this can't fail while `self`
        // exists.
        let _ = self.ops.send(op);
    }

    pub fn user_seen(&self, id: UserId, username: &str) {
        self.send(Op::UserSeen {
            id,
            username: username.to_string(),
            at: now_ms(),
        });
    }

    pub fn lobby_opened(&self, code: &LobbyCode, host: UserId) {
        self.send(Op::LobbyOpened {
            code: code.clone(),
            host,
            at: now_ms(),
        });
    }

    pub fn lobby_closed(&self, code: &LobbyCode) {
        self.send(Op::LobbyClosed {
            code: code.clone(),
            at: now_ms(),
        });
    }

    /// Records a new game. `players` is (slot, user, name) for each seat.
    pub fn game_started(
        &self,
        id: i64,
        lobby: &LobbyCode,
        seed: u64,
        players: &[(u8, UserId, String)],
    ) {
        let players = serde_json::Value::Array(
            players
                .iter()
                .map(|(slot, user, name)| {
                    serde_json::json!({ "slot": slot, "user_id": user.0, "name": name })
                })
                .collect(),
        );
        self.send(Op::GameStarted {
            id,
            lobby: lobby.clone(),
            seed,
            players: players.to_string(),
            at: now_ms(),
        });
    }

    pub fn game_event(&self, game: i64, seq: i64, audience: &Audience, message: &ServerMessage) {
        self.send(Op::Event {
            game,
            seq,
            at: now_ms(),
            audience: serde_json::to_string(audience).expect("audiences serialize"),
            message: serde_json::to_string(message).expect("messages serialize"),
        });
    }

    pub fn game_ended(&self, id: i64, result: &GameOverInfo) {
        self.send(Op::GameEnded {
            id,
            result: serde_json::to_string(result).expect("results serialize"),
            at: now_ms(),
        });
    }

    /// Blocks until every write sent before this call is on disk.
    pub fn flush(&self) {
        let (done, wait) = mpsc::channel();
        self.send(Op::Flush(done));
        let _ = wait.recv();
    }
}

fn write_loop(connection: Connection, inbox: mpsc::Receiver<Op>) {
    for op in inbox {
        if let Err(err) = apply(&connection, op) {
            eprintln!("database write failed: {err}");
        }
    }
}

fn apply(db: &Connection, op: Op) -> rusqlite::Result<()> {
    // SQLite integers are signed; ids and seeds are stored as the same 64 bits.
    match op {
        Op::UserSeen { id, username, at } => db.execute(
            "INSERT INTO users (id, username, created_at, last_seen) VALUES (?1, ?2, ?3, ?3)
             ON CONFLICT (id) DO UPDATE SET username = ?2, last_seen = ?3",
            params![id.0 as i64, username, at as i64],
        )?,
        Op::LobbyOpened { code, host, at } => db.execute(
            "INSERT INTO lobbies (code, host_id, opened_at) VALUES (?1, ?2, ?3)",
            params![code.as_str(), host.0 as i64, at as i64],
        )?,
        Op::LobbyClosed { code, at } => db.execute(
            "UPDATE lobbies SET closed_at = ?2 WHERE code = ?1 AND closed_at IS NULL",
            params![code.as_str(), at as i64],
        )?,
        Op::GameStarted { id, lobby, seed, players, at } => db.execute(
            "INSERT INTO games (id, lobby_code, seed, players, started_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, lobby.as_str(), seed as i64, players, at as i64],
        )?,
        Op::Event { game, seq, at, audience, message } => db.execute(
            "INSERT INTO game_events (game_id, seq, at, audience, message) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![game, seq, at as i64, audience, message],
        )?,
        Op::GameEnded { id, result, at } => db.execute(
            "UPDATE games SET ended_at = ?2, result = ?3 WHERE id = ?1",
            params![id, at as i64, result],
        )?,
        Op::Flush(done) => {
            let _ = done.send(());
            0
        }
    };
    Ok(())
}
