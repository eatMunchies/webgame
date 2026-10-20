use serde::{Deserialize, Serialize};

use crate::PlayerSlot;

/// A night action. Which shapes a role may send is given by [`crate::Role::target_rule`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum NightAction {
    /// Visit one player (or yourself, for a self-heal or self-vest).
    Target(PlayerSlot),
    /// The Copycat: copy the first player's ability and use it on the second.
    TwoTargets(PlayerSlot, PlayerSlot),
    /// Switch on an ability that has no target: a Veteran's alert, a Survivor's vest, an
    /// Arsonist's ignite, a Jailer's execution.
    Activate,
}

/// A vote during a trial's judgement.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Verdict {
    Guilty,
    Innocent,
    Abstain,
}
