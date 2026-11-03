extends Control

## Plays one skill check by itself, in the night's minigame panel, with no
## server. Pick the check in the inspector and run the scene (F6). It's
## decided here the way the server would: rolled with the reported chance
## once it's done, or when time runs out, after which it carries on as
## practice. Enter starts a new one.

const OVERLAY_SCENE := preload("res://scenes/main/minigame_overlay.tscn")

## The skill check to play.
@export var def: SkillCheckDef = preload("res://skill_checks/typing.tres")
## How long it has, as a stage of the night would give it.
@export var seconds := 10.0
## Play it as a passive game, with nothing riding on it.
@export var practice := false

var _overlay: MinigameOverlay
var _rng := RandomNumberGenerator.new()
var _chance := 0.0
var _decided := false
var _ends_at_msec := 0

@onready var log_label: Label = %Log


func _ready() -> void:
	_rng.randomize()
	_overlay = OVERLAY_SCENE.instantiate()
	_overlay.skill_checks = [def]
	_overlay.check_reported.connect(_on_check_reported)
	add_child(_overlay)
	_start()


func _start() -> void:
	_chance = 0.0
	_decided = practice
	_ends_at_msec = Time.get_ticks_msec() + int(seconds * 1000)
	_overlay.show_minigame({})
	_overlay.show_minigame({
		"kind": "passive" if practice else "skill_check",
		"ends_in_ms": int(seconds * 1000),
	})
	log_label.text = "Enter: start over\n"


func _process(_delta: float) -> void:
	if not _decided and Time.get_ticks_msec() >= _ends_at_msec:
		log_label.text += "Out of time\n"
		_decide()


func _on_check_reported(chance: float, done: bool) -> void:
	_chance = chance
	log_label.text += "Reported %d%%%s\n" % [roundi(chance * 100), ", done" if done else ""]
	if done:
		_decide()


func _decide() -> void:
	_decided = true
	var passed := _rng.randf() < _chance
	log_label.text += "Rolled %d%%: %s\n" % [roundi(_chance * 100), "passed" if passed else "failed"]
	_overlay.show_minigame({
		"kind": "skill_check",
		"ends_in_ms": maxi(_ends_at_msec - Time.get_ticks_msec(), 0),
		"result": "passed" if passed else "failed",
	})


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_start()
		get_viewport().set_input_as_handled()
