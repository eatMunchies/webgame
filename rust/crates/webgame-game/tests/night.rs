//! One test per role interaction in the night calculator.

use std::collections::BTreeMap;

use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;
use webgame_game::Player;
use webgame_game::night::{
    Fight, Jail, NightOutcome, NightPlan, Results, SkillCheck, Stage, plan, resolve,
};
use webgame_protocol::{
    DeathCause, NightAction, Notice, PlayerSlot, Power, Role, SaveReason, UserId,
};

fn players(roles: &[Role]) -> Vec<Player> {
    roles
        .iter()
        .enumerate()
        .map(|(i, role)| Player::new(slot(i as u8), UserId(i as u64), format!("P{i}"), *role))
        .collect()
}

fn slot(n: u8) -> PlayerSlot {
    PlayerSlot(n)
}

fn target(n: u8) -> NightAction {
    NightAction::Target(slot(n))
}

fn run(
    players: &mut [Player],
    actions: &[(u8, NightAction)],
    night: u32,
    jail: Option<(u8, u8)>,
) -> NightOutcome {
    run_with(players, actions, night, jail, &Results::default())
}

fn actions(actions: &[(u8, NightAction)]) -> BTreeMap<PlayerSlot, NightAction> {
    actions
        .iter()
        .map(|(actor, action)| (slot(*actor), *action))
        .collect()
}

fn jail(jail: Option<(u8, u8)>) -> Option<Jail> {
    jail.map(|(jailer, prisoner)| Jail {
        jailer: slot(jailer),
        prisoner: slot(prisoner),
    })
}

fn run_with(
    players: &mut [Player],
    actions_: &[(u8, NightAction)],
    night: u32,
    jail_: Option<(u8, u8)>,
    results: &Results,
) -> NightOutcome {
    resolve(
        players,
        &actions(actions_),
        night,
        jail(jail_),
        results,
        &mut ChaCha8Rng::seed_from_u64(1),
    )
}

fn plan_for(
    players: &[Player],
    actions_: &[(u8, NightAction)],
    night: u32,
    jail_: Option<(u8, u8)>,
    results: &Results,
) -> NightPlan {
    plan(players, &actions(actions_), night, jail(jail_), results)
}

/// Results where these players failed their skill checks.
fn failed(players: &[u8]) -> Results {
    let mut results = Results::default();
    for player in players {
        results.check(slot(*player), false);
    }
    results
}

fn check(player: u8, stage: Stage) -> SkillCheck {
    SkillCheck {
        player: slot(player),
        stage,
    }
}

fn died(outcome: &NightOutcome) -> Vec<u8> {
    outcome.deaths.keys().map(|s| s.0).collect()
}

fn notices(outcome: &NightOutcome, n: u8) -> Vec<Notice> {
    outcome.notices.get(&slot(n)).cloned().unwrap_or_default()
}

#[test]
fn mafioso_kills_an_unprotected_target() {
    let mut game = players(&[Role::Mafioso, Role::Sheriff, Role::Doctor]);
    let outcome = run(&mut game, &[(0, target(1))], 1, None);
    assert_eq!(outcome.deaths[&slot(1)], vec![DeathCause::Mafia]);
}

#[test]
fn doctor_saves_the_mafia_target() {
    let mut game = players(&[Role::Mafioso, Role::Sheriff, Role::Doctor]);
    let outcome = run(&mut game, &[(0, target(1)), (2, target(1))], 1, None);
    assert!(outcome.deaths.is_empty());
    assert_eq!(
        notices(&outcome, 1),
        vec![Notice::Attacked {
            saved: SaveReason::Healed
        }]
    );
    assert_eq!(
        notices(&outcome, 2),
        vec![Notice::TargetAttacked { target: slot(1) }]
    );
}

#[test]
fn doctor_self_heal_is_limited() {
    let mut game = players(&[Role::Mafioso, Role::Doctor]);
    run(&mut game, &[(1, target(1))], 1, None);
    assert_eq!(game[1].uses, 0);
}

