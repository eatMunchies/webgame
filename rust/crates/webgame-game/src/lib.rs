//! The game engine: the rules of a game, with no networking, clock, or storage.
//!
//! A [`Game`] is driven from outside. [`Game::handle`] applies one player's input and
//! [`Game::tick`] moves to the next phase once its deadline has passed. Both return the
//! messages to send as [`Outgoing`] values, each with the [`Audience`] allowed to see it, so
//! deciding who learns what (roles, whispers, night results) happens here and can be tested
//! without a server. Time is passed in as milliseconds, so tests can run a whole game instantly.

mod check;
mod duel;
mod game;
pub mod night;
mod player;
pub mod setup;
pub mod win;

use serde::Serialize;
use webgame_protocol::{MINIGAME_INTRO_MS, NightStage, PlayerSlot, ServerMessage, UserId};

pub use duel::Duel;
pub use game::{FIGHT_ROLL_CHANCE, Game, Input, ROLL_PASS_CHANCE};
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
    /// A morning with nobody to bury: long enough to see the town wake up.
    pub morning: u64,
    /// Added to a morning, and to an execution, for each funeral it holds.
    pub funeral: u64,
    /// The execution itself, before the executed player's funeral.
    pub execution: u64,
    /// The start of the night, while players pick their actions.
    pub choosing: u64,
    pub roleblock: u64,
    /// Each of the Actions stage's rounds. A fight that outlasts its round runs on until a
    /// knockout.
    pub action_round: u64,
    /// Added to every stage of the night after choosing, for the countdown clients show
    /// before a skill check or fight, so the stage's own time is all play.
    pub minigame_intro: u64,
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
        morning: 4_000,
        funeral: 9_000,
        execution: 4_000,
        // A night is about 49 seconds: 12 choosing, 8 for roleblocks, 10 for each of the two
        // action rounds, and the 3 second countdown before each of those three stages.
        choosing: 12_000,
        roleblock: 8_000,
        action_round: 10_000,
        minigame_intro: MINIGAME_INTRO_MS as u64,
    };

    /// Short phases for trying the game out by hand. Choosing stays long enough for players
    /// typing commands, and the skill check stages long enough to play one.
    pub const FAST: Timers = Timers {
        day_zero: 10_000,
        discussion: 15_000,
        voting: 30_000,
        defense: 10_000,
        judgement: 10_000,
        last_words: 5_000,
        morning: 3_000,
        funeral: 7_000,
        execution: 3_000,
        choosing: 15_000,
        roleblock: 8_000,
        action_round: 10_000,
        minigame_intro: MINIGAME_INTRO_MS as u64,
    };

    /// Every phase takes the same time, with no countdown before minigames. Handy in tests.
    pub const fn uniform(ms: u64) -> Timers {
        Timers {
            day_zero: ms,
            discussion: ms,
            voting: ms,
            defense: ms,
            judgement: ms,
            last_words: ms,
            morning: ms,
            funeral: 0,
            execution: ms,
            choosing: ms,
            roleblock: ms,
            action_round: ms,
            minigame_intro: 0,
        }
    }

    /// How long a stage of the night lasts, counting the countdown before its minigames.
    pub fn night_stage(&self, stage: NightStage) -> u64 {
        let play = match stage {
            NightStage::Choosing => return self.choosing,
            NightStage::Roleblock => self.roleblock,
            NightStage::Actions { .. } => self.action_round,
        };
        play + self.minigame_intro
    }
}

impl Default for Timers {
    fn default() -> Self {
        Timers::NORMAL
    }
}
