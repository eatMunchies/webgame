extends GdUnitTestSuite

## Leaving the town asks again inline: one tap only arms the leave icon,
## and the made-up click a phone sends with a tap can't be the second.

const CLOCK := preload("res://scripts/hud/phase_clock.gd")
const MODEL := {"title": "Day 2", "stage": "Discussion", "seconds": 42, "night": false,
		"code": "WTCH92", "reconnecting": false}


func clock() -> Node:
	var made: Node = auto_free(CLOCK.new())
	made.preview = true
	add_child(made)
	return made


func test_one_tap_asks_again() -> void:
	var made := clock()
	made._on_leave_pressed()
	made.show_model(MODEL)
	assert_str(made._code.text).is_equal("Tap again to leave")
	assert_bool(made._town.visible).is_false()


func test_the_tap_echo_does_not_confirm() -> void:
	var made := clock()
	made._on_leave_pressed()
	# The emulated click right after the touch: still armed, not left.
	made._on_leave_pressed()
	assert_int(made._leave_until).is_greater(0)


func test_it_goes_back_to_the_code() -> void:
	var made := clock()
	made._on_leave_pressed()
	made._leave_until = 0
	made.show_model(MODEL)
	assert_str(made._code.text).is_equal("WTCH92")
