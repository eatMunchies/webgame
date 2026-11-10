extends GdUnitTestSuite

const OVERLAY_SCENE := preload("res://scenes/main/minigame_overlay.tscn")

var overlay: MinigameOverlay
## Everything the overlay reported, as [signal name, arguments...], with a
## skill check's chance as a whole percent, as the server gets it.
var reported: Array


func before_test() -> void:
	reported = []
	overlay = auto_free(OVERLAY_SCENE.instantiate())
	# The wheel stands in for every kind, practice too; typing_check_test and
	# the Card Memory tests cover the rest.
	overlay.skill_checks = [load("res://skill_checks/wheel.tres")]
	overlay.practice_checks = overlay.skill_checks
	overlay.intro_seconds = 0.0
	add_child(overlay)
	overlay.check_reported.connect(func(chance: float, done: bool) -> void:
		reported.append(["check", roundi(chance * 100), done]))
	overlay.fight_move.connect(func(move: String) -> void: reported.append(["move", move]))
	overlay.guard_changed.connect(func(up: bool) -> void: reported.append(["guard", up]))


## Sends a key to the overlay's skill check, if it has one, and then to the
## overlay unless the check took it, the way the viewport would.
func key(keycode: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	if overlay.check != null:
		overlay.check._unhandled_key_input(event)
		if get_viewport().is_input_handled():
			return
	overlay._unhandled_key_input(event)


func fighter(hp: int, move := "", lands_in_ms := 0) -> Dictionary:
	return {
		"hp": hp, "guarding": move == "", "move": move, "windup_ms": 400,
		"lands_in_ms": lands_in_ms, "staggered_ms": 0,
	}


func test_the_wheel_hits_only_inside_the_zone() -> void:
	var wheel := TimingWheel.new(7)
	assert_bool(wheel.in_zone()).override_failure_message("a new zone starts ahead of the needle").is_false()
	wheel.angle = wheel.zone_start + TimingWheel.ZONE / 2
	assert_bool(wheel.in_zone()).is_true()
	wheel.angle = wheel.zone_start - 0.05
	assert_bool(wheel.in_zone()).is_false()
	# The zone can wrap past 12 o'clock.
	wheel.zone_start = TAU - TimingWheel.ZONE / 2
	wheel.angle = 0.01
	assert_bool(wheel.in_zone()).is_true()


func test_the_wheel_turns_and_wraps() -> void:
	var wheel := TimingWheel.new(1)
	wheel.advance(0.5)
	assert_float(wheel.angle).is_equal_approx(TimingWheel.SPEED * 0.5, 0.0001)
	wheel.advance(1.0)
	assert_float(wheel.angle).is_equal_approx(fposmod(TimingWheel.SPEED * 1.5, TAU), 0.0001)


func test_a_wheel_check_takes_its_tuning_from_its_def() -> void:
	var def: WheelCheckDef = load("res://skill_checks/wheel.tres").duplicate()
	def.presses = 2
	def.zone_degrees = 90.0
	def.turns_per_second = 1.0
	overlay.skill_checks = [def]
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000})
	var wheel: WheelCheck = overlay.check
	assert_float(wheel.wheel.zone).is_equal_approx(PI / 2, 0.0001)
	assert_float(wheel.wheel.speed).is_equal_approx(TAU, 0.0001)
	press(true)
	press(false)
	assert_array(reported).is_equal([["check", 50, false], ["check", 50, true]])


func test_the_overlay_offers_every_kind() -> void:
	var listed: Array[SkillCheckDef] = auto_free(OVERLAY_SCENE.instantiate()).skill_checks
	var ids := listed.map(func(def: SkillCheckDef) -> StringName: return def.id)
	assert_array(ids).contains_exactly_in_any_order(
			[&"wheel", &"typing", &"flappy", &"golf", &"fruit", &"blackjack"])
	# Practice is random too, but the wheel only ever counts and Card Memory
	# never does.
	listed = auto_free(OVERLAY_SCENE.instantiate()).practice_checks
	ids = listed.map(func(def: SkillCheckDef) -> StringName: return def.id)
	assert_array(ids).contains_exactly_in_any_order(
			[&"typing", &"memory", &"flappy", &"golf", &"fruit", &"blackjack"])


