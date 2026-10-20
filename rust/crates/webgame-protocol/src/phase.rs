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
        stage: NightStage,
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

/// The parts of a night, always in this order and always the same length, so their timing gives
/// nothing away. Players pick their actions while Choosing. In each later stage every living
/// player plays one minigame: a skill check for an action played out in that stage, a fight for
/// an attack, or a passive game for everyone else.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum NightStage {
    Choosing,
    /// Barkeeps and Escorts.
    Roleblock,
    /// Fights and the other killing actions, over [`crate::FIGHT_ROUNDS`] rounds (from 1), so
    /// a player attacked twice fights each attacker in turn.
    Kill {
        round: u8,
    },
    /// Heals, guards, traps, alerts and vests.
    Protect,
    /// Investigations.
    Investigate,
}

impl NightStage {
    /// The stage after this one, or None after the last.
    pub fn next(self) -> Option<NightStage> {
        Some(match self {
            NightStage::Choosing => NightStage::Roleblock,
            NightStage::Roleblock => NightStage::Kill { round: 1 },
            NightStage::Kill { round } if round < crate::FIGHT_ROUNDS => {
                NightStage::Kill { round: round + 1 }
            }
            NightStage::Kill { .. } => NightStage::Protect,
            NightStage::Protect => NightStage::Investigate,
            NightStage::Investigate => return None,
        })
    }
}

impl GamePhase {
    pub fn is_night(&self) -> bool {
        matches!(self, GamePhase::Night { .. })
    }

    /// Whether night actions can still be picked or changed.
    pub fn is_choosing(&self) -> bool {
        matches!(
            self,
            GamePhase::Night {
                stage: NightStage::Choosing,
                ..
            }
        )
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
