//! A fight opponent for `--fight-bot`, so a person in the Godot client can fight a terminal
//! bot for real instead of having the fight rolled. It plays like the minigame tester's
//! practice bot: it looks at the fight every reaction time, now and then misses a move, and
//! answers what it sees: guard a strike (if the guard can come up in time), strike a grab
//! that's far enough off, grab a guard that will outlast the grab, hit someone dazed.

use std::time::{Duration, Instant};

use webgame_protocol::{
    FightMove, FightView, GRAB_WINDUP_MS, GUARD_RAISE_MS, MinigamePlay, STRIKE_WINDUP_MS,
};

/// How long the bot takes to look at the fight again, in milliseconds.
const REACTION_MS: (u64, u64) = (350, 600);
/// How often it doesn't react at all, so it can be beaten.
const MISS_CHANCE: f64 = 0.25;

pub struct FightBot {
    rng: u64,
    next_look: Instant,
}

impl FightBot {
    pub fn new() -> Self {
        let clock = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |time| time.as_nanos() as u64);
        let seed = clock ^ u64::from(std::process::id()).rotate_left(32);
        FightBot {
            rng: seed | 1,
            next_look: Instant::now(),
        }
    }

    /// A number in [0, 1), from a xorshift generator: plenty for a bot's whims.
    fn random(&mut self) -> f64 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        (self.rng >> 11) as f64 / (1u64 << 53) as f64
    }

    /// Waits out the countdown before a fight, plus a reaction time.
    pub fn start(&mut self, delay: Duration) {
        self.next_look = Instant::now() + delay;
    }

    /// What to play now, given the fight as last sent `elapsed` milliseconds ago, if it's
    /// time to look and there's something worth doing.
    pub fn think(
        &mut self,
        view: &FightView,
        elapsed: u32,
        attacking: bool,
    ) -> Option<MinigamePlay> {
        let now = Instant::now();
        if now < self.next_look {
            return None;
        }
        let (low, high) = REACTION_MS;
        let wait = low + ((high - low) as f64 * self.random()) as u64;
        self.next_look = now + Duration::from_millis(wait);
        if self.random() < MISS_CHANCE {
            return None;
        }
        let left = |ms: u32| ms.saturating_sub(elapsed);
        let me = &view.you;
        let them = &view.opponent;
        if me.winding.is_some() || left(me.staggered_ms) > 0 {
            return None;
        }
        let my_guard = left(me.guard_ms) > 0;
        let can_guard = !my_guard && left(me.guard_cooldown_ms) == 0;
        match them.winding {
            Some((FightMove::Strike, lands)) => {
                return (can_guard && left(lands) > GUARD_RAISE_MS)
                    .then_some(MinigamePlay::Guard(true));
            }
            Some((FightMove::Grab, lands)) => {
                if left(lands) > STRIKE_WINDUP_MS {
                    return Some(MinigamePlay::Move(FightMove::Strike));
                }
                // Too late to strike first: drop the guard so the grab misses.
                return my_guard.then_some(MinigamePlay::Guard(false));
            }
            None => {}
        }
        if left(them.guard_ms) > GRAB_WINDUP_MS {
            return Some(MinigamePlay::Move(FightMove::Grab));
        }
        if left(them.staggered_ms) > 0 {
            return Some(MinigamePlay::Move(FightMove::Strike));
        }
        let strike_chance = if attacking { 0.6 } else { 0.3 };
        if self.random() < strike_chance || !can_guard {
            Some(MinigamePlay::Move(FightMove::Strike))
        } else {
            Some(MinigamePlay::Guard(true))
        }
    }
}
