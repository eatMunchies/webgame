//! The night calculator: works out what happens when everyone's night actions meet.
//!
//! [`resolve`] runs in fixed passes, each reading what earlier passes decided:
//!
//! 1. **Jail.** The prisoner can't act. A Serial Killer left alive in jail attacks the Jailer.
//! 2. **Roleblocks.** Barkeeps and Escorts stop their target acting, unless the target is
//!    immune. A Serial Killer who is roleblocked attacks the roleblocker instead.
//! 3. **Visits.** Every action still going ahead visits its target's house. The Mafia's kill is
//!    carried out by the Mafioso, or by the Godfather when the Mafioso can't.
//! 4. **Self effects and disguises.** Alerts, vests, and the Disguiser's swap.
//! 5. **Protection.** Heals, guards, and traps are put in place.
//! 6. **Attacks.** Each attack is checked against the target's defense. A bodyguard or a trap
//!    stops a direct attack and attacks the attacker back. Poison and douses are applied.
//! 7. **Investigations.** Sheriff, Investigator, Consigliere, Lookout, Tracker and Spy results
//!    are read from the final visits and appearances.
//! 8. **Remembering.** An Amnesiac who survived takes their dead target's role.
//!
//! Everyone acts at the same time, so a player killed tonight still carries out their own
//! action. Deaths are returned, not applied: the caller marks the dead and reveals their wills.
//!
//! # Minigames
//!
//! Each action that goes ahead is played out as a minigame during the night, in [`STAGES`]
//! order. Direct attacks (the Mafia's kill, a Serial Killer, a Vigilante, a Jester's haunt) are
//! a [`Fight`] between attacker and victim; every other action, Jailer executions and Arsonist
//! ignitions included, is a one-player [`SkillCheck`]. [`plan`] says who plays what, and
//! [`resolve`] takes the [`Results`]:
//!
//! - A failed skill check still visits, so Lookouts see it and Veterans shoot it, but the
//!   action does nothing and spends no uses.
//! - A lost fight means the attack never reaches the victim. A won one only gets it there:
//!   the victim's defense, heals, guards and traps still apply.
//!
//! Results nobody reported count as a pass or a win, so a night with no minigames resolves as
//! if everyone succeeded.

use std::collections::{BTreeMap, BTreeSet, VecDeque};

use rand::seq::IndexedRandom;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use webgame_protocol::{
    DeathCause, Faction, NightAction, Notice, PlayerSlot, Power, Role, SaveReason,
};

use crate::Player;

/// Tonight's jailing, if the Jailer jailed someone.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Jail {
    pub jailer: PlayerSlot,
    pub prisoner: PlayerSlot,
}

/// What happened in a night.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct NightOutcome {
    /// Who died, and what killed them (several things can).
    pub deaths: BTreeMap<PlayerSlot, Vec<DeathCause>>,
    /// What each player learns at dawn.
    pub notices: BTreeMap<PlayerSlot, Vec<Notice>>,
    /// Every visit made, as (visitor, house).
    pub visits: Vec<(PlayerSlot, PlayerSlot)>,
    /// Amnesiacs who remembered a role. Their role has already been changed.
    pub remembered: Vec<(PlayerSlot, Role)>,
}

impl NightOutcome {
    fn notify(&mut self, slot: PlayerSlot, notice: Notice) {
        self.notices.entry(slot).or_default().push(notice);
    }

    fn kill(&mut self, slot: PlayerSlot, cause: DeathCause) {
        self.deaths.entry(slot).or_default().push(cause);
    }
}

/// A part of the night in which some actions are played out. Each stage only depends on the
/// results of the stages before it in [`STAGES`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Stage {
    /// Barkeeps and Escorts. Their results decide who acts in the later stages, and who a
    /// Serial Killer fights.
    Roleblock,
    /// Fights, plus the other killing and Mafia actions: executions, ignitions, douses, poison,
    /// ambushes and disguises.
    Kill,
    /// Heals, guards, traps, alerts and vests.
    Protect,
    /// Investigations and the Amnesiac. Nothing reads their results, so they could share any
    /// stage's time.
    Investigate,
}

