extends GalleryPage

## The modals: the text box (a whisper on one line, the last will on
## several, and the same box on the machine's glass for its screens) and the
## role card (a Town, a Mafia and a Neutral role, and a spectator's). Each
## over a dimmed stand-in for the town.

const ROLES := {
	"town": {"spectator": false, "name": "Sheriff", "faction": "Town", "category": "Town Investigative",
		"ability": "Interrogate one person a night to learn if they are suspicious (Mafia other than the Godfather, or a Serial Killer).",
		"goal": "Lynch every criminal and evildoer.", "target": "", "team": []},
	"mafia": {"spectator": false, "name": "Mafioso", "faction": "Mafia", "category": "Mafia Killing",
		"ability": "Kill the Godfather's choice each night, or your own if they don't choose.",
		"goal": "Kill anyone who won't submit to the Mafia.", "target": "",
		"team": ["3 Cleo (Godfather)", "6 Finn (Consort)"]},
	"neutral": {"spectator": false, "name": "Executioner", "faction": "Neutral", "category": "Neutral Evil",
		"ability": "Get your target lynched. If they die any other way, you become a Jester. You have basic defense.",
		"goal": "Get your target lynched.", "target": "4 Dax", "team": []},
	"spectator": {"spectator": true},
}


func _init() -> void:
	variants = ["whisper", "will", "machine", "town", "mafia", "neutral", "spectator"]
	settle_frames = 10


func build(stage: Control, variant: String) -> void:
	backdrop(stage, Color("#4a6a3a"))
	if variant in ROLES:
		var card := RoleCard.create(stage)
		card.open_with(ROLES[variant])
		return
	var prompt := TextPrompt.create(stage, variant == "machine")
	match variant:
		"whisper":
			prompt.ask("Whisper to 2 Bram", "Meet me at the well", func(_t: String) -> void: pass)
		"will":
			prompt.ask("Last will", "N1: checked 3 Cleo, suspicious!\nN2: checked 5 Eve, not suspicious",
					func(_t: String) -> void: pass,
					{"multiline": true, "confirm": "Save",
						"placeholder": "Everyone reads this when you die."})
		"machine":
			prompt.ask("session key", "WTCH92", func(_t: String) -> void: pass,
					{"paste": true, "confirm": "join"})
