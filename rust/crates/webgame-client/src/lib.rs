//! The client side of the game, shared by every client: what a player knows, kept up to date
//! from server messages ([`State`]), how each message reads as text, and how a typed line
//! becomes a message ([`parse`]). The terminal client and the Godot extension both use it, so
//! they agree on the rules and say things the same way.
//!
//! Like the protocol, it has no networking or OS dependencies, so it builds for the web.

mod actions;
mod commands;
mod state;

pub use actions::Action;
pub use commands::{Command, HELP, parse};
pub use state::{Choices, State};
