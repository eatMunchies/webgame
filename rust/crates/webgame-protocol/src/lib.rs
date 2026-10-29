//! The types the game client and the game server share.
//!
//! Everything that crosses the network is defined here once: ids, roles, phases, chat channels,
//! and the [`ClientMessage`] / [`ServerMessage`] enums. Rules that both sides need to agree on
//! (which chat channel a player may use, which roles are unique, lobby code format) live here
//! too, so the client can grey out a button for exactly the reason the server would refuse it.
//!
//! This crate is compiled into the Godot extension, including its WebAssembly build, so it must
//! stay free of anything that needs an OS: no tokio, no sockets, no files.

mod actions;
mod chat;
mod ids;
mod messages;
mod minigame;
mod phase;
mod roles;
mod world;

pub use actions::{NightAction, Verdict};
pub use chat::{ChatChannel, ChatContext, ChatMessage, ChatSender, JailStatus};
pub use ids::{CodeError, LobbyCode, NameError, PlayerSlot, UserId, validate_username};
pub use messages::{
    Accepted, ClientMessage, DeathCause, DeathReport, DecodeError, ErrorCode, GameAction,
    GameOverInfo, GameStart, LobbyInfo, LobbyMember, Notice, Outcome, PlayerSummary, SaveReason,
    ServerError, ServerMessage, TeamMember, VoteEntry, decode, encode,
};
pub use minigame::{
    FIGHT_HP, FIGHT_ROUNDS, FightMove, FightView, Fighter, GRAB_WINDUP_MS, Minigame, MinigamePlay,
    MinigameResult, SKILL_CHECK_PRESSES, STAGGER_MS, STRIKE_WINDUP_MS,
};
pub use phase::{DayStage, GamePhase, NightStage};
pub use roles::{Faction, InvestigatorGroup, Power, Role, RoleCategory, RoleSlot, TargetRule};
pub use world::{
    Appearance, Facing, MAX_APPEARANCE_ITEMS, MAX_COORD, MAX_HOUSE_LAYERS, MAX_STYLE_LEN, Movement,
};

/// Bumped whenever a message changes shape. The server refuses a client whose version differs,
/// since postcard can't tell an old message from a garbled one.
pub const PROTOCOL_VERSION: u32 = 5;

/// A game can't start with fewer players than this.
pub const MIN_PLAYERS: usize = 4;
/// A lobby holds at most this many players, one per lot in the town.
pub const MAX_PLAYERS: usize = 15;

/// Lobby codes are this many characters from [`CODE_ALPHABET`].
pub const CODE_LENGTH: usize = 6;
/// Letters and digits that are hard to confuse when read aloud or typed (no 0/O, 1/I/L).
pub const CODE_ALPHABET: &str = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/// Chat messages longer than this are refused.
pub const MAX_CHAT_LEN: usize = 300;
/// Last wills longer than this are refused.
pub const MAX_WILL_LEN: usize = 1500;
/// Usernames are 1 to this many characters.
pub const MAX_NAME_LEN: usize = 16;
/// A trial can be started this many times per day before the day ends anyway.
pub const TRIALS_PER_DAY: u8 = 3;
