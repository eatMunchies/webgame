extends Control

## The minigame tester, opened from the start screen's Minigames button:
## every minigame in res://skill_checks/ in a list, played in the same panel
## and at the same size as during a night, with no server.
##
## Played for real, it's decided the way the server would: rolled with the
## chance the game reports once it's done, or with the last one when time
## runs out, after which it carries on as practice. With Practice ticked,
## nothing rides on it, as for a player with no action that stage. The log
## on the right shows what the game reported and how it rolled.
##
## Night, first in the list, plays a whole night instead (see PracticeNight):
## every stage in order with the real overlay and its pools, your action's
## skill check in one stage and a fight against a bot in another, and the
## morning's summary in the panel. As on the town's clock, the header
## names the stage only while you choose your action; after that it says
## just "Night 1", so the stages go by unseen.
##
## Again starts the picked game (or night) over; Back or Escape returns to
## the start screen.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"
const OVERLAY_SCENE := preload("res://scenes/main/minigame_overlay.tscn")
const CHECKS_DIR := "res://skill_checks/"
## How long a game has, as a stage of the night would give it.
const SECONDS := 10.0
## The most log lines shown; older ones scroll off the top.
const LOG_LINES := 9

## Every minigame found, by title.
var defs: Array[SkillCheckDef] = []
## The game being played, or null for a night.
var current: SkillCheckDef

var _overlay: MinigameOverlay
var _rng := RandomNumberGenerator.new()
var _chance := 0.0
var _decided := false
var _ends_at_msec := 0
var _buttons := ButtonGroup.new()
var _night: PracticeNight
## Whether the night being played is fights-only practice, for Again.
var _fights_only := false
var _stage_title := ""
var _log_lines: Array[String] = []

@onready var list: VBoxContainer = %List
@onready var practice_toggle: CheckBox = %PracticeToggle
@onready var controls_label: Label = %Controls
@onready var log_label: Label = %Log
@onready var stage: Control = %Stage
@onready var stage_label: Label = %StageLabel
@onready var summary_label: Label = %Summary


func _ready() -> void:
	ScreenScale.for_world(get_window())
	theme = HudStyle.build()
	_rng.randomize()
	defs = find_defs()
	_add_button("Night", play_night)
	_add_button("Fight", play_night.bind(true))
	for def in defs:
		_add_button(def.title, play.bind(def))
	list.get_child(0).button_pressed = true
	play_night()


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = _buttons
	button.focus_mode = FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Tall enough to hit with a thumb.
	button.custom_minimum_size.y = 11
	button.pressed.connect(on_pressed)
	list.add_child(button)


## Every SkillCheckDef in res://skill_checks/, sorted by title.
static func find_defs() -> Array[SkillCheckDef]:
	var found: Array[SkillCheckDef] = []
	for file in ResourceLoader.list_directory(CHECKS_DIR):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def := load(CHECKS_DIR + file) as SkillCheckDef
			if def != null:
				found.append(def)
	found.sort_custom(func(a: SkillCheckDef, b: SkillCheckDef) -> bool: return a.title < b.title)
	return found


## Starts `def` fresh, in a new panel so nothing carries over from the last
## game.
func play(def: SkillCheckDef) -> void:
	_reset()
	current = def
	_overlay.skill_checks = [def]
	_overlay.practice_checks = [def]
	_overlay.check_reported.connect(_on_check_reported)
	stage.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	practice_toggle.disabled = false
	var practice := practice_toggle.button_pressed
	_chance = 0.0
	_decided = practice
	# A game that counts opens with the countdown, which the server adds on top.
	var seconds := SECONDS if practice else SECONDS + _overlay.intro_seconds
	_ends_at_msec = Time.get_ticks_msec() + int(seconds * 1000)
	_overlay.show_minigame({
		"kind": "passive" if practice else "skill_check",
		"ends_in_ms": int(seconds * 1000),
	})
	controls_label.text = _overlay.check.hint() if _overlay.check != null else ""
	_stage_title = def.title
	_log("Practice" if practice else "For real, %ds" % SECONDS)


## Plays a whole night with the overlay's real pools, as PracticeNight
## describes, or with `fights_only` a few fights back to back against the bot.
func play_night(fights_only := false) -> void:
	_reset()
	current = null
	stage.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	practice_toggle.disabled = true
	_night = PracticeNight.new()
	add_child(_night)
	_night.stage_started.connect(_on_night_stage_started)
	_night.logged.connect(_log)
	_night.hint_changed.connect(func(text: String) -> void: controls_label.text = text)
	_night.finished.connect(func(summary: String) -> void: summary_label.text = summary)
	_fights_only = fights_only
	_night.start(_overlay, -1, fights_only)


## Clears away the last game or night for a fresh overlay.
func _reset() -> void:
	if _night != null:
		_night.queue_free()
		_night = null
	if _overlay != null:
		_overlay.queue_free()
	_overlay = OVERLAY_SCENE.instantiate()
	_decided = true
	_log_lines.clear()
	log_label.text = ""
	summary_label.text = ""
	controls_label.text = ""


func _process(_delta: float) -> void:
	var left := maxi(_ends_at_msec - Time.get_ticks_msec(), 0)
	stage_label.text = _stage_title if left == 0 else "%s  %ds" % [_stage_title, ceili(left / 1000.0)]
	if not _decided and left == 0:
		_log("Out of time")
		_decide()


func _on_night_stage_started(title: String, seconds: float) -> void:
	var choosing := title == PracticeNight.CHOOSING
	if title == "Morning":
		_stage_title = title
		_log(title)
	elif _fights_only:
		# Fights-only practice has nothing to hide, so it names each fight.
		_stage_title = title
	else:
		_stage_title = "Night 1 · %s" % title if choosing else "Night 1"
	_ends_at_msec = Time.get_ticks_msec() + int(seconds * 1000) if choosing else 0


## Adds a line to the log, dropping the oldest past LOG_LINES.
func _log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > LOG_LINES:
		_log_lines.remove_at(0)
	log_label.text = "\n".join(_log_lines)


func _on_check_reported(chance: float, done: bool) -> void:
	_chance = chance
	_log("Reported %d%%%s" % [roundi(chance * 100), ", done" if done else ""])
	if done:
		_decide()


## Rolls with the chance, as the server would, and shows the result.
func _decide() -> void:
	_decided = true
	var passed := _rng.randf() < _chance
	_log("Rolled %d%%: %s" % [roundi(_chance * 100), "passed" if passed else "failed"])
	_overlay.show_minigame({
		"kind": "skill_check",
		"ends_in_ms": maxi(_ends_at_msec - Time.get_ticks_msec(), 0),
		"result": "passed" if passed else "failed",
	})


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and key.keycode == KEY_ESCAPE:
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


func _on_again_button_pressed() -> void:
	if current != null:
		play(current)
	else:
		play_night(_fights_only)


func _on_practice_toggle_toggled(_on: bool) -> void:
	if current != null:
		play(current)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
