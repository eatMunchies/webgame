extends GalleryPage

## Choices for the primary action's wax button, side by side, for the
## owner to pick: four shapes of wax, each with its words in IM Fell small
## caps, and the old pill in Atkinson bold to compare.


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var sheet := ParchmentPanel.new()
	sheet.theme = UiTheme.paper()
	margin.add_child(sheet)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_LG)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_MD)
	sheet.add_child(flow)

	flow.add_child(_option("A · seal (new)", UiTheme.seal_box(Tokens.WAX, 1.0), Fonts.HEADING))
	var pill := UiTheme.seal_box(Tokens.WAX, 1.0)
	pill.set_corner_radius_all(Tokens.SPACE_LG)
	pill.border_width_bottom = 0
	flow.add_child(_option("B · pill, no edge", pill, Fonts.HEADING))
	var inked := UiTheme.seal_box(Tokens.WAX, 1.0)
	inked.border_color = Tokens.INK
	inked.set_border_width_all(1)
	inked.set_corner_radius_all(0)
	flow.add_child(_option("C · inked square", inked, Fonts.HEADING))
	var deep := UiTheme.seal_box(Tokens.WAX_PRESSED, 1.0)
	flow.add_child(_option("D · darker wax", deep, Fonts.HEADING))
	var old := UiTheme.seal_box(Tokens.WAX, 1.0)
	old.set_corner_radius_all(Tokens.SPACE_LG)
	old.border_color = Tokens.WAX_PRESSED
	old.set_border_width_all(1)
	flow.add_child(_option("old · pill, Atkinson", old, Fonts.BODY_BOLD))


static func _option(label: String, box: StyleBoxFlat, font: Font) -> Control:
	var column := vbox(Tokens.SPACE_XS)
	column.custom_minimum_size.x = 80
	var button := Button.new()
	button.text = "Start game"
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, box)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", Tokens.TYPE_SEAL)
	button.add_theme_color_override("font_color", Tokens.INK_ON_DARK)
	column.add_child(button)
	var note := Label.new()
	note.text = label
	note.theme_type_variation = "Caption"
	column.add_child(note)
	return column
