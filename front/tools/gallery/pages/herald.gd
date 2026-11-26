extends GalleryPage

## The herald's banner at the top of the town: a death at dawn with its will
## (a long one), an execution, and a morning when nobody died. Over a stand-in
## for the town, in a box as wide as the town's part of a phone.


func _init() -> void:
	variants = ["death", "execution", "quiet"]
	settle_frames = 30


func build(stage: Control, variant: String) -> void:
	backdrop(stage, Color("#4a6a3a"))
	var town := Control.new()
	town.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(town)
	var herald := Herald.new()
	town.add_child(herald)
	herald.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE,
			Tokens.SPACE_MD)
	herald.grow_horizontal = Control.GROW_DIRECTION_BOTH
	match variant:
		"death":
			herald.announce("Cleo was found dead", 1)
			herald.add_line("Killed by the Mafia, stabbed by a Serial Killer.")
			herald.add_line("They were the Doctor.", "Dim")
			herald.show_will("N1: healed 4 Dax.\nN2: healed myself. Someone visited me, I think 6 Finn is lying about being the Sheriff.")
			herald.add_line("Rest in peace.", "Heading")
		"execution":
			herald.announce("Bartholomew Wigglesworth was executed", 11)
			herald.add_line("They were the Mafioso.", "Dim")
			herald.show_will("")
		"quiet":
			herald.announce("Morning in Salem")
			herald.add_line("Nobody died last night.")
