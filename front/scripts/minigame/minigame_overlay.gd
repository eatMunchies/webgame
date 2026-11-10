class_name MinigameOverlay
extends PanelContainer

## The night's minigames, shown over the town while one is going.
##
## The server gives each living player one minigame per stage of the night.
## This shows it, takes the player's input, and reports through its signals;
## the town passes those to the GameClient. It never talks to the server
## itself, so it can be driven directly in tests.
##
## - A skill check is one of `skill_checks`, picked at random by weight (see
##   SkillCheckDef and SkillCheck). It works out its own chance of passing, and each report is
##   passed on through `check_reported`.
## - A fight shows both fighters (the opponent masked) as the server last
##   described them, read each frame from `fight_source`. Strike, grab, and
##   guard, which is a tap that comes up after GameClient.GUARD_RAISE_MS,
##   holds for GameClient.GUARD_MS and then can't be raised again for a
##   moment (the Guard button greys out). A press made while winding up,
##   dazed, or for a guard still cooling down, is held for BUFFER_SECONDS and
##   sent as soon as it can be, so quick play isn't dropped. A fight runs
##   until a knockout, so it shows no clock. A bar over each
##   fighter fills as their move winds up, and hits, blocks and misses pop up
##   over the fighters.
## - A passive game is practice, nothing riding on it: one of
##   `practice_checks`, picked at random by weight. The same practice game
##   carries on from stage to stage through the night, until a skill check or
##   fight interrupts it; the next practice after that is picked afresh, and
##   never the one just played. Once a
##   skill check is decided it carries on as practice until the stage ends,
##   and a decided fight gives way to a practice game, so a finished player
##   looks as busy as anyone.
##
## Every minigame is titled with just its name, with no instructions, and
## the time left shows only while something rides on it.
##
## A skill check or fight opens with a countdown in the middle ("Skill
## Check" or "Fight starting", then 3, 2, 1), so a player who was idly
## practicing knows this one counts. The game waits, hidden and frozen,
## until the countdown is over, and moves made during it are dropped. The
## server adds the countdown to the stage (MINIGAME_INTRO_MS), so it never
## takes from the time to play, and the time shown is the play time left,
## in whole seconds, held still while the countdown runs.
##
## Keys in a fight: J or Z strikes; K or X grabs; L, C or Space guards.
## Everything can be tapped as well. A skill check takes its own keys.

## How the player's skill check is going: the chance it should pass, from 0
## to 1, and whether they're done.
signal check_reported(chance: float, done: bool)
## The player started a fight move: "strike" or "grab".
signal fight_move(move: String)
## The player raised their guard (always true now that a guard drops on its
## own; kept a bool to match GameClient.fight_guard).
signal guard_changed(up: bool)

const GOLD := SkillCheck.GOLD
const YOU_COLOR := Color(0.45, 0.72, 1)
const OPPONENT_COLOR := SkillCheck.MISS_COLOR
const DAZED_COLOR := Color(0.55, 0.55, 0.6)
const RESULT_TEXT := {
	"passed": "Passed!",
	"failed": "Failed. Your action won't work tonight.",
	"won": "You won the fight!",
	"lost": "You lost the fight.",
}
## How long a hit flashes, in seconds.
const FLASH_SECONDS := 0.25
## How long a fight press made while busy waits to be sent.
const BUFFER_SECONDS := 0.35
## How long a popup ("HIT!", "BLOCKED!") floats, and how long a hit shakes.
const POPUP_SECONDS := 0.7
const SHAKE_SECONDS := 0.2
const GRAB_COLOR := Color(1, 0.55, 0.45)
const GUARD_COLOR := Color(0.85, 0.9, 1)

## The kinds of skill check to pick from when the chance counts.
@export var skill_checks: Array[SkillCheckDef] = []
## The games to pick from for practice. Falls back on `skill_checks` when
## empty.
@export var practice_checks: Array[SkillCheckDef] = []

## Returns the fight as GameClient.fight() describes it. Read every frame
## during a fight.
var fight_source := Callable()
## The skill check being played, for real or for practice, or null.
var check: SkillCheck
## "", "skill_check", "fight" or "passive".
var kind := ""
var attacking := false
## "" while it is being played, then "passed", "failed", "won" or "lost".
var result := ""
var rolled := false
## The last fight description read from fight_source.
var fight := {}

