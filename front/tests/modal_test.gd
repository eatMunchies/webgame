extends GdUnitTestSuite

## The modals (Modal, TextPrompt, RoleCard) share one way to close: Escape,
## or a tap on the backdrop, except for a moment after opening, when a
## phone's second event for the tap that opened it would land there.

func prompt() -> TextPrompt:
	var host: Control = auto_free(Control.new())
	add_child(host)
	host.size = Vector2(320, 180)
	return TextPrompt.create(host)


func tap() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func test_confirming_calls_back_with_the_text() -> void:
	var made := prompt()
	var got := []
	made.ask("Whisper to 2 Bram", "hello", func(text: String) -> void: got.append(text))
	made._finish()
	assert_array(got).contains_exactly(["hello"])
	assert_bool(made.visible).is_false()


func test_the_tap_that_opened_it_does_not_close_it() -> void:
	var made := prompt()
	made.ask("Chat", "", func(_text: String) -> void: pass)
	made._on_backdrop_input(tap())
	assert_bool(made.visible).is_true()


func test_a_later_tap_outside_closes_it_without_calling_back() -> void:
	var made := prompt()
	var got := []
	made.ask("Chat", "hi", func(text: String) -> void: got.append(text))
	made._opened_msec -= Modal.BACKDROP_GRACE_MSEC
	made._on_backdrop_input(tap())
	assert_bool(made.visible).is_false()
	assert_array(got).is_empty()


func test_the_role_card_shows_the_faction_only_on_its_seal() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var card := RoleCard.create(host)
	card.open_with({"spectator": false, "name": "Mafioso", "faction": "Mafia",
			"category": "Mafia Killing", "ability": "Kill.", "goal": "Win.", "target": "", "team": []})
	var seals := card.find_children("*", "WaxSeal", true, false)
	assert_int(seals.size()).is_equal(1)
	assert_str((seals[0] as WaxSeal).letter).is_equal("M")
