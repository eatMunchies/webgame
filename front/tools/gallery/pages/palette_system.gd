extends GalleryPage

## The machine's colors on its black glass, with contrast against it, and
## the fifteen seat dyes with their parchment numerals.


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var column := vbox(Tokens.SPACE_SM)
	margin.add_child(column)

	var glass := SystemPanel.new()
	glass.theme = UiTheme.system()
	column.add_child(glass)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_LG)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	glass.add_child(flow)
	var swatches := [
		["bg", Tokens.SYS_BG], ["surface", Tokens.SYS_SURFACE], ["line", Tokens.SYS_LINE],
		["text", Tokens.SYS_TEXT], ["dim", Tokens.SYS_DIM], ["accent", Tokens.SYS_ACCENT],
		["accent dim", Tokens.SYS_ACCENT_DIM], ["fault", Tokens.SYS_FAULT],
	]
	var box := vbox(Tokens.SPACE_HAIR)
	var heading := Label.new()
	heading.text = "THE MACHINE"
	heading.theme_type_variation = "Heading"
	box.add_child(heading)
	for swatch: Array in swatches:
		var row := hbox(Tokens.SPACE_XS)
		var chip := ColorRect.new()
		chip.color = swatch[1]
		chip.custom_minimum_size = Vector2(9, 7)
		row.add_child(chip)
		row.add_child(caption(swatch[0], Tokens.SYS_TEXT))
		var ratio := contrast(swatch[1], Tokens.SYS_BG)
		row.add_child(caption("%s  %.1f" % [hex(swatch[1]), ratio], Tokens.SYS_DIM))
		box.add_child(row)
	flow.add_child(box)

	var seats := ParchmentPanel.new()
	seats.theme = UiTheme.paper()
	column.add_child(seats)
	var seat_box := vbox(Tokens.SPACE_XS)
	seats.add_child(seat_box)
	var seat_heading := Label.new()
	seat_heading.text = "Seat dyes"
	seat_heading.theme_type_variation = "Heading"
	seat_box.add_child(seat_heading)
	var dots := HFlowContainer.new()
	dots.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	dots.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	seat_box.add_child(dots)
	for n in range(1, 16):
		dots.add_child(_seat(n))


static func _seat(n: int) -> Control:
	var badge := SeatBadge.new()
	badge.number = n
	badge.custom_minimum_size *= 1.4
	return badge