#[test]
fn bodyguard_trades_with_the_attacker() {
    let mut game = players(&[Role::Mafioso, Role::Sheriff, Role::Bodyguard]);
    let outcome = run(&mut game, &[(0, target(1)), (2, target(1))], 1, None);
    assert_eq!(died(&outcome), vec![0, 2]);
    assert_eq!(outcome.deaths[&slot(0)], vec![DeathCause::Bodyguard]);
    assert_eq!(
        notices(&outcome, 1),
        vec![Notice::Attacked {
            saved: SaveReason::Guarded
        }]
    );
}

#[test]
fn mafioso_carries_out_the_godfathers_choice() {
    let mut game = players(&[
        Role::Godfather,
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Lookout,
    ]);
    let outcome = run(
        &mut game,
        &[(0, target(2)), (1, target(3)), (4, target(2))],
        1,
        None,
    );
    assert_eq!(died(&outcome), vec![2]);
    // The Mafioso went; the Godfather stayed home.
    assert_eq!(
        notices(&outcome, 4),
        vec![Notice::LookoutResult {
            target: slot(2),
            visitors: vec![slot(1)]
        }]
    );
}

#[test]
fn godfather_goes_himself_when_the_mafioso_is_blocked() {
    let mut game = players(&[Role::Godfather, Role::Mafioso, Role::Sheriff, Role::Barkeep]);
    let outcome = run(
        &mut game,
        &[(0, target(2)), (1, target(2)), (3, target(1))],
        1,
        None,
    );
    assert_eq!(died(&outcome), vec![2]);
    assert_eq!(notices(&outcome, 1), vec![Notice::Roleblocked]);
    assert!(outcome.visits.contains(&(slot(0), slot(2))));
}

#[test]
fn godfather_survives_a_vigilante() {
    let mut game = players(&[Role::Godfather, Role::Vigilante]);
    let outcome = run(&mut game, &[(1, target(0))], 2, None);
    assert!(outcome.deaths.is_empty());
    assert_eq!(
        notices(&outcome, 0),
        vec![Notice::Attacked {
            saved: SaveReason::Defense
        }]
    );
    assert_eq!(game[1].uses, 2);
}

#[test]
fn veteran_on_alert_shoots_every_visitor() {
    let mut game = players(&[Role::Veteran, Role::Escort, Role::Doctor, Role::Mafioso]);
    let outcome = run(
        &mut game,
        &[
            (0, NightAction::Activate),
            (1, target(0)),
            (2, target(0)),
            (3, target(0)),
        ],
        1,
        None,
    );
    // The escort and doctor die, the Mafioso's basic attack can't beat an alert, and the
    // Mafioso dies to the Veteran too.
    assert_eq!(died(&outcome), vec![1, 2, 3]);
    assert!(notices(&outcome, 0).contains(&Notice::RoleblockImmune));
    assert!(notices(&outcome, 0).contains(&Notice::ShotVisitor));
    assert_eq!(game[0].uses, 2);
}

#[test]
fn serial_killer_kills_whoever_roleblocks_him() {
    let mut game = players(&[Role::SerialKiller, Role::Barkeep, Role::Sheriff]);
    let outcome = run(&mut game, &[(0, target(2)), (1, target(0))], 1, None);
    assert_eq!(died(&outcome), vec![1]);
    assert_eq!(outcome.deaths[&slot(1)], vec![DeathCause::SerialKiller]);
}

#[test]
fn jail_cancels_the_prisoners_action_and_protects_them() {
    let mut game = players(&[
        Role::Jailer,
        Role::Mafioso,
        Role::Sheriff,
        Role::SerialKiller,
    ]);
    let outcome = run(
        &mut game,
        &[(1, target(2)), (3, target(1))],
        2,
        Some((0, 1)),
    );
    assert!(outcome.deaths.is_empty());
    assert_eq!(
        notices(&outcome, 1),
        vec![Notice::Attacked {
            saved: SaveReason::Jailed
        }]
    );
}