func test_skill_checks_are_picked_by_weight() -> void:
	var never := SkillCheckDef.new()
	never.weight = 0.0
	var always := SkillCheckDef.new()
	var defs: Array[SkillCheckDef] = [never, always]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 20:
		assert_object(SkillCheckDef.pick(defs, rng)).is_same(always)
	assert_object(SkillCheckDef.pick([] as Array[SkillCheckDef], rng)).is_null()


## Presses the wheel check with the needle in the zone or out of it.
func press(hit: bool) -> void:
	var wheel: WheelCheck = overlay.check
	wheel.wheel.angle = wheel.wheel.zone_start + (0.05 if hit else -0.2)
	wheel.press()


func test_a_wheel_check_reports_each_press_then_waits_for_the_server() -> void:
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000, "result": ""})
	assert_bool(overlay.visible).is_true()
	assert_object(overlay.check).is_instanceof(WheelCheck)
	assert_str(overlay.check.def.id).is_equal("wheel")
	press(true)
	for hit in [false, true, true, false]:
		press(hit)
	assert_array(reported).is_equal([
		["check", 20, false], ["check", 20, false], ["check", 40, false],
		["check", 60, false], ["check", 60, true],
	])
	assert_bool(overlay.rolling()).is_true()
	assert_str(overlay.result_label.text).contains("3/5 hits").contains("rolling")
	assert_bool(overlay.practicing()).is_false()
	press(true)
	assert_array(reported).has_size(5)
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 4000, "result": "failed"})
	assert_str(overlay.result_label.text).contains("Failed").contains("3/5")
	assert_bool(overlay.check.practice).is_true()
	press(true)
	assert_array(reported).has_size(5)
	assert_int(overlay.check.streak).is_equal(1)
	assert_str(overlay.result_label.text).contains("Streak 1")


func test_space_presses_the_wheel() -> void:
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000})
	var wheel: WheelCheck = overlay.check
	wheel.wheel.angle = wheel.wheel.zone_start + 0.05
	key(KEY_SPACE)
	key(KEY_SPACE, false)
	assert_array(reported).is_equal([["check", 20, false]])


func test_practice_counts_a_streak_and_reports_nothing() -> void:
	overlay.show_minigame({"kind": "passive", "ends_in_ms": 5000})
	assert_bool(overlay.check.practice).is_true()
	press(true)
	press(true)
	assert_int(overlay.check.streak).is_equal(2)
	press(false)
	assert_int(overlay.check.streak).is_equal(0)
	assert_array(reported).is_empty()


func test_any_skill_check_scene_reports_through_the_overlay() -> void:
	var fake := Control.new()
	fake.set_script(preload("res://tests/fake_check.gd"))
	var def := SkillCheckDef.new()
	def.title = "Fake check"
	def.scene = PackedScene.new()
	def.scene.pack(fake)
	fake.free()
	overlay.skill_checks = [def]
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000})
	assert_object(overlay.check.get_parent()).is_same(overlay.canvas)
	assert_object(overlay.check.def).is_same(def)
	assert_str(overlay.title.text).is_equal("Fake check")
	overlay.check.report(1.5)
	overlay.check.report(0.7, true)
	overlay.check.report(0.1, true)
	assert_array(reported).is_equal([["check", 100, false], ["check", 70, true]])
	overlay.check.changed.emit()
	assert_str(overlay.result_label.text).contains("70%").contains("rolling")


func test_a_decided_fight_turns_into_practice() -> void:
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	assert_object(overlay.check).is_null()
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 3000, "result": "lost"})
	assert_bool(overlay.check.practice).is_true()
	press(true)
	assert_array(reported).is_empty()


