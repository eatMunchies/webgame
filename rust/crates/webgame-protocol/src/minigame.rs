//! The night's minigames: what the server hands each player, what they send back, and the
//! state of a fight.
//!
//! Skill checks are judged by the client, which reports whether the player passed. Fights are
//! run by the server, since two players have to agree on them: each side sends its moves and
//! the server sends both the fight as it stands.
//!
//! A client that can't show minigames (the terminal client, played by people or programs
//! testing the game) sends [`MinigamePlay::Roll`] instead, and the server decides at random. A
//! server only allows that when it is started for testing.

use serde::{Deserialize, Serialize};

/// A minigame given to one player for one stage of the night.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Minigame {
    /// A one-player skill check. Failing it means the night action does nothing, though the
    /// player still visits their target.
    SkillCheck,
    /// A fight between an attacker and their victim. Neither learns who the other is. The
    /// attack only goes ahead if the attacker wins; the victim wins by knocking the attacker
    /// out or lasting until the stage ends.
    Fight { attacking: bool },
    /// Nothing rides on it.
    Passive,
}

/// Something a player does in their minigame.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum MinigamePlay {
    /// The skill check's result. Only the first report counts.
    Check { passed: bool },
    /// Let the server decide this minigame at random. Refused unless the server allows it.
    Roll,
    /// In a fight: start a move, which lands after its windup.
    Move(FightMove),
    /// In a fight: raise or lower guard.
    Guard(bool),
}

/// A fight's attacks. Each beats one thing and loses to another, so neither side can win by
/// doing one thing over and over:
///
/// - A strike hits an open opponent and interrupts their windup, but bounces off a guard and
///   leaves the striker staggered.
/// - A grab breaks a guard, but its windup is slow enough to be struck out of, and grabbing an
///   unguarded opponent misses and staggers the grabber.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum FightMove {
    Strike,
    Grab,
}

impl FightMove {
    /// How long the move takes to land, in milliseconds.
    pub fn windup_ms(self) -> u32 {
        match self {
            FightMove::Strike => STRIKE_WINDUP_MS,
            FightMove::Grab => GRAB_WINDUP_MS,
        }
    }
}

/// Each fighter starts with this many hits to lose.
pub const FIGHT_HP: u8 = 3;
pub const STRIKE_WINDUP_MS: u32 = 400;
pub const GRAB_WINDUP_MS: u32 = 650;
/// How long a strike into a guard, or a missed grab, leaves the attacker unable to act.
pub const STAGGER_MS: u32 = 800;
/// The Kill stage is split into this many rounds, each with its own fights.
pub const FIGHT_ROUNDS: u8 = 3;

/// One side of a fight. Times are milliseconds from when the message was sent, so clients
/// don't need a clock that agrees with the server's.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Fighter {
    pub hp: u8,
    pub guarding: bool,
    /// A move being wound up, and how long until it lands.
    pub winding: Option<(FightMove, u32)>,
    /// How long until this fighter can act again. Zero when they can.
    pub staggered_ms: u32,
}

/// A fight as one of its fighters sees it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FightView {
    pub you: Fighter,
    pub opponent: Fighter,
}

/// How a minigame ended.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum MinigameResult {
    Passed,
    Failed,
    Won,
    Lost,
}
