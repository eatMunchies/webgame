use godot::prelude::*;

mod game_client;
mod practice_fight;
mod state_machine;

struct WebgameExtension;

#[gdextension]
unsafe impl ExtensionLibrary for WebgameExtension {}