var _rng := RandomNumberGenerator.new()
## The practice game being played this night, kept (hidden) between stages
## so the next stage's practice carries on with it. Dropped when a skill
## check or fight interrupts it, or the night it was picked in is over.
var _practice: SkillCheck
## The phase `_practice` was picked in, like "Night 2".
var _practice_phase := ""
## The last practice game picked, which the next pick skips, so a new night
## or the end of a fight always brings a different game.
var _last_practice_def: SkillCheckDef
## A fight press waiting for the fighter to be free: "strike", "grab" or
## "guard", and when it was pressed.
var _queued := ""
var _queued_msec := 0
## Popups floating over the fighters, as {text, side, color, age}.
var _popups: Array[Dictionary] = []
var _shake_left := 0.0
var _ends_at_msec := 0
## How long the countdown before a skill check or fight lasts, in seconds.
## Tests set it to 0 to play straight away.
@export var intro_seconds := GameClient.MINIGAME_INTRO_MS / 1000.0

## Seconds left on each fighter's hit flash.
var _hit_flash := {"you": 0.0, "opponent": 0.0}
## Whether the countdown is running, and when it ends, on the same clock as
## the stage's end so the two always agree.
var _intro_running := false
var _intro_ends_msec := 0

@onready var title: Label = %Title
@onready var time_left: Label = %TimeLeft
@onready var guard_button: Button = $Rows/FightButtons/GuardButton
@onready var canvas: Control = %Canvas
@onready var fight_buttons: Control = %FightButtons
@onready var result_label: Label = %Result


func _ready() -> void:
	visible = false
	canvas.draw.connect(_draw_canvas)
	_rng.randomize()


## Shows a minigame as GameClient.minigame() describes it, or hides the
## overlay when `info` is empty. Calling it again for the same game keeps it
## going and only updates its result and time. A result never goes back to
## "", so one that does is the next stage's game (two fights in a row).
func show_minigame(info: Dictionary) -> void:
	if info.is_empty():
		hide_minigame()
		return
	var new_kind: String = info["kind"]
	var new_result: String = info.get("result", "")
	if new_kind != kind or not visible or (new_result == "" and result != ""):
		_start(new_kind)
	attacking = info.get("attacking", false)
	rolled = info.get("rolled", false)
	result = new_result
	if result != "":
		_end_intro()
	_ends_at_msec = Time.get_ticks_msec() + int(info.get("ends_in_ms", 0))
	if practicing():
		if check == null:
			_start_check(true)
		else:
			check.practice = true
	visible = true
	_update_text()


func hide_minigame() -> void:
	_queued = ""
	_end_check()
	kind = ""
	visible = false


## Whether the game is being played for practice, with nothing riding on it.
func practicing() -> bool:
	return kind == "passive" or (kind != "" and result != "")


## Whether the countdown before a skill check or fight is still going.
func in_intro() -> bool:
	return _intro_running


## Seconds left on the countdown.
func _intro_left() -> float:
	return maxi(_intro_ends_msec - Time.get_ticks_msec(), 0) / 1000.0


## Whether the skill check is done and waits on the server.
func rolling() -> bool:
	return kind == "skill_check" and result == "" and check != null and check.waiting()


func strike() -> void:
	_press("strike")


func grab() -> void:
	_press("grab")


func guard() -> void:
	_press("guard")


## Sends a fight press now, or holds it while the fighter is busy.
func _press(action: String) -> void:
	if kind != "fight" or result != "" or in_intro():
		return
	if _busy(action):
		_queued = action
		_queued_msec = Time.get_ticks_msec()
	else:
		_send(action)


func _send(action: String) -> void:
	_queued = ""
	if action == "guard":
		guard_changed.emit(true)
	else:
		fight_move.emit(action)


## Whether the player can't `action` yet, as last described: winding up or
## dazed, or for a guard, one still up or cooling down.
func _busy(action: String) -> bool:
	if not fight.has("you"):
		return false
	var you: Dictionary = fight["you"]
	if action == "guard" and you.get("guard_cooldown_ms", 0) > 0:
		return true
	return you["move"] != "" or you["staggered_ms"] > 0


