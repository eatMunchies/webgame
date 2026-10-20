use std::fmt;

use serde::{Deserialize, Serialize};

/// The side a role plays for. Town and Mafia win together; each Neutral role has its own goal.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Faction {
    Town,
    Mafia,
    Neutral,
}

/// A group of roles within a faction. Role lists are written in categories ("Town
/// Investigative") so a game has a known shape without everyone knowing the exact roles.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum RoleCategory {
    TownPower,
    TownInvestigative,
    TownSupport,
    TownKilling,
    TownProtective,
    MafiaKilling,
    MafiaSupport,
    MafiaDeception,
    NeutralBenign,
    NeutralEvil,
    NeutralKilling,
}

impl RoleCategory {
    pub const ALL: [RoleCategory; 11] = [
        RoleCategory::TownPower,
        RoleCategory::TownInvestigative,
        RoleCategory::TownSupport,
        RoleCategory::TownKilling,
        RoleCategory::TownProtective,
        RoleCategory::MafiaKilling,
        RoleCategory::MafiaSupport,
        RoleCategory::MafiaDeception,
        RoleCategory::NeutralBenign,
        RoleCategory::NeutralEvil,
        RoleCategory::NeutralKilling,
    ];

    pub fn faction(self) -> Faction {
        use RoleCategory::*;
        match self {
            TownPower | TownInvestigative | TownSupport | TownKilling | TownProtective => {
                Faction::Town
            }
            MafiaKilling | MafiaSupport | MafiaDeception => Faction::Mafia,
            NeutralBenign | NeutralEvil | NeutralKilling => Faction::Neutral,
        }
    }

    /// The roles in this category.
    pub fn roles(self) -> impl Iterator<Item = Role> {
        Role::ALL
            .into_iter()
            .filter(move |role| role.category() == self)
    }

    pub fn name(self) -> &'static str {
        use RoleCategory::*;
        match self {
            TownPower => "Town Power",
            TownInvestigative => "Town Investigative",
            TownSupport => "Town Support",
            TownKilling => "Town Killing",
            TownProtective => "Town Protective",
            MafiaKilling => "Mafia Killing",
            MafiaSupport => "Mafia Support",
            MafiaDeception => "Mafia Deception",
            NeutralBenign => "Neutral Benign",
            NeutralEvil => "Neutral Evil",
            NeutralKilling => "Neutral Killing",
        }
    }
}

/// How hard an attack hits, or how much defense a player has. An attack kills only when it is
/// stronger than the target's defense.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Power {
    None,
    Basic,
    Powerful,
    Unstoppable,
}

/// What a role's night action can be aimed at. The client uses this to decide which players to
/// offer as targets; the server checks the same thing plus limited uses (bullets, alerts).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum TargetRule {
    /// No night action.
    None,
    /// One other living player.
    Other,
    /// One other living player who isn't in the Mafia.
    OtherNotMafia,
    /// One living player, possibly yourself (a self-heal or self-vest, which is limited).
    AnyAlive,
    /// Only yourself: an ability that is switched on, like an alert or a vest.
    SelfOnly,
    /// One dead player.
    Dead,
    /// Two living players: the Copycat copies the first player's ability onto the second.
    TwoAlive,
    /// Another living player to douse, or yourself to ignite everyone doused.
    DouseOrIgnite,
    /// Execute tonight's prisoner, if you jailed someone during the day.
    Execute,
}

/// Every role in the game.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Role {
    // Town
    Jailer,
    Sheriff,
    Investigator,
    Lookout,
    Tracker,
    Spy,
    Barkeep,
    Medium,
    Vigilante,
    Veteran,
    Trapper,
    Doctor,
    Bodyguard,
    // Mafia
    Godfather,
    Mafioso,
    Ambusher,
    Poisoner,
    Consigliere,
    Escort,
    Disguiser,
    Copycat,
    // Neutral
    Executioner,
    Jester,
    Amnesiac,
    Survivor,
    SerialKiller,
    Arsonist,
}

