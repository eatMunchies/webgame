use serde::{Deserialize, Serialize};

use crate::PlayerSlot;

/// Where a game is in its cycle. A game starts on Day 0 (a short discussion with no voting),
/// then alternates Night 1, Day 1, Night 2, Day 2, and so on.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum GamePhase {
    /// Players are in the lobby; no game is running.
    Lobby,
    Day {
        day: u32,
        stage: DayStage,
    },
    Night {
        night: u32,
    },
    GameOver,
}

/// The parts of a day. Discussion leads to Voting. When enough votes land on one player they go
/// on trial: Defense, then Judgement. A guilty verdict leads to LastWords and the lynch, which
/// ends the day. Otherwise voting resumes, up to [`crate::TRIALS_PER_DAY`] trials.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum DayStage {
    Discussion,
    Voting { trials_left: u8 },
    Defense { accused: PlayerSlot },
    Judgement { accused: PlayerSlot },
    LastWords { accused: PlayerSlot },
}

impl GamePhase {
    pub fn is_night(&self) -> bool {
        matches!(self, GamePhase::Night { .. })
    }

    pub fn is_day(&self) -> bool {
        matches!(self, GamePhase::Day { .. })
    }

    /// The player on trial, during the trial stages of a day.
    pub fn accused(&self) -> Option<PlayerSlot> {
        match self {
            GamePhase::Day {
                stage:
                    DayStage::Defense { accused }
                    | DayStage::Judgement { accused }
                    | DayStage::LastWords { accused },
                ..
            } => Some(*accused),
            _ => None,
        }
    }
}
