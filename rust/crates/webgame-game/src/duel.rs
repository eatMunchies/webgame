//! A fight between an attacker and their victim, run by the server so both players see the
//! same one. See [`FightMove`] for how the moves beat each other.
//!
//! A fight only changes when a player sends a move or a windup lands, so it is driven like the
//! game: [`Duel::next_landing`] says when it next needs time to pass, and [`Duel::land`] moves
//! it there.

use webgame_protocol::{
    FIGHT_HP, FightMove, FightView, Fighter, GUARD_COOLDOWN_MS, GUARD_MS, GUARD_RAISE_MS,
    MinigamePlay, PlayerSlot, STAGGER_MS,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Side {
    hp: u8,
    /// When a raised guard comes up, and when it drops: it blocks from the one until the other.
    guard_from: u64,
    guard_until: u64,
    /// When a guard can next be raised.
    guard_ready_at: u64,
    /// A move being wound up, and when it lands.
    winding: Option<(FightMove, u64)>,
    staggered_until: u64,
}

impl Side {
    fn new() -> Self {
        Side {
            hp: FIGHT_HP,
            guard_from: 0,
            guard_until: 0,
            guard_ready_at: 0,
            winding: None,
            staggered_until: 0,
        }
    }

    fn guarding_at(&self, at: u64) -> bool {
        self.guard_from <= at && at < self.guard_until
    }

    /// Whether a guard is raised at `at`, up or still coming up.
    fn guard_raised_at(&self, at: u64) -> bool {
        at < self.guard_until
    }

    /// Ends a raised guard at `at`, starting its cooldown.
    fn end_guard(&mut self, at: u64) {
        if self.guard_raised_at(at) {
            self.guard_until = at;
            self.guard_from = self.guard_from.min(at);
            self.guard_ready_at = at + u64::from(GUARD_COOLDOWN_MS);
        }
    }

    fn view(&self, now: u64) -> Fighter {
        let gap = |at: u64| at.saturating_sub(now) as u32;
        let raised = self.guard_raised_at(now);
        Fighter {
            hp: self.hp,
            guard_ms: if raised { gap(self.guard_until) } else { 0 },
            raising_ms: if raised { gap(self.guard_from) } else { 0 },
            guard_cooldown_ms: gap(self.guard_ready_at),
            winding: self
                .winding
                .map(|(play, at)| (play, at.saturating_sub(now) as u32)),
            staggered_ms: self.staggered_until.saturating_sub(now) as u32,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Duel {
    pub attacker: PlayerSlot,
    pub victim: PlayerSlot,
    /// The attacker, then the victim.
    sides: [Side; 2],
    /// Whether the attacker won, once the fight is over.
    pub attacker_won: Option<bool>,
}

impl Duel {
    pub fn new(attacker: PlayerSlot, victim: PlayerSlot) -> Self {
        Duel {
            attacker,
            victim,
            sides: [Side::new(), Side::new()],
            attacker_won: None,
        }
    }

    pub fn is_over(&self) -> bool {
        self.attacker_won.is_some()
    }

    /// Ends the fight with a winner, if it hasn't ended.
    pub fn finish(&mut self, attacker_won: bool) {
        if self.attacker_won.is_none() {
            self.attacker_won = Some(attacker_won);
        }
    }

    fn side(&self, slot: PlayerSlot) -> Option<usize> {
        if slot == self.attacker {
            Some(0)
        } else if slot == self.victim {
            Some(1)
        } else {
            None
        }
    }

    /// Applies a player's move. Returns whether anything changed; a move the fighter can't make
    /// right now (staggered, or already winding up) is ignored.
    pub fn play(&mut self, slot: PlayerSlot, play: MinigamePlay, now: u64) -> bool {
        let Some(i) = self.side(slot) else {
            return false;
        };
        if self.is_over() {
            return false;
        }
        let side = &mut self.sides[i];
        let busy = side.winding.is_some() || now < side.staggered_until;
        match play {
            MinigamePlay::Move(play) if !busy => {
                // Attacking lowers the guard.
                side.end_guard(now);
                side.winding = Some((play, now + u64::from(play.windup_ms())));
                true
            }
            // One guard at a time, and not while it cools down.
            MinigamePlay::Guard(true)
                if !busy && !side.guard_raised_at(now) && now >= side.guard_ready_at =>
            {
                side.guard_from = now + u64::from(GUARD_RAISE_MS);
                side.guard_until = side.guard_from + u64::from(GUARD_MS);
                side.guard_ready_at = side.guard_until + u64::from(GUARD_COOLDOWN_MS);
                true
            }
            MinigamePlay::Guard(false) if side.guard_raised_at(now) => {
                side.end_guard(now);
                true
            }
            _ => false,
        }
    }

    /// When the next windup lands, if one is under way.
    pub fn next_landing(&self) -> Option<u64> {
        if self.is_over() {
            return None;
        }
        self.sides
            .iter()
            .filter_map(|s| s.winding.map(|(_, at)| at))
            .min()
    }

    /// Lands every windup due at or before `at`. Two that land at the same moment both see
    /// the fight as it was just before. A fighter brought to no hits left loses; if both are,
    /// the victim survives it.
    pub fn land(&mut self, at: u64) {
        if self.is_over() {
            return;
        }
        let before = self.sides;
        let landing: Vec<(usize, FightMove)> = (0..2)
            .filter_map(|i| match before[i].winding {
                Some((play, due)) if due <= at => Some((i, play)),
                _ => None,
            })
            .collect();
        for (i, _) in &landing {
            self.sides[*i].winding = None;
        }
        for &(i, play) in &landing {
            let other = 1 - i;
            let guarded = before[other].guarding_at(at);
            let hit = match play {
                FightMove::Strike => !guarded,
                FightMove::Grab => guarded,
            };
            if hit {
                let target = &mut self.sides[other];
                target.hp = target.hp.saturating_sub(1);
                target.end_guard(at);
                if !landing.iter().any(|(j, _)| *j == other) {
                    // Hit mid-windup: the move never lands.
                    target.winding = None;
                }
            } else {
                self.sides[i].staggered_until = at + u64::from(STAGGER_MS);
            }
        }
        let [attacker, victim] = self.sides;
        if victim.hp == 0 && attacker.hp > 0 {
            self.attacker_won = Some(true);
        } else if attacker.hp == 0 || victim.hp == 0 {
            self.attacker_won = Some(false);
        }
    }

    /// The fight as `slot` sees it.
    pub fn view(&self, slot: PlayerSlot, now: u64) -> Option<FightView> {
        let i = self.side(slot)?;
        Some(FightView {
            you: self.sides[i].view(now),
            opponent: self.sides[1 - i].view(now),
        })
    }
}

#[cfg(test)]
mod tests {
    use webgame_protocol::{GRAB_WINDUP_MS, STRIKE_WINDUP_MS};

    use super::*;

    const A: PlayerSlot = PlayerSlot(0);
    const V: PlayerSlot = PlayerSlot(1);
    const STRIKE: MinigamePlay = MinigamePlay::Move(FightMove::Strike);
    const GRAB: MinigamePlay = MinigamePlay::Move(FightMove::Grab);

    fn run_to(duel: &mut Duel, until: u64) {
        while let Some(at) = duel.next_landing().filter(|at| *at <= until) {
            duel.land(at);
        }
    }

    fn hp(duel: &Duel) -> (u8, u8) {
        (duel.sides[0].hp, duel.sides[1].hp)
    }

    #[test]
    fn a_strike_hits_an_open_fighter_and_bounces_off_a_guard() {
        let mut duel = Duel::new(A, V);
        assert!(duel.play(A, STRIKE, 0));
        run_to(&mut duel, 2_000);
        assert_eq!(hp(&duel), (3, 2));

        duel.play(V, MinigamePlay::Guard(true), 2_000);
        duel.play(A, STRIKE, 2_000);
        run_to(&mut duel, 4_000);
        assert_eq!(hp(&duel), (3, 2));
        let staggered = duel.view(A, 2_000 + u64::from(STRIKE_WINDUP_MS)).unwrap();
        assert_eq!(staggered.you.staggered_ms, STAGGER_MS);
        // Staggered, the striker can't move or guard.
        let after = 2_000 + u64::from(STRIKE_WINDUP_MS) + 10;
        assert!(!duel.play(A, STRIKE, after));
        assert!(!duel.play(A, MinigamePlay::Guard(true), after));
    }

    #[test]
    fn a_grab_breaks_a_guard_and_misses_an_open_fighter() {
        let mut duel = Duel::new(A, V);
        // Raised late enough that it's still up when the grab lands.
        duel.play(A, GRAB, 0);
        duel.play(V, MinigamePlay::Guard(true), 600);
        run_to(&mut duel, 4_000);
        assert_eq!(hp(&duel), (3, 2));
        assert!(!duel.sides[1].guarding_at(2_600), "the guard is broken");

        duel.play(A, GRAB, 6_000);
        run_to(&mut duel, 10_000);
        assert_eq!(hp(&duel), (3, 2));
        assert!(duel.sides[0].staggered_until > 6_000 + u64::from(GRAB_WINDUP_MS));
    }

    #[test]
    fn a_guard_drops_on_its_own() {
        let mut duel = Duel::new(A, V);
        duel.play(V, MinigamePlay::Guard(true), 0);
        let up = u64::from(GUARD_RAISE_MS);
        assert_eq!(duel.view(V, up + 400).unwrap().you.guard_ms, GUARD_MS - 400);
        // Raised too early: it's down by the time the strike lands.
        duel.play(A, STRIKE, up + u64::from(GUARD_MS) - 100);
        run_to(&mut duel, 10_000);
        assert_eq!(hp(&duel), (3, 2));
    }

    #[test]
    fn a_guard_takes_time_to_come_up() {
        let mut duel = Duel::new(A, V);
        let raise = u64::from(GUARD_RAISE_MS);
        // A strike about to land when the guard is raised still hits.
        duel.play(A, STRIKE, 0);
        duel.play(
            V,
            MinigamePlay::Guard(true),
            u64::from(STRIKE_WINDUP_MS) - raise + 100,
        );
        run_to(&mut duel, 4_000);
        assert_eq!(hp(&duel), (3, 2));

        // Raised in time, it blocks.
        let mut duel = Duel::new(A, V);
        duel.play(A, STRIKE, 0);
        let raised = u64::from(STRIKE_WINDUP_MS) - raise - 100;
        duel.play(V, MinigamePlay::Guard(true), raised);
        assert_eq!(
            duel.view(V, raised + 100).unwrap().you.raising_ms,
            GUARD_RAISE_MS - 100
        );
        run_to(&mut duel, 4_000);
        assert_eq!(hp(&duel), (3, 3));
    }

    #[test]
    fn a_guard_cools_down_before_another() {
        let mut duel = Duel::new(A, V);
        let guard = MinigamePlay::Guard(true);
        assert!(duel.play(V, guard, 0));
        assert!(!duel.play(V, guard, 1_000), "one guard at a time");
        // Dropped early, the cooldown runs from then.
        assert!(duel.play(V, MinigamePlay::Guard(false), 1_000));
        let ready = 1_000 + u64::from(GUARD_COOLDOWN_MS);
        assert_eq!(
            duel.view(V, 1_000).unwrap().you.guard_cooldown_ms,
            GUARD_COOLDOWN_MS
        );
        assert!(!duel.play(V, guard, ready - 1));
        assert!(duel.play(V, guard, ready));
        // A strike started as a guard ends lands before another can come up.
        const _: () = assert!(STRIKE_WINDUP_MS <= GUARD_COOLDOWN_MS + GUARD_RAISE_MS);
    }

    #[test]
    fn a_strike_interrupts_a_slower_grab() {
        let mut duel = Duel::new(A, V);
        duel.play(A, GRAB, 0);
        // Started right away, the strike lands just before the grab.
        duel.play(V, STRIKE, 100);
        const _: () = assert!(100 + STRIKE_WINDUP_MS < GRAB_WINDUP_MS);
        run_to(&mut duel, 4_000);
        assert_eq!(hp(&duel), (2, 3), "the grab never landed");
    }

    #[test]
    fn knocking_out_the_victim_wins_and_a_double_knockout_spares_them() {
        let mut duel = Duel::new(A, V);
        for n in 0..3 {
            duel.play(A, STRIKE, n * 2_000);
            run_to(&mut duel, n * 2_000 + 1_999);
        }
        const _: () = assert!(STRIKE_WINDUP_MS < 2_000);
        assert_eq!(duel.attacker_won, Some(true));
        assert!(
            !duel.play(A, STRIKE, 10_000),
            "a finished fight takes no moves"
        );

        let mut duel = Duel::new(A, V);
        duel.sides = [
            Side {
                hp: 1,
                ..Side::new()
            },
            Side {
                hp: 1,
                ..Side::new()
            },
        ];
        duel.play(A, STRIKE, 0);
        duel.play(V, STRIKE, 0);
        run_to(&mut duel, 2_000);
        assert_eq!(duel.attacker_won, Some(false));
    }

    #[test]
    fn views_count_down_from_when_they_are_sent() {
        let mut duel = Duel::new(A, V);
        duel.play(A, GRAB, 2_000);
        let view = duel.view(V, 2_400).unwrap();
        assert_eq!(
            view.opponent.winding,
            Some((FightMove::Grab, GRAB_WINDUP_MS - 400))
        );
        assert_eq!(view.you.winding, None);
        assert_eq!(duel.view(PlayerSlot(5), 2_400), None);
    }
}
