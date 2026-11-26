extends GalleryPage

## The type scale: every style in its face and size, on parchment and on the
## machine's glass, with sample words from the game.


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_SM)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	margin.add_child(flow)

	var sheet := ParchmentPanel.new()
	sheet.theme = UiTheme.paper()
	flow.add_child(sheet)
	var paper := vbox(Tokens.SPACE_XS)
	sheet.add_child(paper)
	_specimen(paper, "Title", "Table of Salem", "IM Fell English  %d" % Tokens.TYPE_TITLE)
	_specimen(paper, "Heading", "Day the Second", "IM Fell SC  %d" % Tokens.TYPE_HEADING)
	_specimen(paper, "Body", "Bram whispers to Ada (3)", "Atkinson  %d" % Tokens.TYPE_BODY)
	_specimen(paper, "Dim", "Ada was a Sheriff", "Atkinson faint  %d" % Tokens.TYPE_BODY)
	_specimen(paper, "Caption", "away  ·  host  ·  2 votes", "Atkinson  %d" % Tokens.TYPE_CAPTION)
	var display := Label.new()
	display.text = "The Town Votes"
	display.add_theme_font_override("font", Fonts.TITLE)
	display.add_theme_font_size_override("font_size", Tokens.TYPE_DISPLAY)
	paper.add_child(display)
	paper.add_child(caption("Display  IM Fell %d" % Tokens.TYPE_DISPLAY, Tokens.INK_FAINT))

	var glass := SystemPanel.new()
	glass.theme = UiTheme.system()
	flow.add_child(glass)
	var system := vbox(Tokens.SPACE_XS)
	glass.add_child(system)
	_specimen(system, "Title", "SIMULATION 7", "Plex Mono bold  %d" % Tokens.TYPE_TITLE)
	_specimen(system, "Heading", "SUBJECT SYNC", "Plex Mono bold  %d" % Tokens.TYPE_MONO)
	_specimen(system, "Mono", "> memory sync 42%", "Plex Mono  %d" % Tokens.TYPE_MONO)
	_specimen(system, "Accent", "> desync detected", "accent  %d" % Tokens.TYPE_MONO)
	_specimen(system, "Caption", "build 0.9.3 / node salem-1692", "Plex Mono  %d" % Tokens.TYPE_MONO_SMALL)


static func _specimen(column: Control, variation: String, sample: String, note: String) -> void:
	var label := Label.new()
	label.text = sample
	label.theme_type_variation = variation
	column.add_child(label)
	var detail := Label.new()
	detail.text = "%s · %s" % [variation, note]
	detail.theme_type_variation = "Caption"
	column.add_child(detail)
