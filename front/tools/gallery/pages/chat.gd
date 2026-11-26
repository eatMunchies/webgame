extends GalleryPage

## The chat alone, with a line of every kind: the machine's (teal mono, after
## a `>`), game news (ochre), what players said (ink, after their seat
## badge, a two-digit one too), and whispers (woad). At a wide screen's
## column width (88 units) and a phone's (176), by day and by candlelight.

const CHAT := preload("res://scenes/hud/chat_panel.tscn")

const LINES := [
	{"text": "Connected as Ada.", "kind": "system", "lot": -1},
	{"text": "In lobby WTCH92.", "kind": "system", "lot": -1},
	{"text": "The game begins.", "kind": "game", "lot": -1},
	{"text": "Bram (2): I was home all night, ask anyone.", "kind": "chat", "lot": 1},
	{"text": "Cleo (3): Cleo, where were you?", "kind": "chat", "lot": 2},
	{"text": "Lucretia (12): Somebody is lying.", "kind": "chat", "lot": 11},
	{"text": "Bram whispers to you: vote Cleo", "kind": "whisper", "lot": -1},
	{"text": "Votes: Cleo (3) 2 (4 needed)", "kind": "game", "lot": -1},
	{"text": "! Unknown command /fly. Try /help.", "kind": "system", "lot": -1},
]


func _init() -> void:
	variants = ["day", "night"]


func build(stage: Control, _variant: String) -> void:
	backdrop(stage)
	var page := flow(stage, Tokens.SPACE_MD, Tokens.SPACE_SM)
	for width in [88.0, 176.0]:
		var column := vbox(Tokens.SPACE_XS)
		column.custom_minimum_size = Vector2(width, 120)
		page.add_child(column)
		column.add_child(caption("chat · %d units wide" % width))
		var chat: Control = CHAT.instantiate()
		chat.preview = true
		chat.custom_minimum_size.y = 110
		column.add_child(chat)
		chat.show_lines(LINES)