impl Role {
    pub const ALL: [Role; 27] = [
        Role::Jailer,
        Role::Sheriff,
        Role::Investigator,
        Role::Lookout,
        Role::Tracker,
        Role::Spy,
        Role::Barkeep,
        Role::Medium,
        Role::Vigilante,
        Role::Veteran,
        Role::Trapper,
        Role::Doctor,
        Role::Bodyguard,
        Role::Godfather,
        Role::Mafioso,
        Role::Ambusher,
        Role::Poisoner,
        Role::Consigliere,
        Role::Escort,
        Role::Disguiser,
        Role::Copycat,
        Role::Executioner,
        Role::Jester,
        Role::Amnesiac,
        Role::Survivor,
        Role::SerialKiller,
        Role::Arsonist,
    ];

    pub fn name(self) -> &'static str {
        use Role::*;
        match self {
            Jailer => "Jailer",
            Sheriff => "Sheriff",
            Investigator => "Investigator",
            Lookout => "Lookout",
            Tracker => "Tracker",
            Spy => "Spy",
            Barkeep => "Barkeep",
            Medium => "Medium",
            Vigilante => "Vigilante",
            Veteran => "Veteran",
            Trapper => "Trapper",
            Doctor => "Doctor",
            Bodyguard => "Bodyguard",
            Godfather => "Godfather",
            Mafioso => "Mafioso",
            Ambusher => "Ambusher",
            Poisoner => "Poisoner",
            Consigliere => "Consigliere",
            Escort => "Escort",
            Disguiser => "Disguiser",
            Copycat => "Copycat",
            Executioner => "Executioner",
            Jester => "Jester",
            Amnesiac => "Amnesiac",
            Survivor => "Survivor",
            SerialKiller => "Serial Killer",
            Arsonist => "Arsonist",
        }
    }

    pub fn category(self) -> RoleCategory {
        use Role::*;
        use RoleCategory::*;
        match self {
            Jailer => TownPower,
            Sheriff | Investigator | Lookout | Tracker | Spy => TownInvestigative,
            Barkeep | Medium => TownSupport,
            Vigilante | Veteran => TownKilling,
            Trapper | Doctor | Bodyguard => TownProtective,
            Godfather | Mafioso | Ambusher | Poisoner => MafiaKilling,
            Consigliere | Escort => MafiaSupport,
            Disguiser | Copycat => MafiaDeception,
            Survivor | Amnesiac => NeutralBenign,
            Executioner | Jester => NeutralEvil,
            SerialKiller | Arsonist => NeutralKilling,
        }
    }

    pub fn faction(self) -> Faction {
        self.category().faction()
    }

    /// Unique roles appear at most once in a game.
    pub fn unique(self) -> bool {
        matches!(
            self,
            Role::Jailer | Role::Veteran | Role::Godfather | Role::Mafioso
        )
    }

    /// The defense a role has every night without doing anything.
    pub fn base_defense(self) -> Power {
        match self {
            Role::Godfather | Role::Executioner | Role::SerialKiller | Role::Arsonist => {
                Power::Basic
            }
            _ => Power::None,
        }
    }

    /// Roleblock-immune roles keep acting when a Barkeep or Escort visits them.
    pub fn roleblock_immune(self) -> bool {
        matches!(
            self,
            Role::Barkeep | Role::Escort | Role::Veteran | Role::SerialKiller
        )
    }

    /// Roles that can kill on their own and keep the game going until they're dead.
    pub fn is_neutral_killing(self) -> bool {
        self.category() == RoleCategory::NeutralKilling
    }

    /// Whether a Sheriff sees this role as suspicious. The Godfather and the Arsonist hide.
    pub fn suspicious(self) -> bool {
        (self.faction() == Faction::Mafia && self != Role::Godfather) || self == Role::SerialKiller
    }

    pub fn investigator_group(self) -> InvestigatorGroup {
        InvestigatorGroup::ALL
            .into_iter()
            .find(|group| group.roles().contains(&self))
            .expect("every role is in an investigator group")
    }

    pub fn target_rule(self) -> TargetRule {
        use Role::*;
        match self {
            Jailer => TargetRule::Execute,
            Sheriff | Investigator | Lookout | Tracker | Spy | Barkeep | Trapper | Vigilante
            | Disguiser | SerialKiller => TargetRule::Other,
            Doctor | Bodyguard => TargetRule::AnyAlive,
            Veteran | Survivor => TargetRule::SelfOnly,
            Godfather | Mafioso | Ambusher | Poisoner | Consigliere | Escort => {
                TargetRule::OtherNotMafia
            }
            Copycat => TargetRule::TwoAlive,
            Amnesiac => TargetRule::Dead,
            Arsonist => TargetRule::DouseOrIgnite,
            Medium | Executioner | Jester => TargetRule::None,
        }
    }

    /// How many times a limited ability can be used, when it is limited: bullets, alerts,
    /// vests, self-heals, executions.
    pub fn starting_uses(self) -> Option<u8> {
        match self {
            Role::Vigilante | Role::Veteran | Role::Jailer => Some(3),
            Role::Survivor => Some(4),
            Role::Doctor | Role::Bodyguard | Role::Amnesiac => Some(1),
            _ => None,
        }
    }

    /// What the role does, in a sentence or two.
    pub fn ability(self) -> &'static str {
        use Role::*;
        match self {
            Jailer => {
                "During the day, pick someone to jail. At night you talk to them privately, they can't act, and you may execute them (3 times, not on night 1; executing a Town member costs you the rest)."
            }
            Sheriff => {
                "Interrogate one person a night to learn if they are suspicious (Mafia other than the Godfather, or a Serial Killer)."
            }
            Investigator => {
                "Investigate one person a night to learn a short list of roles they could be."
            }
            Lookout => "Watch one house a night to see who visits it.",
            Tracker => "Follow one person a night to see who they visit.",
            Spy => {
                "Bug one house a night to hear what happens to its owner. You also learn who the Mafia visited."
            }
            Barkeep => {
                "Keep one person at the bar all night so they can't act (roleblock). You can't be roleblocked."
            }
            Medium => "Speak with the dead at night, without them knowing who you are.",
            Vigilante => {
                "Shoot one person a night (3 bullets, not on night 1). Shooting Town makes you die of guilt the next night."
            }
            Veteran => {
                "Go on alert (3 times). While alert you shoot everyone who visits you and can't be killed by basic attacks."
            }
            Trapper => {
                "Set a trap at a house. The first person to attack its owner is attacked by the trap instead."
            }
            Doctor => {
                "Heal one person a night, saving them from attacks. You can heal yourself once."
            }
            Bodyguard => {
                "Guard one person a night. If they are attacked you fight off the attacker and die. You can vest yourself once."
            }
            Godfather => {
                "Choose who the Mafia kills. The Mafioso carries it out; if they can't, you do. Sheriffs see you as not suspicious."
            }
            Mafioso => "Kill the Godfather's choice each night, or your own if they don't choose.",
            Ambusher => {
                "Lie in wait at a house and attack one person who visits it. Everyone who visits sees you."
            }
            Poisoner => {
                "Poison one person a night. They die the next night unless a Doctor heals them."
            }
            Consigliere => "Learn one person's exact role each night.",
            Escort => {
                "Distract one person a night so they can't act (roleblock). You can't be roleblocked."
            }
            Disguiser => {
                "Swap appearances with one person a night: investigators who look at either of you see the other's role."
            }
            Copycat => {
                "Pick two people: copy the first one's night ability and use it on the second. You learn the first one's role."
            }
            Executioner => {
                "Get your target lynched. If they die any other way, you become a Jester. You have basic defense."
            }
            Jester => {
                "Get yourself lynched. If you are, you haunt one of the people who voted guilty the next night."
            }
            Amnesiac => "Once, remember that you were like a dead player and take their role.",
            Survivor => "Stay alive to the end. You have 4 bulletproof vests to put on at night.",
            SerialKiller => {
                "Kill one person a night. You can't be roleblocked: you kill whoever tries instead."
            }
            Arsonist => {
                "Douse one person a night, or ignite to burn everyone doused at once. Sheriffs see you as not suspicious."
            }
        }
    }

    /// How the role wins.
    pub fn goal(self) -> &'static str {
        match self.faction() {
            Faction::Town => "Lynch every criminal and evildoer.",
            Faction::Mafia => "Kill anyone who won't submit to the Mafia.",
            Faction::Neutral => match self {
                Role::Executioner => "Get your target lynched.",
                Role::Jester => "Get yourself lynched.",
                Role::Amnesiac => "Remember a role, then win with its side.",
                Role::Survivor => "Be alive when the game ends.",
                _ => "Be the last one standing.",
            },
        }
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// What an Investigator learns: a handful of roles, one of which is the target's. Every role is
/// in exactly one group.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum InvestigatorGroup {
    Weapons,
    Blood,
    Secrets,
    Shadows,
    Distraction,
    Justice,
    Watchers,
    Afterlife,
}

