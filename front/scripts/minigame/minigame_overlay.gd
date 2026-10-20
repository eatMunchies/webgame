class_name MinigameOverlay
extends PanelContainer

## The night's minigames, shown over the town while one is going.
##
## The server gives each living player one minigame per stage of the night.
## This shows it, takes the player's input, and reports through its signals;
## the town passes those to the GameClient. It never talks to the server
## itself, so it can be driven directly in tests.
##
## - A skill check is a TimingWheel with one try: press while the needle is
##   in the gold zone.
## - A fight shows both fighters (the opponent masked) as the server last
##   described them, read each frame from `fight_source`. Strike, grab, and
##   hold guard.
## - A passive game is the same wheel for practice, with a score. Once a
##   skill check or fight is decided, the wheel carries on as practice until
##   the stage ends, so a finished player looks as busy as anyone.
##
## Keys: Space presses the wheel (or guards, held, in a fight); J or Z
## strikes; K or X grabs; L or C guards. Everything can be tapped as well.

## The player pressed in their skill check.
signal check_reported(passed: bool)
## The player started a fight move: "strike" or "grab".
signal fight_move(move: String)
## The player raised or lowered their guard.
signal guard_changed(up: bool)

const GOLD := Color(1, 0.8, 0.3)
const YOU_COLOR := Color(0.45, 0.72, 1)
const OPPONENT_COLOR := Color(0.92, 0.38, 0.38)
const DAZED_COLOR := Color(0.55, 0.55, 0.6)
const RESULT_TEXT := {
	"passed": "Passed!",
	"failed": "Failed. Your action won't work tonight.",
	"won": "You won the fight!",
	"lost": "You lost the fight.",
}
## How long a hit or a press flashes, in seconds.
const FLASH_SECONDS := 0.25

## Returns the fight as GameClient.fight() describes it. Read every frame
## during a fight.
var fight_source := Callable()
## "", "skill_check", "fight" or "passive".
var kind := ""
var attacking := false
## "" while it is being played, then "passed", "failed", "won" or "lost".
var result := ""
var rolled := false
## The last fight description read from fight_source.
var fight := {}
## Practice hits in a row.
var score := 0

var _wheel := TimingWheel.new()
var _pressed := false
var _guard_held := false
var _ends_at_msec := 0
## Seconds left on each flash: the wheel, then each fighter.
var _wheel_flash := 0.0
var _wheel_flash_color := GOLD
var _hit_flash := {"you": 0.0, "opponent": 0.0}

@onready var title: Label = %Title
@onready var time_left: Label = %TimeLeft
@onready var hint: Label = %Hint
@onready var canvas: Control = %Canvas
@onready var fight_buttons: Control = %FightButtons
@onready var result_label: Label = %Result


func _ready() -> void:
	visible = false
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)


## Shows a minigame as GameClient.minigame() describes it, or hides the
## overlay when `info` is empty. Calling it again with the same kind keeps
## the game going and only updates its result and time.
func show_minigame(info: Dictionary) -> void:
	if info.is_empty():
		hide_minigame()
		return
	var new_kind: String = info["kind"]
	if new_kind != kind or not visible:
		_start(new_kind)
	attacking = info.get("attacking", false)
	rolled = info.get("rolled", false)
	var new_result: String = info.get("result", "")
	if new_result != "":
		result = new_result
	_ends_at_msec = Time.get_ticks_msec() + int(info.get("ends_in_ms", 0))
	visible = true
	_update_text()


func hide_minigame() -> void:
	_set_guard(false)
	kind = ""
	visible = false


## Whether the wheel is being played for practice, with nothing riding on it.
func practicing() -> bool:
	return kind == "passive" or (kind != "" and result != "")


## The wheel, pressed: the skill check's one try, or a practice hit.
func press() -> void:
	if kind == "fight" and result == "":
		return
	var hit := _wheel.in_zone()
	if kind == "skill_check" and not _pressed:
		_pressed = true
		# Shown straight away; the server's answer confirms it.
		result = "passed" if hit else "failed"
		check_reported.emit(hit)
	elif hit:
		score += 1
	else:
		score = 0
	_wheel_flash = FLASH_SECONDS
	_wheel_flash_color = GOLD if hit else OPPONENT_COLOR
	_wheel.move_zone()
	_update_text()


func strike() -> void:
	_fight_move("strike")


func grab() -> void:
	_fight_move("grab")


func _fight_move(move: String) -> void:
	if kind == "fight" and result == "":
		fight_move.emit(move)


func _set_guard(up: bool) -> void:
	if up == _guard_held:
		return
	_guard_held = up
	if kind == "fight" and (result == "" or not up):
		guard_changed.emit(up)


func _start(new_kind: String) -> void:
	_set_guard(false)
	kind = new_kind
	result = ""
	rolled = false
	fight = {}
	score = 0
	_pressed = false
	_wheel = TimingWheel.new()
	_hit_flash = {"you": 0.0, "opponent": 0.0}


