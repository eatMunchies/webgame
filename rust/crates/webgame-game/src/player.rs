use webgame_protocol::{Faction, PlayerSlot, Role, UserId};

/// One player in a game, with the state their role carries from night to night.
#[derive(Clone, Debug)]
pub struct Player {
    pub slot: PlayerSlot,
    pub user_id: UserId,
    pub name: String,
    pub role: Role,
    pub alive: bool,
    pub will: String,
    /// Uses left of a limited ability (see [`Role::starting_uses`]); 0 for unlimited roles,
    /// which never check it.
    pub uses: u8,
    /// Doused by an Arsonist, waiting to be ignited.
    pub doused: bool,
    /// Poisoned, by whom, and the night the poison kills on.
    pub poison: Option<(PlayerSlot, u32)>,
    /// For a Trapper: the house the trap is set at.
    pub trap: Option<PlayerSlot>,
    /// For a Vigilante who shot a Town member: dies the next night.
    pub guilty: bool,
    /// For an Executioner: the player to get lynched.
    pub executioner_target: Option<PlayerSlot>,
    /// A Jester who was lynched, or an Executioner whose target was. They win whatever happens.
    pub won: bool,
}

impl Player {
    pub fn new(slot: PlayerSlot, user_id: UserId, name: String, role: Role) -> Self {
        Player {
            slot,
            user_id,
            name,
            role,
            alive: true,
            will: String::new(),
            uses: role.starting_uses().unwrap_or(0),
            doused: false,
            poison: None,
            trap: None,
            guilty: false,
            executioner_target: None,
            won: false,
        }
    }

    pub fn faction(&self) -> Faction {
        self.role.faction()
    }

    pub fn is_mafia(&self) -> bool {
        self.faction() == Faction::Mafia
    }

    /// Changes the player's role, resetting the uses of limited abilities.
    pub fn become_role(&mut self, role: Role) {
        self.role = role;
        self.uses = role.starting_uses().unwrap_or(0);
        self.trap = None;
    }
}