## Two cards on the board with the same face, and one with a different face.
func pair_and_odd(game: MemoryGame) -> Array[int]:
	var first := 0
	var second := game.faces.find(game.faces[first], first + 1)
	var odd := game.faces.find((game.faces[first] + 1) % 8)
	return [first, second, odd]


func test_a_memory_board_has_eight_pairs_and_a_seed_deals_the_same() -> void:
	var game := MemoryGame.new(3)
	for face in 8:
		assert_int(game.faces.count(face)).is_equal(2)
	assert_array(MemoryGame.new(3).faces).is_equal(game.faces)


func test_memory_cards_cant_be_turned_during_the_peek() -> void:
	var game := MemoryGame.new(1)
	assert_bool(game.face_up(5)).is_true()
	assert_str(game.pick(5)).is_equal("")
	game.advance(MemoryGame.PEEK_SECONDS)
	assert_bool(game.face_up(5)).is_false()
	assert_str(game.pick(5)).is_equal("turned")
	assert_bool(game.face_up(5)).is_true()


func test_memory_pairs_stay_up_and_misses_turn_back() -> void:
	var game := MemoryGame.new(2)
	game.advance(MemoryGame.PEEK_SECONDS)
	var cards := pair_and_odd(game)
	assert_str(game.pick(cards[0])).is_equal("turned")
	assert_str(game.pick(cards[2])).is_equal("miss")
	assert_bool(game.missed()).is_true()
	game.advance(MemoryGame.MISS_SECONDS)
	assert_bool(game.face_up(cards[0])).is_false()
	assert_str(game.pick(cards[0])).is_equal("turned")
	assert_str(game.pick(cards[0])).override_failure_message("the same card twice is no try").is_equal("")
	assert_str(game.pick(cards[1])).is_equal("match")
	assert_bool(game.matched[cards[0]] and game.matched[cards[1]]).is_true()
	assert_int(game.pairs_found).is_equal(1)


func test_picking_during_a_miss_turns_the_miss_back_at_once() -> void:
	var game := MemoryGame.new(4)
	game.advance(MemoryGame.PEEK_SECONDS)
	var cards := pair_and_odd(game)
	game.pick(cards[0])
	game.pick(cards[2])
	assert_str(game.pick(cards[1])).is_equal("turned")
	assert_array(game.turned).is_equal([cards[1]])


func test_clearing_a_board_deals_a_new_one() -> void:
	var game := MemoryGame.new(5)
	game.advance(MemoryGame.PEEK_SECONDS)
	for face in 8:
		var first := game.faces.find(face)
		game.pick(first)
		game.pick(game.faces.find(face, first + 1))
	assert_bool(game.cleared()).is_true()
	assert_int(game.boards_cleared).is_equal(1)
	game.advance(MemoryGame.CLEARED_SECONDS)
	assert_bool(game.cleared()).is_false()
	assert_bool(game.peeking()).is_true()
	assert_int(game.pairs_found).is_equal(8)


func test_the_memory_cursor_stops_at_the_edges() -> void:
	var game := MemoryGame.new(6)
	game.move_cursor(Vector2i.LEFT)
	assert_int(game.cursor).is_equal(0)
	game.move_cursor(Vector2i.RIGHT)
	game.move_cursor(Vector2i.DOWN)
	assert_int(game.cursor).is_equal(5)
	for i in 5:
		game.move_cursor(Vector2i(1, 1))
	assert_int(game.cursor).is_equal(15)


## Makes practice always Card Memory, and starts a passive game.
func start_card_memory() -> MemoryCheck:
	overlay.practice_checks = [load("res://skill_checks/memory.tres")]
	overlay.show_minigame({"kind": "passive", "ends_in_ms": 5000})
	return overlay.check


