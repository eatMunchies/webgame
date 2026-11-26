extends SceneTree

## Plays the game and saves a screenshot every few seconds, for checking the
## UI where there's no screen to look at (an agent, CI). Run it through
## `just shots`, which starts it under a virtual display.
##
## Each frame is named by the seconds since start and the clock's phase, like
## 024_Night_1_Choosing_011.png, so the moments are easy to pick out. Game
## options go after `--` as usual (--name=Ada --create, --join=CODE,
## --server=ws://...), so a run can host or join a lobby that terminal bots
## (`just cli`) are in.
##
## Settings come from the environment:
## - SHOTS: the folder to save into (made if missing).
## - SECS: how long to run, 60 by default.
## - EVERY: seconds between frames, 4 by default.
## - SCENE: the scene to start in, the start screen by default.
## - TOUCH=1: act as a touch screen (TextPrompt.touch), as a phone would.
## - CLOSE_CARD=1: close the role card whenever it opens, as a player would.
##
## Gotchas: this script is compiled before the game's autoloads exist, so it
## reaches Session as root.get_node("Session") and loads other scripts by
## path instead of naming their classes. Input events made with
## Input.parse_input_event take window pixels, not the HUD's units: map a
## Control's point with root.get_final_transform().

var _out := ""
var _secs := 60.0
var _every := 4.0
var _t := 0.0
var _next := 0.0


func _initialize() -> void:
	_out = OS.get_environment("SHOTS")
	if _out == "":
		_out = ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(_out)
	_secs = float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 60.0
	_every = float(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 4.0
	if OS.get_environment("TOUCH") == "1":
		load("res://scripts/ui/text_prompt.gd").touch = true
	var scene := OS.get_environment("SCENE")
	change_scene_to_file(scene if scene != "" else "res://scenes/main/lobby.tscn")


func _close_cards(node: Node) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("role_card.gd") and node.visible:
		node.close()
	for child in node.get_children():
		_close_cards(child)


func _process(delta: float) -> bool:
	_t += delta
	if OS.get_environment("CLOSE_CARD") == "1":
		_close_cards(root)
	if _t >= _next:
		var session := root.get_node_or_null("Session")
		var phase: String = str(session.client.phase_label()) if session and session.client else ""
		var label := phase.replace(" ", "_").replace(":", "").replace("/", "-").replace(",", "")
		root.get_texture().get_image().save_png("%s/%03d_%s.png" % [_out, int(_t), label])
		_next += _every
	return _t > _secs
