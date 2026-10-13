use godot::prelude::*;
use godot::{classes::{INode, Node}, obj::{Base, Gd}, prelude::{GodotClass, godot_api}};

/// A generic finite state machine implementation. This can be used for any kind of state machine,
/// such as player movement or game state management.
#[derive(GodotClass)]
#[class(base=Node)]
struct StateMachine {
    base: Base<Node>,
    #[export]
    context: OnEditor<Gd<Node>>,
    current_state: Option<Gd<State>>,
}

/// Most transitions `change_state` follows in one call, so states whose `state_enter` hand off to
/// each other in a cycle report an error.
const MAX_CHAINED_TRANSITIONS: usize = 32;

#[godot_api]
impl StateMachine {
    /// Forces the state machine to change to a new state. This will call the exit method of the
    /// current state and the enter method of the new state, recursively until the new state
    /// does not transition to another state in its `state_enter` method.
    fn change_state(&mut self, new_state: Gd<State>) {
        let mut next = Some(new_state);

        for _ in 0..MAX_CHAINED_TRANSITIONS {
            let Some(state) = next else {
                return;
            };

            // The guards let the hooks call back into this machine without a double borrow.
            if let Some(previous) = self.current_state.clone() {
                let _reentrant = self.base_mut();
                State::state_exit(previous);
            }

            self.current_state = Some(state.clone());

            next = {
                let _reentrant = self.base_mut();
                State::state_enter(state)
            };
        }

        if let Some(state) = next {
            godot_error!(
                "StateMachine: stopped after {MAX_CHAINED_TRANSITIONS} chained transitions; \
                 is there a cycle? Next state would have been {}",
                state.get_name()
            );
        }
    }
}

#[godot_api]
impl INode for StateMachine {
    fn init(base: Base<Node>) -> Self {
        StateMachine {
            base,
            context: OnEditor::default(),
            current_state: None,
        }
    }

    fn ready(&mut self) {

    }

    fn process(&mut self, delta: f64) {
        let Some(state) = self.current_state.clone() else {
            return;
        };

        let next = {
            let _reentrant = self.base_mut();
            State::state_process(state, delta)
        };

        if let Some(next) = next {
            self.change_state(next);
        }
    }
}

#[derive(GodotClass)]
#[class(base=Node)]
struct State {
    base: Base<Node>,
}

#[godot_api]
impl State {
    #[func(virtual, gd_self)]
    fn state_enter(_this: Gd<Self>) -> Option<Gd<State>> {
        None
    }

    #[func(virtual, gd_self)]
    fn state_process(_this: Gd<Self>, _delta: f64) -> Option<Gd<State>> {
        None
    }

    #[func(virtual, gd_self)]
    fn state_physics_process(_this: Gd<Self>, _delta: f64) -> Option<Gd<State>> {
        None
    }

    #[func(virtual, gd_self)]
    fn state_unhandled_input(_this: Gd<Self>, _delta: f64) -> Option<Gd<State>> {
        None
    }

    #[func(virtual, gd_self)]
    fn state_exit(_this: Gd<Self>) { }
}

#[godot_api]
impl INode for State {
    fn init(base: Base<Node>) -> Self {
        State { base }
    }
}