#[test]
fn jailer_execution_is_unstoppable_and_costs_executions_on_town() {
    let mut game = players(&[Role::Jailer, Role::Doctor, Role::Doctor]);
    let outcome = run(
        &mut game,
        &[(0, NightAction::Activate), (2, target(1))],
        2,
        Some((0, 1)),
    );
    assert_eq!(outcome.deaths[&slot(1)], vec![DeathCause::Jailer]);
    assert_eq!(game[0].uses, 0);
    assert!(notices(&outcome, 0).contains(&Notice::LostExecutions));
}

#[test]
fn a_jailed_serial_killer_who_is_spared_kills_the_jailer() {
    let mut game = players(&[Role::Jailer, Role::SerialKiller]);
    let outcome = run(&mut game, &[], 1, Some((0, 1)));
    assert_eq!(outcome.deaths[&slot(0)], vec![DeathCause::SerialKiller]);
}

#[test]
fn sheriff_and_the_disguiser() {
    let mut game = players(&[
        Role::Sheriff,
        Role::Godfather,
        Role::Mafioso,
        Role::Disguiser,
        Role::Doctor,
        Role::Consigliere,
    ]);
    let outcome = run(&mut game, &[(0, target(1))], 1, None);
    assert_eq!(
        notices(&outcome, 0),
        vec![Notice::SheriffResult {
            target: slot(1),
            suspicious: false
        }]
    );

    let outcome = run(&mut game, &[(0, target(2))], 1, None);
    assert_eq!(
        notices(&outcome, 0),
        vec![Notice::SheriffResult {
            target: slot(2),
            suspicious: true
        }]
    );

    // The Disguiser swaps looks with the Doctor: a Sheriff on the Disguiser sees a Doctor, and
    // a Consigliere on the Doctor sees a Disguiser.
    let outcome = run(
        &mut game,
        &[(3, target(4)), (0, target(3)), (5, target(4))],
        1,
        None,
    );
    assert_eq!(
        notices(&outcome, 0),
        vec![Notice::SheriffResult {
            target: slot(3),
            suspicious: false
        }]
    );
    assert_eq!(
        notices(&outcome, 5),
        vec![Notice::ConsigliereResult {
            target: slot(4),
            role: Role::Disguiser
        }]
    );
}

#[test]
fn investigator_sees_a_group_with_the_real_role() {
    let mut game = players(&[Role::Investigator, Role::Arsonist]);
    let outcome = run(&mut game, &[(0, target(1))], 1, None);
    let result = notices(&outcome, 0);
    let [Notice::InvestigatorResult { roles, .. }] = result.as_slice() else {
        panic!("expected one result");
    };
    assert!(roles.contains(&Role::Arsonist) && roles.len() > 1);
}

#[test]
fn lookout_and_tracker_see_visits() {
    let mut game = players(&[
        Role::Lookout,
        Role::Tracker,
        Role::Mafioso,
        Role::Doctor,
        Role::Sheriff,
    ]);
    let outcome = run(
        &mut game,
        &[
            (0, target(4)),
            (1, target(2)),
            (2, target(4)),
            (3, target(4)),
        ],
        1,
        None,
    );
    assert!(outcome.deaths.is_empty());
    assert!(notices(&outcome, 0).contains(&Notice::LookoutResult {
        target: slot(4),
        visitors: vec![slot(2), slot(3)]
    }));
    assert!(notices(&outcome, 1).contains(&Notice::TrackerResult {
        target: slot(2),
        visited: vec![slot(4)]
    }));
}

#[test]
fn spy_hears_mafia_visits_and_the_bugged_house() {
    let mut game = players(&[Role::Spy, Role::Mafioso, Role::Sheriff, Role::Doctor]);
    let outcome = run(
        &mut game,
        &[(0, target(2)), (1, target(2)), (3, target(2))],
        1,
        None,
    );
    assert_eq!(
        notices(&outcome, 0),
        vec![
            Notice::SpyMafiaVisits {
                targets: vec![slot(2)]
            },
            Notice::SpyBug {
                target: slot(2),
                heard: vec![Notice::Attacked {
                    saved: SaveReason::Healed
                }]
            },
        ]
    );
}