func test_card_memory_is_played_by_keys_and_taps_and_reports_nothing() -> void:
	var cards_check := start_card_memory()
	# A real size, since a headless test never lays the overlay out.
	cards_check.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cards_check.size = Vector2(120, 120)
	cards_check.game = MemoryGame.new(7)
	cards_check.game.advance(MemoryGame.PEEK_SECONDS)
	var cards := pair_and_odd(cards_check.game)
	cards_check.game.cursor = cards[0]
	key(KEY_SPACE)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = cards_check.card_rect(cards[1]).get_center()
	cards_check._gui_input(tap)
	assert_int(cards_check.game.pairs_found).is_equal(1)
	key(KEY_RIGHT)
	assert_int(cards_check.game.cursor).is_equal(cards[1] + 1 if cards[1] % 4 < 3 else cards[1])
	assert_array(reported).is_empty()


func test_card_memory_shows_just_its_name() -> void:
	start_card_memory()
	assert_str(overlay.title.text).is_equal("Card Memory")
	assert_bool(overlay.time_left.visible).is_false()
	assert_str(overlay.result_label.text).is_empty()


func test_the_practice_game_carries_on_from_stage_to_stage() -> void:
	var practice := start_card_memory()
	var board := practice.game
	# The stage ends, then the next stage's practice game starts.
	overlay.show_minigame({})
	overlay.show_minigame({"kind": "passive", "ends_in_ms": 5000})
	assert_object(overlay.check).is_same(practice)
	assert_object(overlay.check.game).is_same(board)


func test_a_skill_check_or_fight_ends_the_practice_game() -> void:
	for interruption in ["skill_check", "fight"]:
		var practice := start_card_memory()
		overlay.show_minigame({})
		overlay.show_minigame({"kind": interruption, "ends_in_ms": 5000})
		overlay.show_minigame({})
		await await_idle_frame()
		assert_bool(is_instance_valid(practice)).is_false()
		overlay.show_minigame({"kind": "passive", "ends_in_ms": 5000})
		assert_object(overlay.check).is_not_same(practice)
		assert_bool(overlay.check is MemoryCheck).is_true()
		overlay.show_minigame({})


func test_the_practice_after_a_fight_is_a_different_game() -> void:
	overlay.practice_checks = [load("res://skill_checks/wheel.tres"), load("res://skill_checks/memory.tres")]
	for i in 20:
		overlay.show_minigame({"kind": "passive", "ends_in_ms": 8000})
		var before: String = overlay.check.title()
		overlay.show_minigame({})
		overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
		overlay.show_minigame({"kind": "fight", "ends_in_ms": 5000, "result": "won"})
		assert_str(overlay.check.title()).is_not_equal(before)
		overlay.show_minigame({})


func test_fights_send_moves_until_decided() -> void:
	overlay.show_minigame({"kind": "fight", "attacking": true, "ends_in_ms": 8000})
	assert_str(overlay.title.text).is_equal("Fight")
	# A fight runs until a knockout, so it shows no clock.
	assert_bool(overlay.time_left.visible).is_false()
	key(KEY_J)
	key(KEY_K)
	key(KEY_SPACE)
	# A guard is a tap: letting go sends nothing.
	key(KEY_SPACE, false)
	assert_array(reported).is_equal([["move", "strike"], ["move", "grab"], ["guard", true]])
	reported.clear()
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 3000, "result": "won", "rolled": true})
	key(KEY_J)
	key(KEY_SPACE)
	assert_array(reported).is_empty()
	assert_str(overlay.result_label.text).contains("won").contains("rolled")


func test_a_fight_is_drawn_from_its_source_and_flashes_hits() -> void:
	# Lambdas capture locals by value, so the view sits in a shared dictionary.
	var source := {"view": {"you": fighter(3), "opponent": fighter(3, "strike", 200), "max_hp": 3}}
	overlay.fight_source = func() -> Dictionary: return source["view"]
	overlay.show_minigame({"kind": "fight", "attacking": false, "ends_in_ms": 8000})
	await get_tree().process_frame
	assert_dict(overlay.fight).is_equal(source["view"])
	source["view"] = {"you": fighter(2), "opponent": fighter(3), "max_hp": 3}
	await get_tree().process_frame
	assert_float(overlay._hit_flash["you"]).is_greater(0.0)
	assert_bool(overlay.fight_buttons.visible).is_true()


