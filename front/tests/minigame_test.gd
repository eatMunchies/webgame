extends GdUnitTestSuite

const OVERLAY_SCENE := preload("res://scenes/main/minigame_overlay.tscn")

var overlay: MinigameOverlay
## Everything the overlay reported, as [signal name, arguments...], with a
## skill check's chance as a whole percent, as the server gets it.
var reported: Array


func before_test() -> void:
	reported = []
	overlay = auto_free(OVERLAY_SCENE.instantiate())
	# The wheel stands in for every kind; typing_check_test covers the rest.
	overlay.skill_checks = [load("res://skill_checks/wheel.tres")]
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
	assert_array(ids).contains_exactly_in_any_order([&"wheel", &"typing"])


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


func test_fights_send_moves_until_decided() -> void:
	overlay.show_minigame({"kind": "fight", "attacking": true, "ends_in_ms": 8000})
	assert_str(overlay.title.text).contains("You attack")
	key(KEY_J)
	key(KEY_K)
	key(KEY_SPACE)
	key(KEY_SPACE, false)
	assert_array(reported).is_equal([
		["move", "strike"], ["move", "grab"], ["guard", true], ["guard", false],
	])
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


func test_an_empty_minigame_hides_the_overlay_and_drops_the_guard() -> void:
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	key(KEY_L)
	overlay.show_minigame({})
	assert_bool(overlay.visible).is_false()
	assert_array(reported).is_equal([["guard", true], ["guard", false]])


func test_a_second_fight_in_a_row_starts_fresh() -> void:
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000})
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 2000, "result": "lost"})
	overlay.show_minigame({"kind": "fight", "ends_in_ms": 8000, "result": ""})
	assert_str(overlay.result).is_equal("")
	assert_object(overlay.check).is_null()
	key(KEY_J)
	assert_array(reported).is_equal([["move", "strike"]])