#[test]
fn copycat_copies_an_ability_onto_a_second_target() {
    let mut game = players(&[
        Role::Copycat,
        Role::Doctor,
        Role::Sheriff,
        Role::Mafioso,
        Role::Veteran,
    ]);
    // Copy the Sheriff's interrogation onto the Mafioso.
    let outcome = run(
        &mut game,
        &[(0, NightAction::TwoTargets(slot(2), slot(3)))],
        1,
        None,
    );
    assert!(notices(&outcome, 0).contains(&Notice::CopycatLearned {
        target: slot(2),
        role: Role::Sheriff,
        copied: true
    }));
    assert!(notices(&outcome, 0).contains(&Notice::SheriffResult {
        target: slot(3),
        suspicious: true
    }));

    // A copied heal saves the second target.
    let outcome = run(
        &mut game,
        &[
            (0, NightAction::TwoTargets(slot(1), slot(2))),
            (3, target(2)),
        ],
        1,
        None,
    );
    assert!(outcome.deaths.is_empty());

    // An alert has no target, so it can't be copied; the Copycat still learns the role.
    let outcome = run(
        &mut game,
        &[(0, NightAction::TwoTargets(slot(4), slot(2)))],
        1,
        None,
    );
    assert_eq!(
        notices(&outcome, 0),
        vec![Notice::CopycatLearned {
            target: slot(4),
            role: Role::Veteran,
            copied: false
        }]
    );
}

#[test]
fn copied_kills_count_as_mafia_kills() {
    let mut game = players(&[Role::Copycat, Role::Vigilante, Role::Sheriff]);
    let outcome = run(
        &mut game,
        &[(0, NightAction::TwoTargets(slot(1), slot(2)))],
        1,
        None,
    );
    assert_eq!(outcome.deaths[&slot(2)], vec![DeathCause::Mafia]);
    // The Vigilante's bullets are untouched.
    assert_eq!(game[1].uses, 3);
}

#[test]
fn poison_kills_the_next_night_unless_healed() {
    let mut game = players(&[Role::Poisoner, Role::Sheriff, Role::Doctor]);
    let outcome = run(&mut game, &[(0, target(1))], 1, None);
    assert!(outcome.deaths.is_empty());
    assert_eq!(notices(&outcome, 1), vec![Notice::Poisoned]);
    let outcome = run(&mut game, &[], 2, None);
    assert_eq!(outcome.deaths[&slot(1)], vec![DeathCause::Poison]);

    let mut game = players(&[Role::Poisoner, Role::Sheriff, Role::Doctor]);
    run(&mut game, &[(0, target(1))], 1, None);
    let outcome = run(&mut game, &[(2, target(1))], 2, None);
    assert!(outcome.deaths.is_empty());

    // Healed on the night of the poisoning: cured straight away.
    let mut game = players(&[Role::Poisoner, Role::Sheriff, Role::Doctor]);
    let outcome = run(&mut game, &[(0, target(1)), (2, target(1))], 1, None);
    assert_eq!(notices(&outcome, 1), vec![Notice::PoisonCured]);
    assert_eq!(game[1].poison, None);
}

#[test]
fn arsonist_ignites_everyone_doused_through_heals() {
    let mut game = players(&[Role::Arsonist, Role::Sheriff, Role::Doctor, Role::Lookout]);
    run(&mut game, &[(0, target(1))], 1, None);
    run(&mut game, &[(0, target(3))], 2, None);
    let outcome = run(
        &mut game,
        &[(0, NightAction::Activate), (2, target(1))],
        3,
        None,
    );
    assert_eq!(died(&outcome), vec![1, 3]);
    assert!(game.iter().all(|p| !p.doused));
}

