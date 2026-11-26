extends GalleryPage

## The spacing scale as a ruler of ink bars, the smallest tap target, and
## the icon grid, all in HUD units.


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
	var column := vbox(Tokens.SPACE_SM)
	sheet.add_child(column)

	var heading := Label.new()
	heading.text = "Spacing"
	heading.theme_type_variation = "Heading"
	column.add_child(heading)
	for step: Array in [["hair", Tokens.SPACE_HAIR], ["xs", Tokens.SPACE_XS], ["sm", Tokens.SPACE_SM],
			["md", Tokens.SPACE_MD], ["lg", Tokens.SPACE_LG], ["xl", Tokens.SPACE_XL],
			["xxl", Tokens.SPACE_XXL]]:
		var row := hbox(Tokens.SPACE_SM)
		var bar := ColorRect.new()
		bar.color = Tokens.INK
		bar.custom_minimum_size = Vector2(step[1] * 4, 3)
		row.add_child(caption("%-4s %2d" % [step[0], step[1]], Tokens.INK_SECONDARY))
		row.add_child(bar)
		column.add_child(row)

	var sizes := Label.new()
	sizes.text = "Sizes"
	sizes.theme_type_variation = "Heading"
	column.add_child(sizes)
	var row := hbox(Tokens.SPACE_LG)
	column.add_child(row)
	row.add_child(_box("tap %d" % Tokens.TOUCH_MIN, Vector2(Tokens.TOUCH_MIN * 2, Tokens.TOUCH_MIN)))
	row.add_child(_box("icon %d" % Tokens.ICON, Vector2(Tokens.ICON, Tokens.ICON)))
	row.add_child(_box("rule %d" % Tokens.RULE, Vector2(24, Tokens.RULE)))


static func _box(text: String, size: Vector2) -> Control:
	var box := vbox(Tokens.SPACE_HAIR)
	var shape := Panel.new()
	shape.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Tokens.INK, 0.12)
	style.border_color = Tokens.INK
	style.set_border_width_all(1)
	shape.add_theme_stylebox_override("panel", style)
	box.add_child(shape)
	box.add_child(caption(text, Tokens.INK_SECONDARY))
	return box
