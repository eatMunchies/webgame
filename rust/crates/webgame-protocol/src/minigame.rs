//! The night's minigames: what the server hands each player, what they send back, and the
//! state of a fight.
//!
//! A skill check is played on the client, which shows it however it likes (a timing dial, a
//! typing test, ...) and reports the chance it should pass, out of [`MAX_CHANCE`]. The server
//! rolls once with that chance when the client says it's done, or when the stage ends with the
//! last chance reported (none counts as 0). Fights are
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
    /// A one-player skill check, played on the client. Failing it means the night action does
    /// nothing, though the player still visits their target.
    SkillCheck,
    /// A fight between an attacker and their victim. Neither learns who the other is. The
    /// attack only goes ahead if the attacker wins. It goes on until one of them is knocked
    /// out (the victim wins if both are), running past the stage's time if it has to.
    Fight { attacking: bool },
    /// Nothing rides on it.
    Passive,
}

/// Something a player does in their minigame.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum MinigamePlay {
    /// How a skill check is going: the chance it should pass, out of [`MAX_CHANCE`], and whether
    /// the player is done, which decides it now. Each report replaces the last, so a check the
    /// stage ends on is decided from the latest. Reports after it is decided are refused.
    Check { chance: u8, done: bool },
    /// Let the server decide this minigame at random. Refused unless the server allows it.
    Roll,
    /// In a fight: start a move, which lands after its windup.
    Move(FightMove),
    /// In a fight: `true` raises a guard, which comes up after [`GUARD_RAISE_MS`], stays up for
    /// [`GUARD_MS`] and then drops on its own; `false` drops it now. Either way another can't be
    /// raised for [`GUARD_COOLDOWN_MS`] after it ends.
    Guard(bool),
}

/// A fight's attacks. Each beats one thing and loses to another, so neither side can win by
/// doing one thing over and over:
///
/// - A strike hits an open opponent and interrupts their windup, but bounces off a guard and
///   leaves the striker staggered. A guard is a tap that takes [`GUARD_RAISE_MS`] to come up,
///   lasts [`GUARD_MS`] and then can't be raised again for [`GUARD_COOLDOWN_MS`], so it has to
///   be timed against a strike rather than held.
/// - A grab breaks a guard, but a strike started with it lands first, and grabbing an
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

/// A skill check's chance of passing is out of this, so it is a percentage.
pub const MAX_CHANCE: u8 = 100;
/// Each fighter starts with this many hits to lose.
pub const FIGHT_HP: u8 = 3;
/// A strike's windup is long enough to see coming and guard. A grab is only a little slower,
/// so a strike beats it only when started almost with it, on a read: seeing a grab and then
/// striking is too late. That keeps a held guard from being safe against everything.
pub const STRIKE_WINDUP_MS: u32 = 1_400;
pub const GRAB_WINDUP_MS: u32 = 1_600;
/// How long a guard stays up after it's raised: longer than a grab's windup, so a guard seen
/// going up can still be grabbed.
pub const GUARD_MS: u32 = 3_200;
/// How long a guard takes to come up after it's raised, half a strike's windup: enough to
/// guard a strike seen coming, not one about to land.
pub const GUARD_RAISE_MS: u32 = STRIKE_WINDUP_MS / 2;
/// How long after a guard ends (dropping on its own, dropped, broken by a grab, or lowered
/// to attack) before another can be raised. As long as a strike's windup, so a strike started
/// as a guard ends always lands: a guard can't be kept up all fight.
pub const GUARD_COOLDOWN_MS: u32 = STRIKE_WINDUP_MS;
/// How long a strike into a guard, or a missed grab, leaves the attacker unable to act.
pub const STAGGER_MS: u32 = 2_200;
/// The Kill stage is split into this many rounds, each with its own fights.
pub const FIGHT_ROUNDS: u8 = 3;
/// How long the countdown before a skill check or fight lasts ("Skill Check", "Fight
/// starting", then 3, 2, 1). The server adds it to each minigame stage, so it never comes out
/// of the time to play.
pub const MINIGAME_INTRO_MS: u32 = 3_000;

/// One side of a fight. Times are milliseconds from when the message was sent, so clients
/// don't need a clock that agrees with the server's.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Fighter {
    pub hp: u8,
    /// How long until this fighter's guard drops, counting the time it takes to come up.
    /// Zero when there's no guard.
    pub guard_ms: u32,
    /// How long until a raised guard is up and blocks ([`GUARD_RAISE_MS`] after raising).
    /// Zero once it's up, or with no guard.
    pub raising_ms: u32,
    /// How long until this fighter can raise a guard again, counting any guard still raised and
    /// its cooldown after. Zero when they can.
    pub guard_cooldown_ms: u32,
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