#[test]
fn vigilante_who_shoots_town_dies_of_guilt_the_next_night() {
    let mut game = players(&[Role::Vigilante, Role::Sheriff]);
    let outcome = run(&mut game, &[(0, target(1))], 2, None);
    assert_eq!(died(&outcome), vec![1]);
    game[1].alive = false;
    let outcome = run(&mut game, &[], 3, None);
    assert_eq!(outcome.deaths[&slot(0)], vec![DeathCause::Guilt]);
}

#[test]
fn trap_stops_an_attacker_and_hits_back() {
    let mut game = players(&[Role::Trapper, Role::Sheriff, Role::Mafioso]);
    let outcome = run(&mut game, &[(0, target(1))], 1, None);
    assert!(outcome.deaths.is_empty());
    assert_eq!(game[0].trap, Some(slot(1)));
    // The trap stays set until it goes off.
    let outcome = run(&mut game, &[(2, target(1))], 2, None);
    assert_eq!(died(&outcome), vec![2]);
    assert_eq!(outcome.deaths[&slot(2)], vec![DeathCause::Trap]);
    assert!(notices(&outcome, 0).contains(&Notice::TrapTriggered { target: slot(1) }));
    assert_eq!(game[0].trap, None);
}

#[test]
fn ambusher_attacks_a_visitor_and_is_seen() {
    let mut game = players(&[Role::Ambusher, Role::Sheriff, Role::Doctor]);
    let outcome = run(&mut game, &[(0, target(1)), (2, target(1))], 1, None);
    assert_eq!(died(&outcome), vec![2]);
    assert!(notices(&outcome, 2).contains(&Notice::SawAmbusher { ambusher: slot(0) }));
}

#[test]
fn survivor_vests_block_basic_attacks() {
    let mut game = players(&[Role::Survivor, Role::Mafioso]);
    let outcome = run(
        &mut game,
        &[(0, NightAction::Activate), (1, target(0))],
        1,
        None,
    );
    assert!(outcome.deaths.is_empty());
    assert_eq!(game[0].uses, 3);
}

#[test]
fn amnesiac_remembers_a_dead_role() {
    let mut game = players(&[Role::Amnesiac, Role::Sheriff, Role::Godfather]);
    game[2].alive = false;
    let outcome = run(&mut game, &[(0, target(2))], 2, None);
    assert_eq!(outcome.remembered, vec![(slot(0), Role::Godfather)]);
    assert_eq!(game[0].role, Role::Godfather);
}

#[test]
fn escort_blocks_town_but_not_the_immune() {
    let mut game = players(&[Role::Escort, Role::Sheriff, Role::Barkeep, Role::Mafioso]);
    let outcome = run(&mut game, &[(0, target(1)), (1, target(3))], 1, None);
    assert_eq!(notices(&outcome, 1), vec![Notice::Roleblocked]);
    let outcome = run(&mut game, &[(0, target(2)), (2, target(3))], 1, None);
    assert_eq!(notices(&outcome, 2), vec![Notice::RoleblockImmune]);
    // The Barkeep's own block still lands on the Mafioso.
    assert_eq!(notices(&outcome, 3), vec![Notice::Roleblocked]);
}

// ----- Minigames -----

#[test]
fn a_failed_heal_still_visits_but_saves_nobody() {
    let mut game = players(&[Role::Mafioso, Role::Sheriff, Role::Doctor, Role::Lookout]);
    let outcome = run_with(
        &mut game,
        &[(0, target(1)), (2, target(1)), (3, target(1))],
        1,
        None,
        &failed(&[2]),
    );
    assert_eq!(died(&outcome), vec![1]);
    assert_eq!(
        notices(&outcome, 3),
        vec![Notice::LookoutResult {
            target: slot(1),
            visitors: vec![slot(0), slot(2)]
        }]
    );
    assert!(notices(&outcome, 2).is_empty());
}