func _start(new_kind: String) -> void:
	_queued = ""
	_popups.clear()
	_shake_left = 0.0
	_end_check()
	kind = new_kind
	result = ""
	rolled = false
	fight = {}
	_hit_flash = {"you": 0.0, "opponent": 0.0}
	if kind == "skill_check" or kind == "fight":
		_drop_practice()
	if kind == "skill_check":
		_start_check(false)
	_intro_running = intro_seconds > 0.0 and (kind == "skill_check" or kind == "fight")
	_intro_ends_msec = Time.get_ticks_msec() + int(intro_seconds * 1000)
	if check != null and in_intro():
		check.visible = false
		check.process_mode = PROCESS_MODE_DISABLED


## Ends the countdown and lets the game go.
func _end_intro() -> void:
	_intro_running = false
	if check != null:
		check.visible = true
		check.process_mode = PROCESS_MODE_INHERIT


## Fills the game area with a skill check picked from `skill_checks`, or
## for practice from `practice_checks`.
func _start_check(practice: bool) -> void:
	var phase: String = Session.client.phase_info()["title"]
	if practice and _practice != null and _practice_phase == phase:
		check = _practice
		return
	var defs := practice_checks if practice and not practice_checks.is_empty() else skill_checks
	if practice and defs.size() > 1 and _last_practice_def != null:
		var others: Array[SkillCheckDef] = []
		for other in defs:
			if other != _last_practice_def:
				others.append(other)
		defs = others
	var def := SkillCheckDef.pick(defs, _rng)
	if def == null:
		push_error("MinigameOverlay: no skill check to pick from")
		return
	check = def.instantiate()
	check.practice = practice
	check.reported.connect(check_reported.emit)
	check.changed.connect(_update_text)
	canvas.add_child(check)
	check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if practice:
		_drop_practice()
		_last_practice_def = def
		_practice = check
		_practice_phase = phase


## Lets go of the check shown now. The night's practice game stays for the
## next stage; anything else is freed.
func _end_check() -> void:
	if check != null and check != _practice:
		check.queue_free()
	check = null


## Frees the kept practice game, so the next practice is picked afresh.
func _drop_practice() -> void:
	if _practice != null:
		if check == _practice:
			check = null
		_practice.queue_free()
		_practice = null


func _process(delta: float) -> void:
	if not visible:
		return
	if kind == "fight" and fight_source.is_valid():
		_read_fight(fight_source.call())
	if in_intro() and Time.get_ticks_msec() >= _intro_ends_msec:
		_end_intro()
	if _queued != "":
		if Time.get_ticks_msec() - _queued_msec > BUFFER_SECONDS * 1000 or result != "":
			_queued = ""
		elif not _busy(_queued):
			_send(_queued)
	for side in _hit_flash:
		_hit_flash[side] = maxf(_hit_flash[side] - delta, 0.0)
	_shake_left = maxf(_shake_left - delta, 0.0)
	for popup in _popups:
		popup["age"] += delta
	_popups = _popups.filter(func(popup: Dictionary) -> bool: return popup["age"] < POPUP_SECONDS)
	# Play time left: held still while the countdown runs.
	var left := _ends_at_msec - maxi(Time.get_ticks_msec(), _intro_ends_msec if in_intro() else 0)
	left = maxi(left, 0)
	time_left.text = "%ds" % ceili(left / 1000.0)
	fight_buttons.visible = kind == "fight" and result == "" and not in_intro()
	# A fight runs until a knockout, so it has no clock; the guard button
	# greys out while a guard is up or cooling down.
	time_left.visible = not practicing() and kind != "fight"
	if fight.has("you"):
		guard_button.disabled = fight["you"].get("guard_cooldown_ms", 0) > 0
	canvas.queue_redraw()


