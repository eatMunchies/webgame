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


func test_a_speakers_number_is_left_to_their_badge() -> void:
	var panel := chat_panel()
	panel.log_view.clear()
	panel.show_lines([{"text": "Bram (2): I was home (all night).", "kind": "chat", "lot": 1}])
	assert_str(panel.log_view.get_parsed_text().strip_edges()).is_equal("Bram: I was home (all night).")


func test_the_machine_speaks_after_a_prompt() -> void:
	var panel := chat_panel()
	panel.log_view.clear()
	panel.show_lines([{"text": "Connected as Ada.", "kind": "system", "lot": -1}])
	assert_str(panel.log_view.get_parsed_text().strip_edges()).is_equal("> Connected as Ada.")
