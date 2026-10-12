use godot::prelude::*;

struct WebgameExtension;

#[gdextension]
unsafe impl ExtensionLibrary for WebgameExtension {}
