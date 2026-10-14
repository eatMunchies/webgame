use godot::prelude::*;
use godot::{classes::{INode, Node}, obj::{Base, Gd}, prelude::{GodotClass, godot_api}};

/// A generic finite state machine implementation. This can be used for any kind of state machine,
/// such as player movement or game state management.
#[derive(GodotClass)]
#[class(base=Node)]
struct StateMachine {
    base: Base<Node>,

    /// The node the states act on, set by `initialize`. The machine passes it to each state it
    /// changes to, as that state's `context`.
    #[var]
    context: Option<Gd<Node>>,

    /// The state `initialize` enters first.
    #[export]
    initial_state: Option<Gd<State>>,

    #[var(no_set)]
    current_state: Option<Gd<State>>,
}

/// Most transitions `change_state` follows in one call, so states whose `state_enter` hand off to
/// each other in a cycle report an error.
const MAX_CHAINED_TRANSITIONS: usize = 32;

#[godot_api]
impl StateMachine {
    /// Emitted once per `change_state` call, after any hand-offs from `state_enter`, with the state
    /// the machine settled on.
    #[signal]
    fn state_changed(new_state: Gd<State>);

    /// Emitted each time a state is entered, including every hand-off, after its `state_enter` runs.
    /// `previous_state` is null when the machine had no state before.
    #[signal]
    fn state_entered(previous_state: Option<Gd<State>>, new_state: Gd<State>);

    /// Sets the context and enters `initial_state`. Call it from the node the states act on, e.g.
    /// `$StateMachine.initialize(self)` in its `_ready`.
    #[func(gd_self)]
    fn initialize(this: Gd<Self>, context: Gd<Node>) {
        Self::on_initialize(this, context);
    }

    /// What `initialize` does. Scripts extending StateMachine can override it as `_initialize` to
    /// keep a more specific context type, such as a CharacterBody2D. Overrides can't call `super`,
    /// so call `initialize_default(context)` instead to keep the default behavior.
    #[func(virtual, gd_self, rename = _initialize)]
    fn on_initialize(this: Gd<Self>, context: Gd<Node>) {
        Self::initialize_default(this, context);
    }

    /// The default `_initialize`: sets `context` and enters `initial_state`, if there is one.
    #[func(gd_self)]
    fn initialize_default(this: Gd<Self>, context: Gd<Node>) {
        let mut this = this;
        let initial_state = {
            let mut machine = this.bind_mut();
            machine.context = Some(context);
            machine.initial_state.clone()
        };
        if let Some(initial_state) = initial_state {
            this.bind_mut().change_state(initial_state);
        }
    }

    /// Forces the state machine to change to a new state. This will call the exit method of the
    /// current state and the enter method of the new state, recursively until the new state
    /// does not transition to another state in its `state_enter` method.
    #[func]
    fn change_state(&mut self, new_state: Gd<State>) {
        let mut next = Some(new_state);
        let mut transitions = 0;

        while let Some(mut state) = next.take() {
            if transitions == MAX_CHAINED_TRANSITIONS {
                godot_error!(
                    "StateMachine: stopped after {MAX_CHAINED_TRANSITIONS} chained transitions; \
                     is there a cycle? Next state would have been {}",
                    state.get_name()
                );
                break;
            }
            transitions += 1;

            // The guards let the hooks call back into this machine without a double borrow.
            let previous = self.current_state.clone();
            if let Some(previous) = previous.clone() {
                let _reentrant = self.base_mut();
                State::state_exit(previous);
            }

            state.bind_mut().context = self.context.clone();
            self.current_state = Some(state.clone());

            next = {
                let _reentrant = self.base_mut();
                State::state_enter(state.clone())
            };

            self.signals().state_entered().emit(previous.as_ref(), &state);
        }

        if let Some(current_state) = self.current_state.clone() {
            self.signals().state_changed().emit(&current_state);
        }
    }
}

#[godot_api]
impl INode for StateMachine {
    fn init(base: Base<Node>) -> Self {
        StateMachine {
            base,
            context: None,
            initial_state: None,
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

    /// The node this state acts on. Its state machine sets this before entering it.
    #[var]
    context: Option<Gd<Node>>,
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
        State { base, context: None }
    }
}
