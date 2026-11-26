extends GalleryPage

## Every button style in every state, on parchment and on the machine's
## glass. A screenshot can't hover, so each state's look is applied as the
## button's resting look.

const STATES := ["normal", "hover", "pressed", "disabled"]


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
	var paper := UiTheme.paper()
	sheet.theme = paper
	column.add_child(sheet)
	var paper_rows := vbox(Tokens.SPACE_XS)
	sheet.add_child(paper_rows)
	paper_rows.add_child(_row(paper, "Button", "Vote", "stamped"))
	paper_rows.add_child(_row(paper, "WaxButton", "Start game", "primary"))
	paper_rows.add_child(_row(paper, "QuietButton", "Cancel", "quiet"))
	paper_rows.add_child(_icon_row(paper, Tokens.INK))

	var glass := SystemPanel.new()
	var system := UiTheme.system()
	glass.theme = system
	column.add_child(glass)
	var glass_rows := vbox(Tokens.SPACE_XS)
	glass.add_child(glass_rows)
	glass_rows.add_child(_row(system, "Button", "Strike", "system"))
	glass_rows.add_child(_row(system, "SysPrimary", "Join", "primary"))
	glass_rows.add_child(_row(system, "QuietButton", "Back", "quiet"))


static func _row(theme: Theme, type: String, text: String, note: String) -> Control:
	var row := hbox(Tokens.SPACE_XS)
	var name := Label.new()
	name.text = note
	name.theme_type_variation = "Caption"
	name.custom_minimum_size.x = 24
	row.add_child(name)
	for state: String in STATES:
		var button := Button.new()
		button.text = text
		button.theme_type_variation = type
		button.focus_mode = Control.FOCUS_NONE
		if state == "disabled":
			button.disabled = true
		elif state != "normal":
			button.add_theme_stylebox_override("normal", theme.get_stylebox(state, type))
			button.add_theme_color_override("font_color", theme.get_color("font_%s_color" % state, type))
		row.add_child(button)
	return row


static func _icon_row(_theme: Theme, ink: Color) -> Control:
	var row := hbox(Tokens.SPACE_XS)
	var name := Label.new()
	name.text = "icon"
	name.theme_type_variation = "Caption"
	name.custom_minimum_size.x = 24
	row.add_child(name)
	for icon_name: StringName in [&"will", &"role", &"whisper", &"copy", &"leave"]:
		var button := Button.new()
		button.icon = Icons.get_icon(icon_name)
		button.theme_type_variation = "IconButton"
		button.focus_mode = Control.FOCUS_NONE
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.add_theme_color_override("icon_normal_color", ink)
		row.add_child(button)
	var labelled := Button.new()
	labelled.icon = Icons.get_icon(&"whisper")
	labelled.text = "Whisper"
	labelled.theme_type_variation = "IconButton"
	labelled.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(labelled)
	return row