func test_an_empty_minigame_hides_the_overlay() -> void:
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	key(KEY_L)
	overlay.show_minigame({})
	assert_bool(overlay.visible).is_false()
	assert_array(reported).is_equal([["guard", true]])


func test_a_press_while_busy_waits_until_the_fighter_is_free() -> void:
	var source := {"view": {"you": fighter(3, "strike", 300), "opponent": fighter(3), "max_hp": 3}}
	overlay.fight_source = func() -> Dictionary: return source["view"]
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay._process(0.0)
	overlay.grab()
	assert_array(reported).is_empty()
	source["view"] = {"you": fighter(3), "opponent": fighter(3), "max_hp": 3}
	overlay._process(0.0)
	assert_array(reported).is_equal([["move", "grab"]])


func test_a_guard_pressed_while_cooling_down_waits_and_the_button_greys() -> void:
	var cooling := fighter(3)
	cooling["guarding"] = false
	cooling["guard_cooldown_ms"] = 300
	var source := {"view": {"you": cooling, "opponent": fighter(3), "max_hp": 3}}
	overlay.fight_source = func() -> Dictionary: return source["view"]
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay._process(0.0)
	assert_bool(overlay.guard_button.disabled).is_true()
	assert_bool(overlay.time_left.visible).override_failure_message("a fight has no clock").is_false()
	overlay.guard()
	assert_array(reported).is_empty()
	var ready := fighter(3)
	ready["guard_cooldown_ms"] = 0
	source["view"] = {"you": ready, "opponent": fighter(3), "max_hp": 3}
	overlay._process(0.0)
	assert_array(reported).is_equal([["guard", true]])
	assert_bool(overlay.guard_button.disabled).is_false()


func test_a_blocked_strike_pops_up_over_the_guard() -> void:
	var dazed := fighter(3)
	dazed["staggered_ms"] = 600
	var source := {"view": {"you": fighter(3), "opponent": fighter(3, "strike", 50), "max_hp": 3}}
	overlay.fight_source = func() -> Dictionary: return source["view"]
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay._process(0.0)
	source["view"] = {"you": fighter(3), "opponent": dazed, "max_hp": 3}
	overlay._process(0.0)
	assert_array(overlay._popups.map(func(p: Dictionary) -> Array: return [p["text"], p["side"]])) \
			.is_equal([["BLOCKED!", "you"]])


func test_a_second_fight_in_a_row_starts_fresh() -> void:
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 2000, "result": "lost"})
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000, "result": ""})
	assert_str(overlay.result).is_equal("")
	assert_object(overlay.check).is_null()
	key(KEY_J)
	assert_array(reported).is_equal([["move", "strike"]])


func test_a_check_that_counts_waits_out_its_countdown() -> void:
	overlay.intro_seconds = 3.0
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 8000})
	assert_bool(overlay.in_intro()).is_true()
	assert_bool(overlay.check.visible).is_false()
	assert_int(overlay.check.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	overlay._intro_ends_msec = 0
	overlay._process(0.0)
	assert_bool(overlay.in_intro()).is_false()
	assert_bool(overlay.check.visible).is_true()


func test_fight_moves_in_the_countdown_are_dropped() -> void:
	overlay.intro_seconds = 3.0
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay.strike()
	overlay.guard()
	assert_array(reported).is_empty()
	overlay._intro_ends_msec = 0
	overlay._process(0.0)
	overlay.strike()
	assert_array(reported).is_equal([["move", "strike"]])


func test_practice_has_no_countdown() -> void:
	overlay.intro_seconds = 3.0
	overlay.show_minigame({"kind": "passive", "ends_in_ms": 8000})
	assert_bool(overlay.in_intro()).is_false()
	assert_bool(overlay.check.visible).is_true()
