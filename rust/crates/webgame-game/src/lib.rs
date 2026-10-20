//! The game engine: the rules of a game, with no networking, clock, or storage.
//!
//! A [`Game`] is driven from outside. [`Game::handle`] applies one player's input and
//! [`Game::tick`] moves to the next phase once its deadline has passed. Both return the
//! messages to send as [`Outgoing`] values, each with the [`Audience`] allowed to see it, so
//! deciding who learns what (roles, whispers, night results) happens here and can be tested
//! without a server. Time is passed in as milliseconds, so tests can run a whole game instantly.

mod game;
pub mod night;
mod player;
pub mod setup;
pub mod win;

use serde::Serialize;
use webgame_protocol::{PlayerSlot, ServerMessage, UserId};

pub use game::{Game, Input};
pub use player::Player;

/// One player's seat when a game starts.
#[derive(Clone, Debug)]
pub struct Seat {
    pub slot: PlayerSlot,
    pub user_id: UserId,
    pub name: String,
}

/// Who may see a message.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum Audience {
    All,
    One(PlayerSlot),
    Many(Vec<PlayerSlot>),
}

impl Audience {
    pub fn includes(&self, slot: PlayerSlot) -> bool {
        match self {
            Audience::All => true,
            Audience::One(one) => *one == slot,
            Audience::Many(many) => many.contains(&slot),
        }
    }
}

/// A message for the server to deliver.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Outgoing {
    pub to: Audience,
    pub message: ServerMessage,
}

impl Outgoing {
    pub fn all(message: ServerMessage) -> Self {
        Outgoing {
            to: Audience::All,
            message,
        }
    }

    pub fn one(slot: PlayerSlot, message: ServerMessage) -> Self {
        Outgoing {
            to: Audience::One(slot),
            message,
        }
    }
}

/// How long each phase lasts, in milliseconds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Timers {
    pub day_zero: u64,
    pub discussion: u64,
    pub voting: u64,
    pub defense: u64,
    pub judgement: u64,
    pub last_words: u64,
    pub night: u64,
}

impl Timers {
    /// Lengths close to Town of Salem's.
    pub const NORMAL: Timers = Timers {
        day_zero: 15_000,
        discussion: 45_000,
        voting: 60_000,
        defense: 20_000,
        judgement: 20_000,
        last_words: 7_000,
        night: 37_000,
    };

    /// Short phases for trying the game out by hand.
    pub const FAST: Timers = Timers {
        day_zero: 10_000,
        discussion: 15_000,
        voting: 30_000,
        defense: 10_000,
        judgement: 10_000,
        last_words: 5_000,
        night: 20_000,
    };

    /// Every phase takes the same time. Handy in tests.
    pub const fn uniform(ms: u64) -> Timers {
        Timers {
            day_zero: ms,
            discussion: ms,
            voting: ms,
            defense: ms,
            judgement: ms,
            last_words: ms,
            night: ms,
        }
    }
}

impl Default for Timers {
    fn default() -> Self {
        Timers::NORMAL
    }
}