/// The order the night's stages are played in.
pub const STAGES: [Stage; 4] = [
    Stage::Roleblock,
    Stage::Kill,
    Stage::Protect,
    Stage::Investigate,
];

/// A player who plays a skill check for their action.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SkillCheck {
    pub player: PlayerSlot,
    pub stage: Stage,
}

/// An attacker and victim who fight over whether the attack reaches the victim.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Fight {
    pub attacker: PlayerSlot,
    pub victim: PlayerSlot,
    pub stage: Stage,
    pub power: Power,
    /// The victim's defense, as far as the results reported so far show. Heals only count once
    /// their skill check has passed.
    pub defense: Power,
}

/// Who plays which minigame tonight. Everyone else plays a passive one.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NightPlan {
    pub checks: Vec<SkillCheck>,
    pub fights: Vec<Fight>,
}

impl NightPlan {
    /// The skill checks and fights played in one stage.
    pub fn stage(&self, stage: Stage) -> (Vec<SkillCheck>, Vec<Fight>) {
        (
            self.checks
                .iter()
                .filter(|c| c.stage == stage)
                .copied()
                .collect(),
            self.fights
                .iter()
                .filter(|f| f.stage == stage)
                .copied()
                .collect(),
        )
    }
}

/// How tonight's minigames went.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Results {
    checks: BTreeMap<PlayerSlot, bool>,
    fights: BTreeMap<(PlayerSlot, PlayerSlot), bool>,
}

impl Results {
    pub fn check(&mut self, player: PlayerSlot, passed: bool) {
        self.checks.insert(player, passed);
    }

    pub fn fight(&mut self, attacker: PlayerSlot, victim: PlayerSlot, attacker_won: bool) {
        self.fights.insert((attacker, victim), attacker_won);
    }

    fn passed(&self, player: PlayerSlot, unreported: bool) -> bool {
        self.checks.get(&player).copied().unwrap_or(unreported)
    }

    fn won(&self, attacker: PlayerSlot, victim: PlayerSlot) -> bool {
        self.fights
            .get(&(attacker, victim))
            .copied()
            .unwrap_or(true)
    }
}

/// Whether an attack that reached its target kills them. A won fight only means the attack
/// reached them, so the target's defense still has to be beaten.
///
/// To let the fight decide on its own instead, return true here for any attack with `fight`
/// set, and move [`Stage::Protect`] before [`Stage::Kill`] in [`STAGES`] so heals are known
/// (and in [`Fight::defense`]) before the fight starts.
fn kills(attack: &Attack, defense: Power) -> bool {
    attack.power > defense
}

/// What one action does, once its role and target are known.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Ability {
    Execute(PlayerSlot),
    Alert,
    Vest,
    Heal(PlayerSlot),
    Guard(PlayerSlot),
    Trap(PlayerSlot),
    Block(PlayerSlot),
    Disguise(PlayerSlot),
    Kill(PlayerSlot, DeathCause),
    MafiaKill(PlayerSlot),
    Ambush(PlayerSlot),
    Poison(PlayerSlot),
    Douse(PlayerSlot),
    Ignite,
    Interrogate(PlayerSlot),
    Investigate(PlayerSlot),
    Consult(PlayerSlot),
    Watch(PlayerSlot),
    Track(PlayerSlot),
    Bug(PlayerSlot),
    Remember(PlayerSlot),
    Haunt(PlayerSlot),
}