func _process(delta: float) -> void:
	if not visible:
		return
	if kind == "fight" and fight_source.is_valid():
		_read_fight(fight_source.call())
	_wheel.advance(delta)
	_wheel_flash = maxf(_wheel_flash - delta, 0.0)
	for side in _hit_flash:
		_hit_flash[side] = maxf(_hit_flash[side] - delta, 0.0)
	var left := maxi(_ends_at_msec - Time.get_ticks_msec(), 0)
	time_left.text = "%.1fs" % (left / 1000.0)
	fight_buttons.visible = kind == "fight" and result == ""
	canvas.queue_redraw()


## Takes a new fight description, flashing whoever lost a hit.
func _read_fight(view: Dictionary) -> void:
	if view.is_empty():
		return
	for side in ["you", "opponent"]:
		if fight.has(side) and view[side]["hp"] < fight[side]["hp"]:
			_hit_flash[side] = FLASH_SECONDS
	fight = view


func _update_text() -> void:
	match kind:
		"skill_check":
			title.text = "Skill check"
			hint.text = "Press Space or tap when the needle is in the gold zone. One try."
		"fight":
			title.text = "Fight! You attack." if attacking else "Fight! You're attacked."
			hint.text = "J strike, K grab, hold L guard. Strike beats open, guard beats strike, grab beats guard."
		"passive":
			title.text = "Practice"
			hint.text = "Nothing rides on this one. Keep the streak going."
	result_label.text = RESULT_TEXT.get(result, "")
	if result != "" and rolled:
		result_label.text += " (rolled)"
	if practicing():
		result_label.text = ("%s  Streak %d" % [result_label.text, score]).strip_edges()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or key.echo:
		return
	var handled := true
	match key.physical_keycode:
		KEY_SPACE:
			if kind == "fight" and result == "":
				_set_guard(key.pressed)
			elif key.pressed:
				press()
		KEY_J, KEY_Z:
			if key.pressed:
				strike()
		KEY_K, KEY_X:
			if key.pressed:
				grab()
		KEY_L, KEY_C:
			_set_guard(key.pressed)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_canvas_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if tapped and (kind != "fight" or result != ""):
		press()
		canvas.accept_event()


func _on_strike_button_pressed() -> void:
	strike()


func _on_grab_button_pressed() -> void:
	grab()


func _on_guard_button_down() -> void:
	_set_guard(true)


func _on_guard_button_up() -> void:
	_set_guard(false)


# ----- Drawing -----


func _draw_canvas() -> void:
	if kind == "fight" and result == "":
		_draw_fight()
	else:
		_draw_wheel()


func _draw_wheel() -> void:
	var size := canvas.size
	var center := size / 2
	var radius := minf(size.x, size.y) * 0.4
	var ring := Color(1, 1, 1, 0.25)
	if _wheel_flash > 0.0:
		ring = ring.lerp(_wheel_flash_color, _wheel_flash / FLASH_SECONDS)
	canvas.draw_arc(center, radius, 0, TAU, 48, ring, 3.0)
	# Wheel angles start at 12 o'clock; draw_arc's start at 3 o'clock.
	var start := _wheel.zone_start - PI / 2
	canvas.draw_arc(center, radius, start, start + TimingWheel.ZONE, 12, GOLD, 5.0)
	var tip := center + Vector2.from_angle(_wheel.angle - PI / 2) * (radius + 3)
	canvas.draw_line(center, tip, Color.WHITE, 2.0)
	canvas.draw_circle(center, 2.5, Color.WHITE)


func _draw_fight() -> void:
	if fight.is_empty():
		return
	var size := canvas.size
	var ground := size.y * 0.8
	_draw_fighter(fight["you"], Vector2(size.x * 0.3, ground), 1, YOU_COLOR, "you", false)
	_draw_fighter(fight["opponent"], Vector2(size.x * 0.7, ground), -1, OPPONENT_COLOR, "opponent", true)


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
		# The windup grows the arm toward the other fighter, so it can be read
		# and answered in time.
		var windup := maxf(float(fighter["windup_ms"]), 1.0)
		var progress := 1.0 - float(fighter["lands_in_ms"]) / windup
		var reach := 6.0 + 18.0 * progress
		if move == "strike":
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, 0), GOLD, 3.0)
		else:
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, -5), OPPONENT_COLOR.lightened(0.3), 2.0)
			canvas.draw_line(shoulder, shoulder + Vector2(reach * facing, 5), OPPONENT_COLOR.lightened(0.3), 2.0)
		canvas.draw_string(font, feet + Vector2(-12, 10), move.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, GOLD)
	elif fighter["guarding"]:
		var shield := Rect2(feet + Vector2(9 * facing - 1.5, -30), Vector2(3, 24))
		canvas.draw_rect(shield, Color(0.85, 0.9, 1))
		canvas.draw_string(font, feet + Vector2(-12, 10), "GUARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.9, 1))
	elif dazed:
		canvas.draw_string(font, feet + Vector2(-12, 10), "DAZED", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, DAZED_COLOR)