## Takes a new fight description, flashing whoever lost a hit and popping
## up what happened: a hit, a grab through a guard, a strike blocked, a
## grab that missed.
func _read_fight(view: Dictionary) -> void:
	if view.is_empty():
		return
	for side in ["you", "opponent"]:
		if not fight.has(side):
			continue
		var other := "opponent" if side == "you" else "you"
		var was: Dictionary = fight[side]
		var now: Dictionary = view[side]
		if now["hp"] < was["hp"]:
			_hit_flash[side] = FLASH_SECONDS
			var grabbed: bool = fight[other]["move"] == "grab"
			_pop("GRABBED!" if grabbed else "HIT!", side, GRAB_COLOR if grabbed else GOLD)
			if side == "you":
				_shake_left = SHAKE_SECONDS
		elif now["staggered_ms"] > 0 and was["staggered_ms"] == 0:
			# Dazed without a hit: their move failed.
			if was["move"] == "grab":
				_pop("MISSED", side, DAZED_COLOR)
			else:
				_pop("BLOCKED!", other, GUARD_COLOR)
	fight = view


func _pop(text: String, side: String, color: Color) -> void:
	_popups.append({"text": text, "side": side, "color": color, "age": 0.0})


func _update_text() -> void:
	match kind:
		"skill_check":
			title.text = check.title() if check != null else "Skill check"
		"fight":
			title.text = "Fight"
		"passive":
			title.text = check.title() if check != null else "Practice"
	result_label.text = RESULT_TEXT.get(result, "")
	var status := check.status() if check != null and kind == "skill_check" else ""
	if result != "" and rolled:
		result_label.text += " (rolled)"
	elif status != "":
		if result != "":
			result_label.text += " (%s)" % status
		elif rolling():
			result_label.text = "%s, rolling..." % status
		else:
			result_label.text = status
	if practicing() and check != null:
		result_label.text = ("%s  %s" % [result_label.text, check.practice_status()]).strip_edges()
	# Practice is titled by the game being played, even after a decided fight.
	if practicing() and check != null:
		title.text = check.title()
	time_left.visible = not practicing() and kind != "fight"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or key.echo:
		return
	var handled := true
	match key.physical_keycode:
		KEY_SPACE:
			if kind == "fight" and result == "":
				if key.pressed:
					guard()
			else:
				handled = false
		KEY_J, KEY_Z:
			if key.pressed:
				strike()
		KEY_K, KEY_X:
			if key.pressed:
				grab()
		KEY_L, KEY_C:
			if key.pressed:
				guard()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_strike_button_pressed() -> void:
	strike()


func _on_grab_button_pressed() -> void:
	grab()


func _on_guard_button_down() -> void:
	guard()


# ----- Drawing -----


## The countdown, or the fight while it goes on. A skill check draws itself.
func _draw_canvas() -> void:
	if in_intro():
		_draw_intro()
	elif kind == "fight" and result == "":
		_draw_fight()


## "Skill Check" or "Fight starting" over a big 3, 2, 1, each number
## fading as its second runs out.
func _draw_intro() -> void:
	var font := ThemeDB.fallback_font
	var middle := canvas.size / 2
	var heading := "Fight starting" if kind == "fight" else "Skill Check"
	_draw_centered(font, heading, middle + Vector2(0, -16), 10, GOLD)
	if kind == "skill_check" and check != null:
		_draw_centered(font, check.title(), middle + Vector2(0, -5), 7, Color.WHITE)
	var intro_left := _intro_left()
	var second := maxi(ceili(intro_left), 1)
	var fade := intro_left - (second - 1)
	_draw_centered(font, str(second), middle + Vector2(0, 14), 22, Color(1, 1, 1, 0.35 + 0.65 * fade))


## Draws `text` with its middle at `center`.
func _draw_centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var at := Vector2(center.x - 200, center.y + font.get_ascent(font_size) / 2 - 1)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 400, font_size, color)


func _draw_fight() -> void:
	if fight.is_empty():
		return
	var size := canvas.size
	var ground := size.y * 0.8
	if _shake_left > 0.0:
		var strength := 2.0 * _shake_left / SHAKE_SECONDS
		canvas.draw_set_transform(Vector2(randf_range(-strength, strength), randf_range(-strength, strength)))
	var feet := {"you": Vector2(size.x * 0.3, ground), "opponent": Vector2(size.x * 0.7, ground)}
	_draw_fighter(fight["you"], feet["you"], 1, YOU_COLOR, "you", false)
	_draw_fighter(fight["opponent"], feet["opponent"], -1, OPPONENT_COLOR, "opponent", true)
	var font := ThemeDB.fallback_font
	for popup in _popups:
		var t: float = popup["age"] / POPUP_SECONDS
		var at: Vector2 = feet[popup["side"]] + Vector2(0, -62 - 10 * t)
		var color: Color = popup["color"]
		color.a = 1.0 - t * t
		_draw_centered(font, popup["text"], at, 9, color)
	canvas.draw_set_transform(Vector2.ZERO)


