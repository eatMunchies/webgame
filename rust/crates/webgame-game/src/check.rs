//! A skill check being played, and the chance it passes.
//!
//! For now the client judges the check and reports the chance itself (see
//! [`MinigamePlay::Check`]). This is the only place that turns what a client sends into that
//! chance, so making the server authoritative means changing just this: have the client send
//! its raw inputs instead, and work the chance out from them here, the way [`crate::duel`]
//! runs fights.

use webgame_protocol::{MAX_CHANCE, MinigamePlay};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Check {
    /// Out of [`MAX_CHANCE`]. Zero until the client reports anything.
    chance: u8,
    done: bool,
}

impl Check {
    /// Takes a play from the player, or says why it doesn't fit a skill check.
    pub fn play(&mut self, play: MinigamePlay) -> Result<(), &'static str> {
        match play {
            MinigamePlay::Check { chance, done } => {
                if chance > MAX_CHANCE {
                    return Err("A skill check's chance is out of 100.");
                }
                self.chance = chance;
                self.done = done;
                Ok(())
            }
            _ => Err("That isn't a skill check play."),
        }
    }

    /// Whether the player is finished, so the check can be decided now rather than when the
    /// stage ends.
    pub fn is_done(&self) -> bool {
        self.done
    }

    /// The chance the check passes, from 0 to 1.
    pub fn chance(&self) -> f64 {
        f64::from(self.chance) / f64::from(MAX_CHANCE)
    }
}
