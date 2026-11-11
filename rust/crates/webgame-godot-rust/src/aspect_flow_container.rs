use godot::classes::{BoxContainer, IBoxContainer, Viewport};
use godot::prelude::*;

/// A box container that lays its children out in a row on a wide screen and in a column on a tall
/// one. It is a `BoxContainer` whose `vertical` it sets from the screen's aspect ratio (the
/// viewport's visible width over its height), so separation, size flags and stretch ratios work as
/// they do in an HBoxContainer or VBoxContainer. It checks again whenever the viewport resizes,
/// such as when a phone rotates.
///
/// `vertical` is set at runtime, so whatever the inspector shows for it is only how the editor
/// draws the scene.
#[derive(GodotClass)]
#[class(base=BoxContainer)]
struct AspectFlowContainer {
    base: Base<BoxContainer>,

    /// The children go in a column while the screen's width divided by its height is below this,
    /// and in a row otherwise. The default of 1.0 means a column on portrait screens.
    #[export]
    #[var(set = set_aspect_threshold)]
    aspect_threshold: f32,
}

#[godot_api]
impl IBoxContainer for AspectFlowContainer {
    fn init(base: Base<BoxContainer>) -> Self {
        Self {
            base,
            aspect_threshold: 1.0,
        }
    }

    fn enter_tree(&mut self) {
        if let Some(mut viewport) = self.viewport() {
            let callable = self.refresh_callable();
            viewport.connect("size_changed", &callable);
        }
        self.refresh();
    }

    fn exit_tree(&mut self) {
        if let Some(mut viewport) = self.viewport() {
            let callable = self.refresh_callable();
            if viewport.is_connected("size_changed", &callable) {
                viewport.disconnect("size_changed", &callable);
            }
        }
    }
}

#[godot_api]
impl AspectFlowContainer {
    /// Emitted when the children switch between a row and a column, with the new direction.
    #[signal]
    fn flow_changed(vertical: bool);

    #[func]
    fn set_aspect_threshold(&mut self, threshold: f32) {
        self.aspect_threshold = threshold;
        self.refresh();
    }

    /// Sets `vertical` from the screen's current aspect ratio. Runs on its own when the viewport
    /// resizes.
    #[func]
    fn refresh(&mut self) {
        let Some(viewport) = self.viewport() else {
            return;
        };
        let size = viewport.get_visible_rect().size;
        if size.y <= 0.0 {
            return;
        }
        let vertical = size.x / size.y < self.aspect_threshold;
        if vertical != self.base().is_vertical() {
            self.base_mut().set_vertical(vertical);
            self.signals().flow_changed().emit(vertical);
        }
    }
}

impl AspectFlowContainer {
    fn viewport(&self) -> Option<Gd<Viewport>> {
        if self.base().is_inside_tree() {
            self.base().get_viewport()
        } else {
            None
        }
    }

    fn refresh_callable(&self) -> Callable {
        Callable::from_object_method(&self.to_gd(), "refresh")
    }
}
