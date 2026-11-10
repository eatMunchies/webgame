use godot::classes::Time;
use godot::prelude::*;
use webgame_game::Duel;
use webgame_protocol::{FIGHT_HP, FightMove, MinigamePlay, PlayerSlot};

use crate::game_client::fighter;

/// The player's side of a practice fight.
const YOU: PlayerSlot = PlayerSlot(0);
/// The other side, played by a bot in GDScript.
const OPPONENT: PlayerSlot = PlayerSlot(1);

/// A night fight with no server, for the minigame tester. It runs the same [`Duel`] the
/// server runs, so strikes, grabs, guards and staggers play out exactly as in a real game.
///
/// Both fighters are played from here: the player through the overlay's signals and the
/// opponent by a bot. [`PracticeFight::view`] describes the fight the way
/// `GameClient.fight()` does, so it can be the overlay's `fight_source` as it is.
///
/// Time is the engine clock, so call `advance()` each frame to land moves that are due.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct PracticeFight {
    duel: Option<Duel>,
    you_attack: bool,
    /// How far `skip()` has moved the fight's clock ahead of the engine's.
    skipped_ms: u64,
}

#[godot_api]
impl PracticeFight {
    /// Starts a new fight, both fighters at full hits. `you_attack` makes the player the
    /// attacker, who has to knock the victim out; the victim wins by knocking out the attacker.
    #[func]
    fn start(&mut self, you_attack: bool) {
        self.you_attack = you_attack;
        self.duel = Some(if you_attack {
            Duel::new(YOU, OPPONENT)
        } else {
            Duel::new(OPPONENT, YOU)
        });
    }

    /// Plays `action` for one fighter: the player when `you` is true, else the opponent.
    /// `action` is "strike", "grab", "guard" or "unguard". Returns whether it did anything;
    /// a move made while busy (winding up or staggered) is ignored, as on the server.
    #[func]
    fn play(&mut self, you: bool, action: GString) -> bool {
        let play = match action.to_string().as_str() {
            "strike" => MinigamePlay::Move(FightMove::Strike),
            "grab" => MinigamePlay::Move(FightMove::Grab),
            "guard" => MinigamePlay::Guard(true),
            "unguard" => MinigamePlay::Guard(false),
            other => {
                godot_error!("PracticeFight: no fight action called {other:?}");
                return false;
            }
        };
        let slot = if you { YOU } else { OPPONENT };
        let now = self.now();
        self.duel
            .as_mut()
            .is_some_and(|duel| duel.play(slot, play, now))
    }

    /// Lands every move that is due by now, in the order they come due.
    #[func]
    fn advance(&mut self) {
        let now = self.now();
        let Some(duel) = self.duel.as_mut() else {
            return;
        };
        while let Some(at) = duel.next_landing().filter(|at| *at <= now) {
            duel.land(at);
        }
    }

    /// The fight as the player sees it, in the format of `GameClient.fight()`: `you` and
    /// `opponent`, each as `GameClient.fight()` describes, and `max_hp`. Empty before `start()`.
    #[func]
    fn view(&self) -> VarDictionary {
        let Some(view) = self
            .duel
            .as_ref()
            .and_then(|duel| duel.view(YOU, self.now()))
        else {
            return VarDictionary::new();
        };
        vdict! {
            "you" => &fighter(&view.you, 0),
            "opponent" => &fighter(&view.opponent, 0),
            "max_hp" => i64::from(FIGHT_HP),
        }
    }

    /// Who won: "you", "opponent", or "" while it goes on.
    #[func]
    fn winner(&self) -> GString {
        let won = self.duel.as_ref().and_then(|duel| duel.attacker_won);
        GString::from(match won {
            None => "",
            Some(attacker_won) if attacker_won == self.you_attack => "you",
            Some(_) => "opponent",
        })
    }

    /// Moves the fight's clock `ms` ahead without waiting, so tests needn't sleep. Call
    /// `advance()` after it to land what came due.
    #[func]
    fn skip(&mut self, ms: i64) {
        self.skipped_ms += u64::try_from(ms).unwrap_or(0);
    }

    /// The fight's clock: the engine's, plus whatever `skip()` added.
    fn now(&self) -> u64 {
        Time::singleton().get_ticks_msec() + self.skipped_ms
    }

    /// Ends the fight for the victim, as the server does when a round has run on to its cap.
    #[func]
    fn time_up(&mut self) {
        if let Some(duel) = self.duel.as_mut() {
            duel.finish(false);
        }
    }
}
