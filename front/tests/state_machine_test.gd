extends GdUnitTestSuite


## A state that records its hooks in a shared list. Set `on_enter` or `on_process` to a callable
## returning the state to hand off to, or null to stay.
class RecordingState extends State:
	var events: Array
	var on_enter := Callable()
	var on_process := Callable()
	var deltas: Array[float] = []
	var context_on_enter: Node

	func _init(state_name: String, shared_events: Array) -> void:
		name = state_name
		events = shared_events

	func _state_enter() -> State:
		events.append("enter " + name)
		context_on_enter = context
		return on_enter.call() if on_enter.is_valid() else null

	func _state_exit() -> void:
		events.append("exit " + name)

	func _state_process(delta: float) -> State:
		events.append("process " + name)
		deltas.append(delta)
		return on_process.call() if on_process.is_valid() else null


## A machine that keeps a typed context, the way a character's state machine would.
class TypedMachine extends StateMachine:
	var body: Node2D

	func _initialize(new_context: Node) -> void:
		body = new_context as Node2D
		initialize_default(new_context)


var events: Array
var machine: StateMachine


func before_test() -> void:
	events = []
	machine = auto_free(StateMachine.new())
	machine.context = self
	add_child(machine)


func add_state(state_name: String, parent: Node = machine) -> RecordingState:
	var state := RecordingState.new(state_name, events)
	parent.add_child(state)
	return state


func test_starts_without_a_state() -> void:
	assert_object(machine.current_state).is_null()


func test_change_state_enters_the_new_state() -> void:
	var a := add_state("A")
	machine.change_state(a)
	assert_array(events).contains_exactly(["enter A"])
	assert_object(machine.current_state).is_same(a)


func test_change_state_exits_the_previous_state_first() -> void:
	var a := add_state("A")
	var b := add_state("B")
	machine.change_state(a)
	machine.change_state(b)
	assert_array(events).contains_exactly(["enter A", "exit A", "enter B"])
	assert_object(machine.current_state).is_same(b)


func test_enter_can_hand_off_to_another_state() -> void:
	var a := add_state("A")
	var b := add_state("B")
	var c := add_state("C")
	a.on_enter = func() -> State: return b
	b.on_enter = func() -> State: return c
	machine.change_state(a)
	assert_array(events).contains_exactly(["enter A", "exit A", "enter B", "exit B", "enter C"])
	assert_object(machine.current_state).is_same(c)


func test_hand_off_cycle_stops_with_an_error() -> void:
	var a := add_state("A")
	var b := add_state("B")
	a.on_enter = func() -> State: return b
	b.on_enter = func() -> State: return a
	await assert_error(func() -> void: machine.change_state(a)).is_push_error(
			"StateMachine: stopped after 32 chained transitions; is there a cycle? Next state would have been A")
	var enters := events.filter(func(event: String) -> bool: return event.begins_with("enter"))
	assert_int(enters.size()).is_equal(32)


func test_process_runs_the_current_state_with_a_fixed_delta() -> void:
	var a := add_state("A")
	machine.change_state(a)
	for i in 3:
		await get_tree().process_frame
	assert_int(a.deltas.size()).is_greater_equal(2)
	for delta in a.deltas:
		assert_float(delta).is_equal_approx(1.0 / 60.0, 0.000001)


func test_process_can_return_the_next_state() -> void:
	var a := add_state("A")
	var b := add_state("B")
	a.on_process = func() -> State: return b
	machine.change_state(a)
	events.clear()
	for i in 2:
		await get_tree().process_frame
	assert_array(events.slice(0, 3)).contains_exactly(["process A", "exit A", "enter B"])
	assert_object(machine.current_state).is_same(b)


func test_hooks_can_call_back_into_the_machine() -> void:
	var a := add_state("A")
	var b := add_state("B")
	var seen_context: Array = []
	a.on_enter = func() -> State:
		seen_context.append(machine.context)
		machine.change_state(b)
		return null
	machine.change_state(a)
	assert_array(seen_context).contains_exactly([self])
	assert_array(events).contains_exactly(["enter A", "exit A", "enter B"])
	assert_object(machine.current_state).is_same(b)


func test_entered_states_get_the_machine_context_before_entering() -> void:
	var a := add_state("A")
	var b := add_state("B")
	a.on_enter = func() -> State: return b
	machine.change_state(a)
	assert_object(a.context_on_enter).is_same(self)
	assert_object(b.context_on_enter).is_same(self)
	assert_object(b.context).is_same(self)


func test_state_entered_is_emitted_for_every_hand_off() -> void:
	var a := add_state("A")
	var b := add_state("B")
	a.on_enter = func() -> State: return b
	var entered := []
	machine.state_entered.connect(func(previous: State, new: State) -> void: entered.append([previous, new]))
	machine.change_state(a)
	assert_array(entered).contains_exactly([[null, a], [a, b]])


func test_state_changed_is_emitted_once_with_the_settled_state() -> void:
	var a := add_state("A")
	var b := add_state("B")
	var c := add_state("C")
	a.on_enter = func() -> State: return b
	b.on_enter = func() -> State: return c
	var changed := []
	machine.state_changed.connect(func(new: State) -> void: changed.append(new))
	machine.change_state(a)
	assert_array(changed).contains_exactly([c])
	machine.change_state(a)
	assert_array(changed).contains_exactly([c, c])


func test_signal_handlers_can_call_back_into_the_machine() -> void:
	var a := add_state("A")
	var b := add_state("B")
	var seen := []
	machine.state_entered.connect(func(_previous: State, _new: State) -> void:
		seen.append(machine.current_state))
	machine.state_changed.connect(func(new: State) -> void:
		if new == a:
			machine.change_state(b))
	machine.change_state(a)
	assert_array(seen).contains_exactly([a, b])
	assert_object(machine.current_state).is_same(b)


func test_initialize_sets_the_context_and_enters_the_initial_state() -> void:
	var body: Node2D = auto_free(Node2D.new())
	var a := add_state("A")
	machine.initial_state = a
	machine.initialize(body)
	assert_object(machine.context).is_same(body)
	assert_object(machine.current_state).is_same(a)
	assert_object(a.context_on_enter).is_same(body)
	assert_array(events).contains_exactly(["enter A"])


func test_initialize_without_an_initial_state_only_sets_the_context() -> void:
	var body: Node2D = auto_free(Node2D.new())
	add_state("A")
	machine.initialize(body)
	assert_object(machine.context).is_same(body)
	assert_object(machine.current_state).is_null()
	assert_array(events).is_empty()


func test_initialize_can_be_overridden_by_scripts() -> void:
	var typed: TypedMachine = auto_free(TypedMachine.new())
	add_child(typed)
	var a := add_state("A", typed)
	typed.initial_state = a
	var body: Node2D = auto_free(Node2D.new())
	typed.initialize(body)
	assert_object(typed.body).is_same(body)
	assert_object(typed.context).is_same(body)
	assert_object(typed.current_state).is_same(a)


func test_initial_state_is_exported_as_a_state_picker() -> void:
	var properties := machine.get_property_list().filter(
			func(property: Dictionary) -> bool: return property.name == "initial_state")
	assert_int(properties.size()).is_equal(1)
	assert_bool(properties[0].usage & PROPERTY_USAGE_EDITOR != 0).is_true()
	assert_int(properties[0].hint).is_equal(PROPERTY_HINT_NODE_TYPE)
	assert_str(properties[0].hint_string).is_equal("State")