## Draws one fighter standing at `feet`, facing right when `facing` is 1 and
## left when -1. The opponent wears a mask.
func _draw_fighter(fighter: Dictionary, feet: Vector2, facing: int, color: Color,
		side: String, masked: bool) -> void:
	var font := ThemeDB.fallback_font
	var dazed: bool = fighter["staggered_ms"] > 0
	var body_color := DAZED_COLOR if dazed else color
	if _hit_flash[side] > 0.0:
		body_color = body_color.lerp(Color.WHITE, _hit_flash[side] / FLASH_SECONDS)
	var body := Rect2(feet + Vector2(-6, -26), Vector2(12, 26))
	canvas.draw_rect(body, body_color)
	var head := feet + Vector2(0, -32)
	canvas.draw_circle(head, 6, Color(0.1, 0.1, 0.12) if masked else body_color)
	if masked:
		canvas.draw_string(font, head + Vector2(-2.5, 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

	# Hits left, as pips over the head.
	var max_hp: int = fight.get("max_hp", 3)
	for i in max_hp:
		var pip := Rect2(feet + Vector2(-max_hp * 3.5 + i * 7, -46), Vector2(5, 4))
		canvas.draw_rect(pip, color if i < fighter["hp"] else Color(1, 1, 1, 0.15))

	var shoulder := feet + Vector2(6 * facing, -20)
	var move: String = fighter["move"]
	if move != "":
		# The windup grows the arm toward the other fighter and fills a bar
		# over its head, so it can be read and answered in time: guard a
		# strike, strike a grab.
		var move_color := GOLD if move == "strike" else GRAB_COLOR
		var windup := maxf(float(fighter["windup_ms"]), 1.0)
		var progress := clampf(1.0 - float(fighter["lands_in_ms"]) / windup, 0.0, 1.0)
		var reach := 6.0 + 18.0 * progress
		if move == "strike":
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, 0), move_color, 3.0)
		else:
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, -5), move_color, 2.0)
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, 5), move_color, 2.0)
		var bar := Rect2(feet + Vector2(-12, -54), Vector2(24, 3))
		canvas.draw_rect(bar, Color(1, 1, 1, 0.15))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), move_color)
		_draw_centered(font, move.to_upper(), feet + Vector2(0, 8), 8, move_color)
	elif fighter["guarding"]:
		# The shield fades as the guard runs out.
		var left := clampf(float(fighter.get("guard_ms", GameClient.GUARD_MS)) / GameClient.GUARD_MS, 0.0, 1.0)
		var shield_color := Color(GUARD_COLOR, 0.35 + 0.65 * left)
		canvas.draw_rect(Rect2(feet + Vector2(9 * facing - 1.5, -30), Vector2(3, 24)), shield_color)
		_draw_centered(font, "GUARD", feet + Vector2(0, 8), 8, shield_color)
	elif fighter.get("guard_raised", false):
		# Coming up: the shield grows and a bar fills until it blocks.
		var raise := clampf(1.0 - float(fighter["raising_ms"]) / GameClient.GUARD_RAISE_MS, 0.0, 1.0)
		var rising_color := Color(GUARD_COLOR, 0.35)
		canvas.draw_rect(Rect2(feet + Vector2(9 * facing - 1.5, -6 - 24 * raise), Vector2(3, 24 * raise)), rising_color)
		var bar := Rect2(feet + Vector2(-12, -54), Vector2(24, 3))
		canvas.draw_rect(bar, Color(1, 1, 1, 0.15))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * raise, bar.size.y)), GUARD_COLOR)
		_draw_centered(font, "GUARD", feet + Vector2(0, 8), 8, rising_color)
	elif dazed:
		_draw_centered(font, "DAZED", feet + Vector2(0, 8), 8, DAZED_COLOR)
