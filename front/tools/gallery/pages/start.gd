extends GalleryPage

## The start screen as a player first sees it: the plaza and their house,
## the panel to name themselves and host or join, the hint over the house,
## and a refusal from the server; then with the session key's text box open.

const LOBBY := preload("res://scenes/main/lobby.tscn")

var _variant := ""


func _init() -> void:
	variants = ["fresh", "refused", "typing_key"]
	settle_frames = 30


func build(stage: Control, variant: String) -> void:
	_variant = variant
	var lobby: Node = LOBBY.instantiate()
	stage.add_child(lobby)


func after_settle(stage: Control) -> void:
	var lobby: Node = stage.get_child(0)
	if _variant == "refused":
		lobby.status_label.text = "No lobby with that code."
	elif _variant == "typing_key":
		lobby.code_input.text = "WTCH92"
		lobby._prompt.ask("session key", "WTCH92", func(_t: String) -> void: pass,
				{"paste": true, "confirm": "join"})