#[test]
fn a_failed_visit_still_meets_an_alert_veteran() {
    let mut game = players(&[Role::Veteran, Role::Sheriff]);
    let outcome = run_with(
        &mut game,
        &[(0, NightAction::Activate), (1, target(0))],
        1,
        None,
        &failed(&[1]),
    );
    assert_eq!(outcome.deaths[&slot(1)], vec![DeathCause::Veteran]);
    assert!(notices(&outcome, 1).is_empty());
}

#[test]
fn a_failed_alert_shoots_nobody_and_keeps_its_use() {
    let mut game = players(&[Role::Veteran, Role::Sheriff]);
    let outcome = run_with(
        &mut game,
        &[(0, NightAction::Activate), (1, target(0))],
        1,
        None,
        &failed(&[0]),
    );
    assert!(outcome.deaths.is_empty());
    assert_eq!(game[0].uses, 3);
}

#[test]
fn a_failed_roleblock_blocks_nobody() {
    let mut game = players(&[Role::Escort, Role::Mafioso, Role::Sheriff]);
    let outcome = run_with(
        &mut game,
        &[(0, target(1)), (1, target(2))],
        1,
        None,
        &failed(&[0]),
    );
    assert_eq!(died(&outcome), vec![2]);
    assert!(notices(&outcome, 1).is_empty());
}

#[test]
fn a_failed_execution_spares_the_prisoner_and_keeps_its_use() {
    let mut game = players(&[Role::Jailer, Role::Doctor]);
    let outcome = run_with(
        &mut game,
        &[(0, NightAction::Activate)],
        2,
        Some((0, 1)),
        &failed(&[0]),
    );
    assert!(outcome.deaths.is_empty());
    assert_eq!(game[0].uses, 3);

    // A Serial Killer who survives his execution attacks the Jailer, as if spared.
    let mut game = players(&[Role::Jailer, Role::SerialKiller]);
    let outcome = run_with(
        &mut game,
        &[(0, NightAction::Activate)],
        2,
        Some((0, 1)),
        &failed(&[0]),
    );
    assert_eq!(outcome.deaths[&slot(0)], vec![DeathCause::SerialKiller]);
}

#[test]
fn a_failed_ignite_leaves_the_douses() {
    let mut game = players(&[Role::Arsonist, Role::Sheriff]);
    run(&mut game, &[(0, target(1))], 1, None);
    let outcome = run_with(
        &mut game,
        &[(0, NightAction::Activate)],
        2,
        None,
        &failed(&[0]),
    );
    assert!(outcome.deaths.is_empty());
    assert!(game[1].doused);
}

#[test]
fn a_lost_fight_never_reaches_the_victim() {
    let mut game = players(&[Role::Vigilante, Role::Mafioso, Role::Bodyguard]);
    let mut results = Results::default();
    results.fight(slot(0), slot(1), false);
    let outcome = run_with(
        &mut game,
        &[(0, target(1)), (2, target(1))],
        2,
        None,
        &results,
    );
    // The Bodyguard had nothing to step in front of.
    assert!(outcome.deaths.is_empty());
    assert!(notices(&outcome, 1).is_empty());
    // The shot was still fired.
    assert_eq!(game[0].uses, 2);
}

#[test]
fn a_won_fight_still_has_to_beat_defense() {
    let mut game = players(&[Role::Vigilante, Role::Godfather]);
    let mut results = Results::default();
    results.fight(slot(0), slot(1), true);
    let outcome = run_with(&mut game, &[(0, target(1))], 2, None, &results);
    assert!(outcome.deaths.is_empty());
    assert_eq!(
        notices(&outcome, 1),
        vec![Notice::Attacked {
            saved: SaveReason::Defense
        }]
    );
}

