use godot::prelude::*;

mod aspect_flow_container;
mod game_client;
mod state_machine;

struct WebgameExtension;

#[gdextension]
unsafe impl ExtensionLibrary for WebgameExtension {}
