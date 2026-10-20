//! The directory of live lobbies, by code.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use rand::seq::IndexedRandom;
use tokio::sync::mpsc;
use webgame_protocol::{CODE_ALPHABET, CODE_LENGTH, LobbyCode, UserId};

use crate::Config;
use crate::db::Db;
use crate::lobby::{Connection, Lobby, LobbyCmd};

/// A way to send commands to a lobby's task.
pub type LobbyHandle = mpsc::Sender<LobbyCmd>;

pub struct Registry {
    lobbies: Mutex<HashMap<LobbyCode, LobbyHandle>>,
    db: Db,
    config: Arc<Config>,
}

impl Registry {
    pub fn new(db: Db, config: Config) -> Arc<Self> {
        Arc::new(Registry {
            lobbies: Mutex::new(HashMap::new()),
            db,
            config: Arc::new(config),
        })
    }

    pub fn db(&self) -> &Db {
        &self.db
    }

    /// Opens a lobby with `host` in it and starts its task. The task removes the lobby from the
    /// registry when it ends.
    pub fn create(
        self: &Arc<Self>,
        host: UserId,
        name: String,
        connection: Connection,
    ) -> (LobbyCode, LobbyHandle) {
        let (handle, inbox) = mpsc::channel(64);
        let code = {
            let mut lobbies = self.lobbies.lock().unwrap();
            let code = loop {
                let code = random_code();
                if !lobbies.contains_key(&code) {
                    break code;
                }
            };
            lobbies.insert(code.clone(), handle.clone());
            code
        };
        let lobby = Lobby::new(
            code.clone(),
            host,
            name,
            connection,
            self.db.clone(),
            self.config.clone(),
        );
        let registry = Arc::clone(self);
        let closing = code.clone();
        tokio::spawn(async move {
            lobby.run(inbox).await;
            registry.lobbies.lock().unwrap().remove(&closing);
        });
        (code, handle)
    }

    pub fn find(&self, code: &LobbyCode) -> Option<LobbyHandle> {
        self.lobbies.lock().unwrap().get(code).cloned()
    }
}

fn random_code() -> LobbyCode {
    let alphabet: Vec<char> = CODE_ALPHABET.chars().collect();
    let mut rng = rand::rng();
    let code: String = (0..CODE_LENGTH)
        .map(|_| *alphabet.choose(&mut rng).unwrap())
        .collect();
    LobbyCode::parse(&code).expect("built from the code alphabet")
}
