extends GalleryPage

## The clock alone, in each state it has, at a wide screen's column width
## (88 units) and a phone's full width (176), with the machine's notice as
## it shows while reconnecting. By day, then by candlelight.

const CLOCK := preload("res://scripts/hud/phase_clock.gd")

const MODELS := {
	"lobby": {"title": "Lobby", "stage": "3 joined, 4 to start", "seconds": -1, "night": false, "code": "WTCH92"},
	"discussion": {"title": "Day 2", "stage": "Discussion", "seconds": 42, "night": false, "code": "WTCH92"},
	"hurry": {"title": "Day 2", "stage": "Judgement: Cleo", "seconds": 4, "night": false, "code": "WTCH92"},
	"long": {"title": "Day 12", "stage": "Defense: Bartholomew Wigglesworth", "seconds": 18, "night": false, "code": "WTCH92"},
	"choosing": {"title": "Night 1", "stage": "Choose your action", "seconds": 23, "night": true, "code": "WTCH92"},
	"night": {"title": "Night 1", "stage": "Roleblocks", "seconds": 9, "night": true, "code": "WTCH92"},
	"leaving": {"title": "Day 2", "stage": "Discussion", "seconds": 42, "night": false, "code": "WTCH92"},
	"reconnecting": {"title": "Day 2", "stage": "Voting", "seconds": 30, "night": false, "code": "WTCH92", "reconnecting": true},
}


func _init() -> void:
	variants = ["day", "night"]


func build(stage: Control, variant: String) -> void:
	backdrop(stage)
	var page := flow(stage, Tokens.SPACE_MD, Tokens.SPACE_SM)
	var names: Array = ["lobby", "discussion", "hurry", "long", "leaving", "reconnecting"] if variant == "day" \
			else ["choosing", "night"]
	for width in [88.0, 176.0]:
		var column := vbox(Tokens.SPACE_XS)
		column.custom_minimum_size.x = width
		page.add_child(column)
		for name in names:
			column.add_child(caption("%s · %d" % [name, width]))
			var clock: Control = CLOCK.new()
			clock.preview = true
			column.add_child(clock)
			var model: Dictionary = MODELS[name].duplicate()
			model["reconnecting"] = model.get("reconnecting", false)
			if name == "leaving":
				clock.arm_leave()
			clock.show_model(model)
	if variant == "day":
		var column := vbox(Tokens.SPACE_XS)
		page.add_child(column)
		column.add_child(caption("notice · reconnecting"))
		var notice := Notice.new()
		column.add_child(notice)
		notice.say(PackedStringArray(["desync detected, resyncing", "hold on, getting you back in"]))
