extends GalleryPage

## Text fields: empty with a placeholder, filled, and focused with the
## caret, on parchment (a ruled line to write on) and on the machine.


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
	sheet.tier = ParchmentPanel.Tier.DOCUMENT
	column.add_child(sheet)
	var paper := vbox(Tokens.SPACE_XS)
	sheet.add_child(paper)
	var title := Label.new()
	title.text = "Whisper to 2 Bram"
	title.theme_type_variation = "Title"
	paper.add_child(title)
	_fields(paper, "Type a message", "meet me at the podium")
	var will := TextEdit.new()
	will.text = "N1: checked 3, not suspicious\nN2: healed 4"
	will.custom_minimum_size = Vector2(0, 30)
	paper.add_child(will)
	will.grab_focus.call_deferred()
	will.set_caret_line.call_deferred(1)
	will.set_caret_column.call_deferred(6)

	var glass := SystemPanel.new()
	glass.theme = UiTheme.system()
	column.add_child(glass)
	var system := vbox(Tokens.SPACE_XS)
	glass.add_child(system)
	var heading := Label.new()
	heading.text = "SUBJECT NAME"
	heading.theme_type_variation = "Heading"
	system.add_child(heading)
	_fields(system, "enter name", "Ada")


static func _fields(column: Control, placeholder: String, filled: String) -> void:
	var empty := LineEdit.new()
	empty.placeholder_text = placeholder
	column.add_child(empty)
	var full := LineEdit.new()
	full.text = filled
	column.add_child(full)
