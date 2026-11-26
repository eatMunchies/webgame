extends GalleryPage

## The surfaces: a parchment Sheet (the HUD's working panels) and Document
## (things handed to you), by day and by candlelight, and the machine's
## glass panel.


func _init() -> void:
	variants = ["day", "night"]


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_MD)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_MD)
	margin.add_child(flow)

	var sheet := ParchmentPanel.new()
	sheet.theme = UiTheme.paper()
	sheet.custom_minimum_size = Vector2(80, 54)
	flow.add_child(sheet)
	sheet.add_child(_contents("Sheet", "Players: 6/6 alive", "The HUD's working panels: flat edges, so many side by side stay calm."))

	var document := ParchmentPanel.new()
	document.theme = UiTheme.paper()
	document.tier = ParchmentPanel.Tier.DOCUMENT
	document.seed = 3.0
	document.custom_minimum_size = Vector2(80, 54)
	flow.add_child(document)
	document.add_child(_contents("Document", "Sheriff", "Handed to you: a role card, a will. Torn edge, darker margins."))

	var glass := SystemPanel.new()
	glass.theme = UiTheme.system()
	glass.custom_minimum_size = Vector2(80, 54)
	flow.add_child(glass)
	var lines := vbox(Tokens.SPACE_XS)
	glass.add_child(lines)
	var title := Label.new()
	title.text = "SYSTEM PANEL"
	title.theme_type_variation = "Heading"
	lines.add_child(title)
	var body := Label.new()
	body.text = "> subject: Ada\n> memory sync 42%\n> scanlines, brackets"
	lines.add_child(body)


static func _contents(kind: String, title_text: String, note: String) -> Control:
	var box := vbox(Tokens.SPACE_XS)
	var heading := Label.new()
	heading.text = kind
	heading.theme_type_variation = "Heading"
	box.add_child(heading)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = "Title"
	box.add_child(title)
	var body := Label.new()
	body.text = note
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 72
	box.add_child(body)
	return box