#[test]
fn the_plan_gives_checks_by_stage_and_fights_for_attacks() {
    let game = players(&[
        Role::Mafioso,
        Role::Sheriff,
        Role::Doctor,
        Role::Escort,
        Role::Lookout,
    ]);
    let actions = [
        (0, target(1)),
        (1, target(0)),
        (2, target(1)),
        (3, target(4)),
        (4, target(1)),
    ];
    let night = plan_for(&game, &actions, 1, None, &Results::default());
    // Nothing is reported yet, so the Escort's block hasn't happened and the Lookout plays.
    assert_eq!(
        night.checks,
        vec![
            check(1, Stage::Investigate),
            check(2, Stage::Protect),
            check(3, Stage::Roleblock),
            check(4, Stage::Investigate),
        ]
    );
    assert_eq!(
        night.fights,
        vec![Fight {
            attacker: slot(0),
            victim: slot(1),
            stage: Stage::Kill,
            power: Power::Basic,
            defense: Power::None,
        }]
    );

    // Once the block and the heal pass, the Lookout has nothing to do and the heal shows.
    let mut results = Results::default();
    results.check(slot(3), true);
    results.check(slot(2), true);
    let night = plan_for(&game, &actions, 1, None, &results);
    assert!(!night.checks.contains(&check(4, Stage::Investigate)));
    assert_eq!(night.fights[0].defense, Power::Powerful);
    assert_eq!(
        night.stage(Stage::Roleblock).0,
        vec![check(3, Stage::Roleblock)]
    );
}

#[test]
fn a_blocked_serial_killer_fights_the_roleblocker() {
    let game = players(&[Role::SerialKiller, Role::Barkeep, Role::Sheriff]);
    let actions = [(0, target(2)), (1, target(0))];
    let before = plan_for(&game, &actions, 1, None, &Results::default());
    assert_eq!(before.fights[0].victim, slot(2));
    let mut results = Results::default();
    results.check(slot(1), true);
    let night = plan_for(&game, &actions, 1, None, &results);
    assert_eq!(night.fights.len(), 1);
    assert_eq!(night.fights[0].victim, slot(1));
}

#[test]
fn jailed_and_blocked_players_play_nothing() {
    let game = players(&[Role::Jailer, Role::Doctor, Role::Escort, Role::Sheriff]);
    let mut results = Results::default();
    results.check(slot(2), true);
    let night = plan_for(
        &game,
        &[(1, target(3)), (2, target(3)), (3, target(1))],
        2,
        Some((0, 1)),
        &results,
    );
    assert_eq!(night.checks, vec![check(2, Stage::Roleblock)]);
    assert!(night.fights.is_empty());
}

#[test]
fn executions_and_ignitions_are_checks_and_haunts_are_fights() {
    let game = players(&[Role::Jailer, Role::Sheriff]);
    let night = plan_for(
        &game,
        &[(0, NightAction::Activate)],
        2,
        Some((0, 1)),
        &Results::default(),
    );
    assert_eq!(night.checks, vec![check(0, Stage::Kill)]);
    assert!(night.fights.is_empty());

    let game = players(&[Role::Arsonist, Role::Sheriff]);
    let night = plan_for(
        &game,
        &[(0, NightAction::Activate)],
        2,
        None,
        &Results::default(),
    );
    assert_eq!(night.checks, vec![check(0, Stage::Kill)]);

    let mut game = players(&[Role::Jester, Role::Sheriff]);
    game[0].alive = false;
    game[0].won = true;
    let night = plan_for(&game, &[(0, target(1))], 2, None, &Results::default());
    assert!(night.checks.is_empty());
    assert_eq!(
        night.fights,
        vec![Fight {
            attacker: slot(0),
            victim: slot(1),
            stage: Stage::Kill,
            power: Power::Unstoppable,
            defense: Power::None,
        }]
    );
}

#[test]
fn planning_changes_nothing() {
    let game = players(&[Role::Vigilante, Role::Doctor, Role::Trapper]);
    plan_for(
        &game,
        &[(0, target(1)), (1, target(1)), (2, target(1))],
        2,
        None,
        &Results::default(),
    );
    assert_eq!(game[0].uses, 3);
    assert_eq!(game[1].uses, 1);
    assert_eq!(game[2].trap, None);
}
