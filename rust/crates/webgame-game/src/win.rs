//! Deciding when a game is over and who won.

use webgame_protocol::{Faction, GameOverInfo, Outcome, Role};

use crate::Player;

/// A game ends in a draw after this many days and nights in a row in which nobody died.
pub const DRAW_AFTER_QUIET_CYCLES: u32 = 3;

/// Checks whether the game is over, given who is alive now and how many day and night cycles
/// in a row passed without a death. Returns the result if it is.
///
/// The game goes on while two sides that kill are both alive. It ends when:
/// - only one killing side is left and nobody can stop it: the Mafia once there is no Town or
///   the Mafia can't be outvoted, a lone Neutral Killer once it can't be outvoted;
/// - or no killers are left at all, which is a Town win if any Town survive.
pub fn check(players: &[Player], quiet_cycles: u32) -> Option<GameOverInfo> {
    let alive: Vec<&Player> = players.iter().filter(|p| p.alive).collect();
    let town = alive
        .iter()
        .filter(|p| p.faction() == Faction::Town)
        .count();
    let mafia = alive.iter().filter(|p| p.is_mafia()).count();
    let killers: Vec<Role> = alive
        .iter()
        .filter(|p| p.role.is_neutral_killing())
        .map(|p| p.role)
        .collect();

    let outcome = if alive.is_empty() {
        Outcome::Draw
    } else if mafia == 0 && killers.is_empty() {
        if town > 0 {
            Outcome::Town
        } else {
            Outcome::Draw
        }
    } else if killers.is_empty() && (town == 0 || mafia * 2 >= alive.len()) {
        Outcome::Mafia
    } else if mafia == 0 && killers.len() == 1 && (town == 0 || alive.len() <= 2) {
        Outcome::Solo(killers[0])
    } else if quiet_cycles >= DRAW_AFTER_QUIET_CYCLES {
        Outcome::Draw
    } else {
        return None;
    };

    let winners = players
        .iter()
        .filter(|p| {
            let side_won = match outcome {
                Outcome::Town => p.faction() == Faction::Town,
                Outcome::Mafia => p.is_mafia(),
                Outcome::Solo(_) => p.alive && p.role.is_neutral_killing(),
                Outcome::Draw => false,
            };
            side_won || p.won || (p.alive && p.role == Role::Survivor)
        })
        .map(|p| p.slot)
        .collect();
    Some(GameOverInfo {
        outcome,
        winners,
        roles: players.iter().map(|p| (p.slot, p.role)).collect(),
    })
}

#[cfg(test)]
mod tests {
    use webgame_protocol::{PlayerSlot, UserId};

    use super::*;

    fn players(roles: &[(Role, bool)]) -> Vec<Player> {
        roles
            .iter()
            .enumerate()
            .map(|(i, (role, alive))| {
                let mut p = Player::new(
                    PlayerSlot(i as u8),
                    UserId(i as u64),
                    format!("P{i}"),
                    *role,
                );
                p.alive = *alive;
                p
            })
            .collect()
    }

    #[test]
    fn going_on_while_sides_remain() {
        let game = players(&[
            (Role::Mafioso, true),
            (Role::Doctor, true),
            (Role::Sheriff, true),
        ]);
        assert_eq!(check(&game, 0), None);
    }

    #[test]
    fn town_wins_when_the_killers_are_gone() {
        let game = players(&[
            (Role::Mafioso, false),
            (Role::Doctor, true),
            (Role::Jester, true),
            (Role::Survivor, true),
        ]);
        let result = check(&game, 0).unwrap();
        assert_eq!(result.outcome, Outcome::Town);
        // The Survivor wins too, the Jester doesn't.
        assert_eq!(result.winners, vec![PlayerSlot(1), PlayerSlot(3)]);
    }

    #[test]
    fn mafia_wins_when_it_cant_be_outvoted() {
        let game = players(&[
            (Role::Mafioso, true),
            (Role::Doctor, true),
            (Role::Sheriff, false),
        ]);
        assert_eq!(check(&game, 0).unwrap().outcome, Outcome::Mafia);
    }

    #[test]
    fn a_lone_killer_wins_a_duel() {
        let game = players(&[
            (Role::SerialKiller, true),
            (Role::Doctor, true),
            (Role::Mafioso, false),
        ]);
        assert_eq!(
            check(&game, 0).unwrap().outcome,
            Outcome::Solo(Role::SerialKiller)
        );
    }

    #[test]
    fn a_lynched_jester_wins_with_anyone() {
        let mut game = players(&[
            (Role::Mafioso, true),
            (Role::Jester, false),
            (Role::Doctor, false),
        ]);
        game[1].won = true;
        let result = check(&game, 0).unwrap();
        assert_eq!(result.outcome, Outcome::Mafia);
        assert_eq!(result.winners, vec![PlayerSlot(0), PlayerSlot(1)]);
    }

    #[test]
    fn quiet_games_end_in_a_draw() {
        let game = players(&[
            (Role::Mafioso, true),
            (Role::SerialKiller, true),
            (Role::Doctor, true),
        ]);
        assert_eq!(check(&game, 2), None);
        assert_eq!(check(&game, 3).unwrap().outcome, Outcome::Draw);
    }
}
