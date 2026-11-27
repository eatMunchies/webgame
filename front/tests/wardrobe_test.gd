extends GdUnitTestSuite

## The wardrobe's tiles and swatches, as the customizer shows them.

const CUSTOMIZER_SCENE := preload("res://scenes/main/customizer.tscn")


func wardrobe() -> Wardrobe:
	var screen: Wardrobe = auto_free(CUSTOMIZER_SCENE.instantiate())
	add_child(screen)
	return screen


func test_tiles_pass_touches_on_so_their_rows_can_scroll() -> void:
	# A button stops touches by default, and then a phone's sideways rows only
	# scroll from the gaps between tiles.
	var screen := wardrobe()
	var buttons: Array = screen._swatches.duplicate()
	buttons.append(screen._custom_skin)
	for picker: String in screen._tiles:
		buttons.append_array(screen._tiles[picker].values())
	assert_int(buttons.size()).is_greater(20)
	for button: Control in buttons:
		assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)


func test_a_tap_still_picks_a_tile() -> void:
	var screen := wardrobe()
	await await_idle_frame()
	var tiles: Dictionary = screen._tiles["body"]
	var tile: Button = tiles.values().filter(func(t: Button) -> bool: return not t.button_pressed)[0]
	# push_input takes window pixels, not the screen's own units.
	var at := tile.get_viewport().get_final_transform() * tile.get_global_rect().get_center()
	var click := func(pressed: bool) -> void:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		tile.get_viewport().push_input(event)
	click.call(true)
	click.call(false)
	await await_idle_frame()
	assert_bool(tile.button_pressed).is_true()
