extends GalleryPage

## The simulated Salem's colors, on parchment by day and by candlelight:
## paper, iron-gall inks, wax and gold, the dyes that carry meaning, and the
## chat's inks. Each ink shows its contrast against the paper it sits on
## (4.5 is the least for reading).


func _init() -> void:
	variants = ["day", "night"]


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
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	sheet.add_child(flow)

	var paper := Tokens.paper_surface
	flow.add_child(_group("Paper", [
		["raised", Tokens.paper_raised], ["surface", Tokens.paper_surface],
		["sunken", Tokens.paper_sunken], ["edge", Tokens.paper_edge],
	], paper, false))
	flow.add_child(_group("Ink", [
		["ink", Tokens.INK], ["secondary", Tokens.INK_SECONDARY],
		["faint", Tokens.INK_FAINT], ["rule", Tokens.INK_RULE, true],
	], paper, true))
	flow.add_child(_group("Wax & gold", [
		["wax", Tokens.WAX], ["wax hover", Tokens.WAX_HOVER, true],
		["gold", Tokens.GOLD, true], ["glow", Tokens.GLOW, true],
	], paper, true))
	flow.add_child(_group("Meaning", [
		["you", Tokens.YOU], ["dead", Tokens.DEAD],
		["safe", Tokens.SAFE], ["danger", Tokens.DANGER],
	], paper, true))
	flow.add_child(_group("Factions (role card)", [
		["town", Tokens.FACTION_TOWN], ["mafia", Tokens.FACTION_MAFIA],
		["neutral", Tokens.FACTION_NEUTRAL],
	], paper, true))


## A heading over a column of swatches, each [name, color].
static func _group(title: String, swatches: Array, on: Color, show_contrast: bool) -> Control:
	var box := vbox(Tokens.SPACE_HAIR)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = "Heading"
	box.add_child(heading)
	for swatch: Array in swatches:
		# A third entry marks a color for lines and ornament, never text.
		var decor: bool = swatch.size() > 2 and swatch[2]
		box.add_child(_swatch(swatch[0], swatch[1], on, show_contrast, decor))
	return box


static func _swatch(swatch_name: String, color: Color, on: Color, show_contrast: bool, decor := false) -> Control:
	var row := hbox(Tokens.SPACE_XS)
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(9, 7)
	row.add_child(chip)
	var text := caption(swatch_name, Tokens.INK)
	row.add_child(text)
	var detail := hex(color)
	if decor:
		detail += "  decor"
	elif show_contrast:
		var ratio := contrast(color, on)
		detail += "  %.1f%s" % [ratio, "" if ratio >= 4.5 else " low"]
	row.add_child(caption(detail, Tokens.INK_FAINT))
	return row