impl InvestigatorGroup {
    pub const ALL: [InvestigatorGroup; 8] = [
        InvestigatorGroup::Weapons,
        InvestigatorGroup::Blood,
        InvestigatorGroup::Secrets,
        InvestigatorGroup::Shadows,
        InvestigatorGroup::Distraction,
        InvestigatorGroup::Justice,
        InvestigatorGroup::Watchers,
        InvestigatorGroup::Afterlife,
    ];

    pub fn roles(self) -> &'static [Role] {
        use Role::*;
        match self {
            InvestigatorGroup::Weapons => &[Vigilante, Veteran, Mafioso, Ambusher],
            InvestigatorGroup::Blood => &[Doctor, Disguiser, SerialKiller, Poisoner],
            InvestigatorGroup::Secrets => &[Investigator, Consigliere, Tracker],
            InvestigatorGroup::Shadows => &[Bodyguard, Godfather, Arsonist],
            InvestigatorGroup::Distraction => &[Barkeep, Escort, Copycat],
            InvestigatorGroup::Justice => &[Sheriff, Executioner, Trapper],
            InvestigatorGroup::Watchers => &[Lookout, Spy, Jester],
            InvestigatorGroup::Afterlife => &[Jailer, Medium, Survivor, Amnesiac],
        }
    }
}

