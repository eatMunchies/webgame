extends GdUnitTestSuite

## The chat box sends: Enter in the box, the Send button beside it, and the
## touch prompt (which fills the box and submits it) all reach the panel. The
## HUD once lost these when the panel moved in the scene, and the chat sent
## nothing on any screen.

const HUD_SCENE := preload("res://scenes/main/hud.tscn")


func chat_panel() -> PanelContainer:
	var hud: Control = auto_free(HUD_SCENE.instantiate())
	add_child(hud)
	return hud.chat_panel


func test_enter_in_the_box_sends() -> void:
	var panel := chat_panel()
	assert_bool(panel.input.text_submitted.is_connected(panel._on_input_text_submitted)).is_true()


func test_the_send_button_sends() -> void:
	var panel := chat_panel()
	assert_bool(panel.send_button.pressed.is_connected(panel._on_send_button_pressed)).is_true()


func test_the_box_does_not_name_the_channel() -> void:
	# The channel (town, jail, mafia, dead) would give a player's role away.
	var panel := chat_panel()
	assert_object(panel.find_child("Channel", true, false)).is_null()
