extends GdUnitTestSuite

const OVERLAY_SCENE := preload("res://scenes/main/minigame_overlay.tscn")

var overlay: MinigameOverlay
## Everything the overlay reported, as [signal name, argument].
var reported: Array


func before_test() -> void:
	reported = []
	overlay = auto_free(OVERLAY_SCENE.instantiate())
	add_child(overlay)
	overlay.check_pressed.connect(func(hit: bool) -> void: reported.append(["press", hit]))
	overlay.fight_move.connect(func(move: String) -> void: reported.append(["move", move]))
	overlay.guard_changed.connect(func(up: bool) -> void: reported.append(["guard", up]))


func key(keycode: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
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


## Presses the wheel with the needle in the zone or out of it.
func press(hit: bool) -> void:
	overlay._wheel.angle = overlay._wheel.zone_start + (0.05 if hit else -0.2)
	overlay.press()


func test_a_skill_check_reports_each_press_then_waits_for_the_server() -> void:
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000, "result": "", "presses": 5})
	assert_bool(overlay.visible).is_true()
	overlay._wheel.angle = overlay._wheel.zone_start + 0.05
	key(KEY_SPACE)
	for hit in [false, true, true, false]:
		press(hit)
	assert_array(reported).is_equal([
		["press", true], ["press", false], ["press", true], ["press", true], ["press", false],
	])
	assert_bool(overlay.rolling()).is_true()
	assert_str(overlay.result_label.text).contains("3/5 hits").contains("rolling")
	assert_bool(overlay.practicing()).is_false()
	press(true)
	assert_array(reported).has_size(5)
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 4000, "result": "failed"})
	assert_str(overlay.result_label.text).contains("Failed").contains("3/5")
	assert_bool(overlay.practicing()).is_true()
	press(true)
	assert_array(reported).has_size(5)
	assert_int(overlay.score).is_equal(1)


func test_a_skill_check_takes_as_many_presses_as_the_server_says() -> void:
	overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 5000, "presses": 2})
	press(false)
	assert_bool(overlay.rolling()).is_false()
	press(false)
	assert_bool(overlay.rolling()).is_true()
	assert_array(reported).is_equal([["press", false], ["press", false]])


func test_practice_counts_a_streak_and_reports_nothing() -> void:
	overlay.show_minigame({"kind": "passive", "ends_in_ms": 5000})
	for i in 2:
		overlay._wheel.angle = overlay._wheel.zone_start + 0.05
		overlay.press()
	assert_int(overlay.score).is_equal(2)
	overlay._wheel.angle = overlay._wheel.zone_start - 0.2
	overlay.press()
	assert_int(overlay.score).is_equal(0)
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
	key(KEY_J)
	assert_array(reported).is_equal([["move", "strike"]])