impl Ability {
    /// What a role's action does. None when the role can't do that (the caller has already
    /// checked targets, so this only has to map shapes).
    fn of(role: Role, action: NightAction, actor: PlayerSlot, jail: Option<Jail>) -> Option<Self> {
        use Ability::*;
        let NightAction::Target(t) = action else {
            return match (role, action) {
                (Role::Jailer, NightAction::Activate) => jail
                    .filter(|jail| jail.jailer == actor)
                    .map(|jail| Execute(jail.prisoner)),
                (Role::Veteran, NightAction::Activate) => Some(Alert),
                (Role::Survivor, NightAction::Activate) => Some(Vest),
                (Role::Arsonist, NightAction::Activate) => Some(Ignite),
                _ => None,
            };
        };
        Some(match role {
            Role::Doctor => Heal(t),
            Role::Bodyguard if t == actor => Vest,
            Role::Bodyguard => Guard(t),
            Role::Trapper => Trap(t),
            Role::Barkeep | Role::Escort => Block(t),
            Role::Disguiser => Disguise(t),
            Role::Vigilante => Kill(t, DeathCause::Vigilante),
            Role::SerialKiller => Kill(t, DeathCause::SerialKiller),
            Role::Godfather | Role::Mafioso => MafiaKill(t),
            Role::Ambusher => Ambush(t),
            Role::Poisoner => Poison(t),
            Role::Arsonist => Douse(t),
            Role::Sheriff => Interrogate(t),
            Role::Investigator => Investigate(t),
            Role::Consigliere => Consult(t),
            Role::Lookout => Watch(t),
            Role::Tracker => Track(t),
            Role::Spy => Bug(t),
            Role::Amnesiac => Remember(t),
            Role::Jester => Haunt(t),
            _ => return None,
        })
    }

    /// What a Copycat does when it copies `role` onto `target`. Any kill it copies is a Mafia
    /// kill. Abilities with no target, and ones that only work on the dead, can't be copied.
    fn copied(role: Role, target: PlayerSlot, copycat: PlayerSlot) -> Option<Self> {
        match Ability::of(role, NightAction::Target(target), copycat, None)? {
            Ability::MafiaKill(t) | Ability::Kill(t, _) => {
                Some(Ability::Kill(t, DeathCause::Mafia))
            }
            Ability::Remember(_) | Ability::Haunt(_) => None,
            other => Some(other),
        }
    }

    /// The house this ability visits, if it visits one.
    fn house(self) -> Option<PlayerSlot> {
        use Ability::*;
        match self {
            Heal(t)
            | Guard(t)
            | Trap(t)
            | Block(t)
            | Disguise(t)
            | Kill(t, _)
            | MafiaKill(t)
            | Ambush(t)
            | Poison(t)
            | Douse(t)
            | Interrogate(t)
            | Investigate(t)
            | Consult(t)
            | Watch(t)
            | Track(t)
            | Bug(t) => Some(t),
            Execute(_) | Alert | Vest | Ignite | Remember(_) | Haunt(_) => None,
        }
    }

    /// The victim and strength of an attack decided by a fight, if this is one.
    fn fight(self) -> Option<(PlayerSlot, Power)> {
        match self {
            Ability::MafiaKill(t) | Ability::Kill(t, _) => Some((t, Power::Basic)),
            Ability::Haunt(t) => Some((t, Power::Unstoppable)),
            _ => None,
        }
    }

