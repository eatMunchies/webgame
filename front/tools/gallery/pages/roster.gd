extends GalleryPage

## The roster alone, in each state it has: a lobby with the host's Start,
## voting (votes on a player, the dead, whisper icons), a trial's verdict
## buttons, a night's neutral "Choose" buttons by candlelight, and a crowd of
## 15 with long names. Shown at the width of a wide screen's column (96
## units) and a phone's full width (180), where that fits.

const ROSTER := preload("res://scenes/hud/roster.tscn")
const FIXTURES := preload("res://tools/gallery/fixtures.gd")


func _init() -> void:
	variants = ["lobby", "voting", "trial", "night", "crowd"]


func build(stage: Control, variant: String) -> void:
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
	for width in [96.0, 172.0]:
		var column := vbox(Tokens.SPACE_XS)
		column.custom_minimum_size.x = width
		flow.add_child(column)
		column.add_child(caption("%s · %d units wide" % [variant, width]))
		var roster: Control = ROSTER.instantiate()
		roster.preview = true
		# Alone, the rows take what they need instead of a share of a screen.
		roster.max_rows_height = 400.0
		roster.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		column.add_child(roster)
		roster.show_model(FIXTURES.roster(variant))
