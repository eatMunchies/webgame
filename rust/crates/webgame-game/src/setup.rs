//! Choosing a game's roles.

use rand::Rng;
use rand::seq::{IndexedRandom, SliceRandom};
use webgame_protocol::{Faction, MAX_PLAYERS, Role, RoleCategory, RoleSlot};

use crate::Player;

/// The role list for a full lobby, in the order slots are added as the lobby grows. A game with
/// n players uses the first n. The order keeps small games balanced: four players get one
/// Mafioso, two Town, and a Neutral who can't kill; the second Mafia member arrives at seven.
pub const RANKED: [RoleSlot; MAX_PLAYERS] = [
    RoleSlot::Exact(Role::Mafioso),
    RoleSlot::Category(RoleCategory::TownInvestigative),
    RoleSlot::Category(RoleCategory::TownProtective),
    RoleSlot::Category(RoleCategory::NeutralEvil),
    RoleSlot::Category(RoleCategory::TownSupport),
    RoleSlot::Category(RoleCategory::TownInvestigative),
    RoleSlot::Exact(Role::Godfather),
    RoleSlot::Exact(Role::Jailer),
    RoleSlot::Category(RoleCategory::TownKilling),
    RoleSlot::Faction(Faction::Mafia),
    RoleSlot::Category(RoleCategory::NeutralKilling),
    RoleSlot::Faction(Faction::Town),
    RoleSlot::Faction(Faction::Town),
    RoleSlot::Any,
    RoleSlot::Faction(Faction::Town),
];

/// The role list for a game of `players` players.
pub fn role_list(players: usize) -> Vec<RoleSlot> {
    RANKED[..players.min(MAX_PLAYERS)].to_vec()
}

/// Rolls a role for each slot of a list, in the list's order. Unique roles are rolled at most
/// once. Narrow slots are filled first so an `Any` can't use up a role an exact slot needs.
pub fn roll_roles(list: &[RoleSlot], rng: &mut impl Rng) -> Vec<Role> {
    let mut order: Vec<usize> = (0..list.len()).collect();
    order.sort_by_key(|&i| match list[i] {
        RoleSlot::Exact(_) => 0,
        RoleSlot::Category(_) => 1,
        RoleSlot::Faction(_) => 2,
        RoleSlot::Any => 3,
    });
    let mut rolled: Vec<Option<Role>> = vec![None; list.len()];
    for i in order {
        let taken: Vec<Role> = rolled.iter().flatten().copied().collect();
        let options: Vec<Role> = Role::ALL
            .into_iter()
            .filter(|role| list[i].allows(*role))
            .filter(|role| !(role.unique() && taken.contains(role)))
            .collect();
        // Every slot used by RANKED has non-unique roles left, so this only falls back for an
        // odd custom list.
        rolled[i] = Some(*options.choose(rng).unwrap_or(&Role::Survivor));
    }
    rolled.into_iter().map(|role| role.unwrap()).collect()
}

/// Rolls roles for the players, deals them out at random, and picks each Executioner's target.
pub fn deal(players: &mut [Player], list: &[RoleSlot], rng: &mut impl Rng) {
    let mut roles = roll_roles(list, rng);
    roles.shuffle(rng);
    for (player, role) in players.iter_mut().zip(roles) {
        player.become_role(role);
    }
    let town: Vec<_> = players
        .iter()
        .filter(|p| p.faction() == Faction::Town && p.role != Role::Jailer)
        .map(|p| p.slot)
        .collect();
    for player in players.iter_mut().filter(|p| p.role == Role::Executioner) {
        match town.choose(rng) {
            Some(target) => player.executioner_target = Some(*target),
            // No one to target, so they start out as what they'd become anyway.
            None => player.become_role(Role::Jester),
        }
    }
}

#[cfg(test)]
mod tests {
    use rand::SeedableRng;
    use rand_chacha::ChaCha8Rng;

    use super::*;

    #[test]
    fn every_size_has_a_mafia_killer_and_unique_roles_once() {
        for seed in 0..200 {
            let mut rng = ChaCha8Rng::seed_from_u64(seed);
            for players in webgame_protocol::MIN_PLAYERS..=MAX_PLAYERS {
                let roles = roll_roles(&role_list(players), &mut rng);
                assert_eq!(roles.len(), players);
                assert!(roles.contains(&Role::Mafioso));
                for role in Role::ALL.into_iter().filter(|r| r.unique()) {
                    assert!(roles.iter().filter(|r| **r == role).count() <= 1);
                }
                let town = roles
                    .iter()
                    .filter(|r| r.faction() == Faction::Town)
                    .count();
                let mafia = roles
                    .iter()
                    .filter(|r| r.faction() == Faction::Mafia)
                    .count();
                assert!(town > mafia, "{players} players: {roles:?}");
            }
        }
    }

    #[test]
    fn rolls_respect_their_slots() {
        let mut rng = ChaCha8Rng::seed_from_u64(7);
        let list = role_list(MAX_PLAYERS);
        let roles = roll_roles(&list, &mut rng);
        for (slot, role) in list.iter().zip(&roles) {
            assert!(slot.allows(*role), "{slot} rolled {role}");
        }
    }
}