    /// When the skill check for this ability is played.
    fn stage(self) -> Stage {
        use Ability::*;
        match self {
            Block(_) => Stage::Roleblock,
            Execute(_) | Kill(..) | MafiaKill(_) | Haunt(_) | Ambush(_) | Poison(_) | Douse(_)
            | Ignite | Disguise(_) => Stage::Kill,
            Heal(_) | Guard(_) | Trap(_) | Alert | Vest => Stage::Protect,
            Interrogate(_) | Investigate(_) | Consult(_) | Watch(_) | Track(_) | Bug(_)
            | Remember(_) => Stage::Investigate,
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct Intent {
    actor: PlayerSlot,
    ability: Ability,
    /// Done by a Copycat with a copied ability. Copied uses don't spend the original's limits.
    copied: bool,
}

#[derive(Clone, Copy, Debug)]
struct Attack {
    attacker: PlayerSlot,
    target: PlayerSlot,
    power: Power,
    cause: DeathCause,
    /// A visitor attacking in person, which a Bodyguard or a trap can stop.
    direct: bool,
    /// Decided by a fight between attacker and target.
    fight: bool,
}

/// Works out a night. `players` is everyone in the game; role state (uses, douses, poison,
/// traps, a Vigilante's guilt, an Amnesiac's new role) is updated in place, but nobody is
/// marked dead. `actions` must already be checked against each role's target rule. `night` is
/// the night's number, which poison uses to know when it lands.
pub fn resolve(
    players: &mut [Player],
    actions: &BTreeMap<PlayerSlot, NightAction>,
    night: u32,
    jail: Option<Jail>,
    results: &Results,
    rng: &mut impl Rng,
) -> NightOutcome {
    run(players, actions, night, jail, results, true, rng).0
}

/// Works out who plays which minigame tonight, given the results so far. Call it at the start
/// of each stage: a roleblock that passed takes away its target's minigames and turns a Serial
/// Killer's fight onto the roleblocker, and a heal that passed shows in [`Fight::defense`].
///
/// A skill check with no result yet counts as failed here, so a player is given a minigame
/// whenever they might still act. That only matters inside one stage: an Escort blocking a
/// Copycat who copied a roleblock leaves the Copycat a skill check either way.
pub fn plan(
    players: &[Player],
    actions: &BTreeMap<PlayerSlot, NightAction>,
    night: u32,
    jail: Option<Jail>,
    results: &Results,
) -> NightPlan {
    // Only Ambushers roll, and their attacks aren't fights, so any seed gives the same plan.
    let mut rng = ChaCha8Rng::seed_from_u64(0);
    run(
        &mut players.to_vec(),
        actions,
        night,
        jail,
        results,
        false,
        &mut rng,
    )
    .1
}

/// [`resolve`] and [`plan`] in one pass. `unreported` is whether a skill check with no result
/// counts as passed.
fn run(
    players: &mut [Player],
    actions: &BTreeMap<PlayerSlot, NightAction>,
    night: u32,
    jail: Option<Jail>,
    results: &Results,
    unreported: bool,
    rng: &mut impl Rng,
) -> (NightOutcome, NightPlan) {
    let passed = |slot: PlayerSlot| results.passed(slot, unreported);
    let index: BTreeMap<PlayerSlot, usize> = players
        .iter()
        .enumerate()
        .map(|(i, p)| (p.slot, i))
        .collect();
    let role = |players: &[Player], slot: PlayerSlot| players[index[&slot]].role;
    let mut out = NightOutcome::default();

    // A jail only holds if both of them are still alive.
    let jail = jail.filter(|jail| {
        [jail.jailer, jail.prisoner]
            .iter()
            .all(|slot| index.get(slot).is_some_and(|&i| players[i].alive))
    });
    let prisoner = jail.map(|jail| jail.prisoner);

    // What everyone is trying to do.
    let mut intents = Vec::new();
    // (copycat, copied player, their role, whether the ability could be used)
    let mut copies = Vec::new();
    for (&actor, &action) in actions {
        let Some(&i) = index.get(&actor) else {
            continue;
        };
        let player = &players[i];
        let haunting = player.role == Role::Jester && player.won;
        if !player.alive && !haunting {
            continue;
        }
        if let (Role::Copycat, NightAction::TwoTargets(copied, target)) = (player.role, action) {
            let copied_role = role(players, copied);
            let ability = Ability::copied(copied_role, target, actor);
            copies.push((actor, copied, copied_role, ability.is_some()));
            if let Some(ability) = ability {
                intents.push(Intent {
                    actor,
                    ability,
                    copied: true,
                });
            }
        } else if let Some(ability) = Ability::of(player.role, action, actor, jail) {
            intents.push(Intent {
                actor,
                ability,
                copied: false,
            });
        }
    }

    let mut attacks = VecDeque::new();

    // 1. Jail. A botched execution leaves a Serial Killer alive in jail too.
    let mut blocked = BTreeSet::new();
    if let Some(jail) = jail {
        blocked.insert(jail.prisoner);
        let executing = passed(jail.jailer)
            && intents
                .iter()
                .any(|i| i.actor == jail.jailer && matches!(i.ability, Ability::Execute(_)));
        if !executing && role(players, jail.prisoner) == Role::SerialKiller {
            attacks.push_back(Attack {
                attacker: jail.prisoner,
                target: jail.jailer,
                power: Power::Basic,
                cause: DeathCause::SerialKiller,
                direct: false,
                fight: false,
            });
        }
    }

    // 2. Roleblocks. Barkeeps and Escorts can't be blocked themselves, so they go first; a
    // Copycat with a copied roleblock can be, so it goes after them.
    let mut blockers: Vec<Intent> = intents
        .iter()
        .filter(|i| matches!(i.ability, Ability::Block(_)))
        .copied()
        .collect();
    blockers.sort_by_key(|i| i.copied);
    let mut serial_killer_blockers: BTreeMap<PlayerSlot, Vec<PlayerSlot>> = BTreeMap::new();
    for intent in blockers {
        let Ability::Block(target) = intent.ability else {
            unreachable!()
        };
        if blocked.contains(&intent.actor) || Some(target) == prisoner || !passed(intent.actor) {
            continue;
        }
        let target_role = role(players, target);
        if target_role == Role::SerialKiller {
            serial_killer_blockers
                .entry(target)
                .or_default()
                .push(intent.actor);
        } else if target_role.roleblock_immune() {
            out.notify(target, Notice::RoleblockImmune);
        } else if blocked.insert(target) {
            out.notify(target, Notice::Roleblocked);
        }
    }

    // 3. Visits. Drop what was blocked, point roleblocked Serial Killers at their blockers, and
    // merge the Godfather's and Mafioso's choices into one Mafia kill.
    let mut active: Vec<Intent> = intents
        .into_iter()
        .filter(|i| !blocked.contains(&i.actor))
        .collect();
    for (killer, blockers) in &serial_killer_blockers {
        active.retain(|i| !(i.actor == *killer && matches!(i.ability, Ability::Kill(..))));
        for blocker in blockers {
            active.push(Intent {
                actor: *killer,
                ability: Ability::Kill(*blocker, DeathCause::SerialKiller),
                copied: false,
            });
        }
    }
    let mafia_choice = |active: &[Intent], wanted: Role| {
        active.iter().find_map(|i| match i.ability {
            Ability::MafiaKill(target) if role(players, i.actor) == wanted => {
                Some((i.actor, target))
            }
            _ => None,
        })
    };
    let godfather = mafia_choice(&active, Role::Godfather);
    let mafioso_choice = mafia_choice(&active, Role::Mafioso);
    let free_mafioso = players
        .iter()
        .find(|p| p.alive && p.role == Role::Mafioso && !blocked.contains(&p.slot))
        .map(|p| p.slot);
    active.retain(|i| !matches!(i.ability, Ability::MafiaKill(_)));
    let mafia_kill = match free_mafioso {
        Some(mafioso) => godfather
            .or(mafioso_choice)
            .map(|(_, target)| (mafioso, target)),
        None => godfather,
    };
    if let Some((killer, target)) = mafia_kill {
        active.push(Intent {
            actor: killer,
            ability: Ability::MafiaKill(target),
            copied: false,
        });
    }
    let mut visits: Vec<(PlayerSlot, PlayerSlot)> = active
        .iter()
        .filter_map(|i| i.ability.house().map(|house| (i.actor, house)))
        .filter(|(visitor, house)| visitor != house)
        .collect();
    for (copycat, copied, ..) in &copies {
        if !blocked.contains(copycat) && copycat != copied {
            visits.push((*copycat, *copied));
        }
    }
    let visitors_of = |house: PlayerSlot| -> Vec<PlayerSlot> {
        let mut found: Vec<_> = visits
            .iter()
            .filter(|v| v.1 == house)
            .map(|v| v.0)
            .collect();
        found.sort();
        found.dedup();
        found
    };

    // Everyone still acting plays for it. Those who fail have visited, but do nothing more.
    let mut plan = NightPlan::default();
    for intent in &active {
        if intent.ability.fight().is_none() {
            plan.checks.push(SkillCheck {
                player: intent.actor,
                stage: intent.ability.stage(),
            });
        }
    }
    active.retain(|i| i.ability.fight().is_some() || passed(i.actor));

    // 4. Self effects and disguises.
    let mut alert = BTreeSet::new();
    let mut vested = BTreeSet::new();
    let mut appearance: BTreeMap<PlayerSlot, Role> = BTreeMap::new();
    for intent in &active {
        match intent.ability {
            Ability::Alert => {
                alert.insert(intent.actor);
            }
            Ability::Vest => {
                vested.insert(intent.actor);
            }
            Ability::Disguise(target) => {
                appearance.insert(intent.actor, role(players, target));
                appearance.insert(target, role(players, intent.actor));
            }
            _ => {}
        }
        let limited = match intent.ability {
            Ability::Alert | Ability::Vest | Ability::Execute(_) => true,
            Ability::Kill(_, DeathCause::Vigilante) => true,
            Ability::Heal(target) => target == intent.actor,
            _ => false,
        };
        if !intent.copied && limited {
            let player = &mut players[index[&intent.actor]];
            player.uses = player.uses.saturating_sub(1);
        }
    }

    // 5. Protection.
    let mut heals: BTreeMap<PlayerSlot, Vec<PlayerSlot>> = BTreeMap::new();
    let mut guards: BTreeMap<PlayerSlot, Vec<PlayerSlot>> = BTreeMap::new();
    for intent in &active {
        match intent.ability {
            Ability::Heal(target) => heals.entry(target).or_default().push(intent.actor),
            Ability::Guard(target) => guards.entry(target).or_default().push(intent.actor),
            Ability::Trap(target) => players[index[&intent.actor]].trap = Some(target),
            _ => {}
        }
    }
    // A jail protects its prisoner from everyone but the Jailer.
    let defense = |players: &[Player], target: PlayerSlot, by_jailer: bool| {
        let mut defense = role(players, target).base_defense();
        if alert.contains(&target) || vested.contains(&target) {
            defense = defense.max(Power::Basic);
        }
        let jailed = prisoner == Some(target) && !by_jailer;
        if jailed || heals.contains_key(&target) {
            defense = defense.max(Power::Powerful);
        }
        defense
    };
    for intent in &active {
        if let Some((victim, power)) = intent.ability.fight() {
            plan.fights.push(Fight {
                attacker: intent.actor,
                victim,
                stage: Stage::Kill,
                power,
                defense: defense(players, victim, false),
            });
        }
    }

    // 6. Attacks, in a fixed order so results never depend on who submitted first.
    for player in players.iter_mut().filter(|p| p.alive && p.guilty) {
        player.guilty = false;
        attacks.push_back(Attack {
            attacker: player.slot,
            target: player.slot,
            power: Power::Unstoppable,
            cause: DeathCause::Guilt,
            direct: false,
            fight: false,
        });
    }
    for intent in &active {
        let (target, power, cause, direct) = match intent.ability {
            Ability::Execute(target) => (target, Power::Unstoppable, DeathCause::Jailer, false),
            Ability::MafiaKill(target) => (target, Power::Basic, DeathCause::Mafia, true),
            Ability::Kill(target, cause) => (target, Power::Basic, cause, true),
            Ability::Haunt(target) => (target, Power::Unstoppable, DeathCause::Haunted, false),
            _ => continue,
        };
        attacks.push_back(Attack {
            attacker: intent.actor,
            target,
            power,
            cause,
            direct,
            fight: intent.ability.fight().is_some(),
        });
    }
    for intent in &active {
        let Ability::Ambush(house) = intent.ability else {
            continue;
        };
        let victims: Vec<PlayerSlot> = visitors_of(house)
            .into_iter()
            .filter(|v| *v != intent.actor && !players[index[v]].is_mafia())
            .collect();
        for victim in &victims {
            out.notify(
                *victim,
                Notice::SawAmbusher {
                    ambusher: intent.actor,
                },
            );
        }
        if let Some(victim) = victims.choose(rng) {
            attacks.push_back(Attack {
                attacker: intent.actor,
                target: *victim,
                power: Power::Basic,
                cause: DeathCause::Mafia,
                direct: true,
                fight: false,
            });
        }
    }
    for player in players.iter_mut().filter(|p| p.alive) {
        if let Some((poisoner, due)) = player.poison
            && due <= night
        {
            player.poison = None;
            attacks.push_back(Attack {
                attacker: poisoner,
                target: player.slot,
                power: Power::Basic,
                cause: DeathCause::Poison,
                direct: false,
                fight: false,
            });
        }
    }
    for intent in &active {
        if intent.ability != Ability::Ignite {
            continue;
        }
        for player in players.iter_mut().filter(|p| p.doused) {
            player.doused = false;
            if player.alive {
                attacks.push_back(Attack {
                    attacker: intent.actor,
                    target: player.slot,
                    power: Power::Unstoppable,
                    cause: DeathCause::Arsonist,
                    direct: false,
                    fight: false,
                });
            }
        }
    }
    for veteran in &alert {
        let visitors = visitors_of(*veteran);
        if !visitors.is_empty() {
            out.notify(*veteran, Notice::ShotVisitor);
        }
        for visitor in visitors {
            attacks.push_back(Attack {
                attacker: *veteran,
                target: visitor,
                power: Power::Powerful,
                cause: DeathCause::Veteran,
                direct: false,
                fight: false,
            });
        }
    }

    while let Some(attack) = attacks.pop_front() {
        let target = attack.target;
        if attack.fight && !results.won(attack.attacker, target) {
            continue;
        }
        if attack.direct {
            if let Some(bodyguard) = guards.get_mut(&target).and_then(|g| g.pop()) {
                // The bodyguard fights the attacker off and dies doing it.
                out.kill(bodyguard, attack.cause);
                out.notify(
                    target,
                    Notice::Attacked {
                        saved: SaveReason::Guarded,
                    },
                );
                attacks.push_back(Attack {
                    attacker: bodyguard,
                    target: attack.attacker,
                    power: Power::Powerful,
                    cause: DeathCause::Bodyguard,
                    direct: false,
                    fight: false,
                });
                continue;
            }
            if let Some(trapper) = players
                .iter_mut()
                .find(|p| p.alive && p.trap == Some(target))
            {
                trapper.trap = None;
                let trapper = trapper.slot;
                out.notify(trapper, Notice::TrapTriggered { target });
                out.notify(
                    target,
                    Notice::Attacked {
                        saved: SaveReason::Trapped,
                    },
                );
                attacks.push_back(Attack {
                    attacker: trapper,
                    target: attack.attacker,
                    power: Power::Powerful,
                    cause: DeathCause::Trap,
                    direct: false,
                    fight: false,
                });
                continue;
            }
        }

        let healers = heals.get(&target).cloned().unwrap_or_default();
        let by_jailer = attack.cause == DeathCause::Jailer;
        let jailed = prisoner == Some(target) && !by_jailer;
        if kills(&attack, defense(players, target, by_jailer)) {
            out.kill(target, attack.cause);
            let target_is_town = players[index[&target]].faction() == Faction::Town;
            let attacker = &mut players[index[&attack.attacker]];
            if target_is_town && attack.cause == DeathCause::Vigilante {
                attacker.guilty = true;
            }
            if target_is_town && attack.cause == DeathCause::Jailer {
                attacker.uses = 0;
                out.notify(attack.attacker, Notice::LostExecutions);
            }
        } else {
            let saved = if jailed {
                SaveReason::Jailed
            } else if !healers.is_empty() {
                SaveReason::Healed
            } else {
                SaveReason::Defense
            };
            out.notify(target, Notice::Attacked { saved });
            for healer in healers {
                out.notify(healer, Notice::TargetAttacked { target });
            }
        }
    }

    // Poison and douses don't kill tonight, so they come after the attacks.
    for intent in &active {
        match intent.ability {
            Ability::Poison(target) if heals.contains_key(&target) => {
                out.notify(target, Notice::PoisonCured);
            }
            Ability::Poison(target) => {
                players[index[&target]].poison = Some((intent.actor, night + 1));
                out.notify(target, Notice::Poisoned);
            }
            Ability::Douse(target) => {
                players[index[&target]].doused = true;
                out.notify(target, Notice::Doused);
            }
            _ => {}
        }
    }

    // 7. Investigations.
    let appears_as = |players: &[Player], slot: PlayerSlot| {
        appearance
            .get(&slot)
            .copied()
            .unwrap_or_else(|| role(players, slot))
    };
    let mut bugs = Vec::new();
    for intent in &active {
        let notice = match intent.ability {
            Ability::Interrogate(target) => Notice::SheriffResult {
                target,
                suspicious: appears_as(players, target).suspicious(),
            },
            Ability::Investigate(target) => Notice::InvestigatorResult {
                target,
                roles: appears_as(players, target)
                    .investigator_group()
                    .roles()
                    .to_vec(),
            },
            Ability::Consult(target) => Notice::ConsigliereResult {
                target,
                role: appears_as(players, target),
            },
            Ability::Watch(target) => Notice::LookoutResult {
                target,
                visitors: visitors_of(target)
                    .into_iter()
                    .filter(|v| *v != intent.actor)
                    .collect(),
            },
            Ability::Track(target) => {
                let mut visited: Vec<_> = visits
                    .iter()
                    .filter(|v| v.0 == target)
                    .map(|v| v.1)
                    .collect();
                visited.sort();
                visited.dedup();
                Notice::TrackerResult { target, visited }
            }
            Ability::Bug(target) => {
                bugs.push((intent.actor, target));
                let mut targets: Vec<_> = visits
                    .iter()
                    .filter(|v| players[index[&v.0]].is_mafia())
                    .map(|v| v.1)
                    .collect();
                targets.sort();
                targets.dedup();
                Notice::SpyMafiaVisits { targets }
            }
            _ => continue,
        };
        out.notify(intent.actor, notice);
    }
    for (copycat, copied, copied_role, worked) in copies {
        if !blocked.contains(&copycat) {
            out.notify(
                copycat,
                Notice::CopycatLearned {
                    target: copied,
                    role: copied_role,
                    copied: worked,
                },
            );
        }
    }
    // Spies hear their target's night last, once everything else has happened to them.
    for (spy, target) in bugs {
        let heard = out.notices.get(&target).cloned().unwrap_or_default();
        out.notify(spy, Notice::SpyBug { target, heard });
    }

    // 8. Remembering.
    for intent in &active {
        let Ability::Remember(target) = intent.ability else {
            continue;
        };
        let target_player = &players[index[&target]];
        if target_player.alive || out.deaths.contains_key(&intent.actor) {
            continue;
        }
        let remembered = target_player.role;
        players[index[&intent.actor]].become_role(remembered);
        out.remembered.push((intent.actor, remembered));
    }

    out.visits = visits;
    (out, plan)
}