/// One line of a game's role list: either an exact role or a random pick from a group.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RoleSlot {
    Exact(Role),
    Category(RoleCategory),
    /// Any role from one faction ("Random Town").
    Faction(Faction),
    Any,
}

impl RoleSlot {
    pub fn allows(self, role: Role) -> bool {
        match self {
            RoleSlot::Exact(exact) => role == exact,
            RoleSlot::Category(category) => role.category() == category,
            RoleSlot::Faction(faction) => role.faction() == faction,
            RoleSlot::Any => true,
        }
    }
}

impl fmt::Display for RoleSlot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RoleSlot::Exact(role) => f.write_str(role.name()),
            RoleSlot::Category(category) => f.write_str(category.name()),
            RoleSlot::Faction(faction) => write!(f, "Random {faction:?}"),
            RoleSlot::Any => f.write_str("Any"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_role_is_in_exactly_one_investigator_group() {
        for role in Role::ALL {
            let groups = InvestigatorGroup::ALL
                .into_iter()
                .filter(|group| group.roles().contains(&role))
                .count();
            assert_eq!(groups, 1, "{role} is in {groups} groups");
        }
    }

    #[test]
    fn every_category_has_a_role() {
        for category in RoleCategory::ALL {
            assert!(category.roles().count() > 0, "{category:?} is empty");
        }
    }

    #[test]
    fn sheriff_sees_through_most_of_the_mafia() {
        assert!(Role::Mafioso.suspicious());
        assert!(Role::SerialKiller.suspicious());
        assert!(!Role::Godfather.suspicious());
        assert!(!Role::Arsonist.suspicious());
        assert!(!Role::Doctor.suspicious());
    }
}
