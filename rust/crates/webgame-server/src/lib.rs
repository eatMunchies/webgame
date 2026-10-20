//! The game server: lobbies and games over WebSockets.
//!
//! Clients connect to `/ws` and exchange [`webgame_protocol`] messages as binary frames. Each
//! connection runs as a session task, each lobby as a lobby task that owns its game, and the
//! [`registry::Registry`] maps lobby codes to lobby tasks. See the README for running it.

pub mod db;
mod lobby;
pub mod registry;
mod session;

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::Router;
use axum::extract::{State, WebSocketUpgrade};
use axum::response::IntoResponse;
use axum::routing::get;
use webgame_game::Timers;

use crate::db::Db;
use crate::registry::Registry;

/// Server settings that games need.
#[derive(Clone, Debug, Default)]
pub struct Config {
    pub timers: Timers,
    /// Seeds every game the same way, so roles and random picks repeat. Random when None.
    pub seed: Option<u64>,
}

/// The HTTP routes: `/ws` for the game and `/health` to check the server is up.
pub fn app(db: Db, config: Config) -> Router {
    Router::new()
        .route("/ws", get(websocket))
        .route("/health", get(|| async { "ok" }))
        .with_state(Registry::new(db, config))
}

async fn websocket(
    ws: WebSocketUpgrade,
    State(registry): State<Arc<Registry>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| session::run(socket, registry))
}

/// Milliseconds since the Unix epoch: the clock games and the database use.
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
