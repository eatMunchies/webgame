extends GalleryPage

## The woodcut icon set: each in ink on parchment and in the machine's text
## color on glass, at the HUD's 16-unit size, with its name.


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var column := vbox(Tokens.SPACE_SM)
	margin.add_child(column)

	var sheet := ParchmentPanel.new()
	sheet.theme = UiTheme.paper()
	column.add_child(sheet)
	sheet.add_child(_grid(Tokens.INK, Tokens.INK_FAINT))

	var glass := SystemPanel.new()
	glass.theme = UiTheme.system()
	column.add_child(glass)
	glass.add_child(_grid(Tokens.SYS_TEXT, Tokens.SYS_DIM))


static func _grid(ink: Color, note: Color) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_SM)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	for icon_name in Icons.NAMES:
		var cell := vbox(0)
		cell.custom_minimum_size.x = 26
		var icon := TextureRect.new()
		icon.texture = Icons.get_icon(icon_name)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(Tokens.ICON, Tokens.ICON)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = ink
		cell.add_child(icon)
		var label := caption(icon_name, note)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		flow.add_child(cell)
	return flow
