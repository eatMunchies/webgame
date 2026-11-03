class_name WheelCheck
extends SkillCheck

## The timing dial: a needle sweeps around a TimingWheel, and the player
## presses while it is in the gold zone, `presses` times. Each hit is an
## equal share of the chance, so 3 hits of 5 is 60%. Every press is
## reported, so a stage that ends early counts the presses not made as
## misses. In practice it counts hits in a row instead. Tuned by a
## WheelCheckDef.
##
## Space presses, and so does tapping it.

## How long a press flashes the ring, in seconds.
const FLASH_SECONDS := 0.25

var presses := 5
var wheel := TimingWheel.new()
## The presses so far, true for each hit. Practice presses aren't counted.
var marks: Array[bool] = []
## Practice hits in a row.
var streak := 0

var _flash := 0.0
var _flash_color := GOLD


func _ready() -> void:
	var tuning := def as WheelCheckDef
	if tuning != null:
		presses = tuning.presses
		wheel.zone = deg_to_rad(tuning.zone_degrees)
		wheel.speed = TAU * tuning.turns_per_second
		wheel.move_zone()


func hint() -> String:
	if practice:
		return "Press Space or tap when the needle is in the gold zone. Nothing rides on this one; keep the streak going."
	return "Press Space or tap when the needle is in the gold zone, %d times. Each hit is a 1 in %d chance your action works." % [presses, presses]


func status() -> String:
	if marks.is_empty():
		return ""
	return "%d/%d hits" % [hits(), presses]


func practice_status() -> String:
	return "Streak %d" % streak


func hits() -> int:
	return marks.count(true)


func press() -> void:
	if waiting():
		return
	var hit := wheel.in_zone()
	if practice:
		streak = streak + 1 if hit else 0
	else:
		marks.append(hit)
		report(float(hits()) / presses, marks.size() >= presses)
	_flash = FLASH_SECONDS
	_flash_color = GOLD if hit else MISS_COLOR
	wheel.move_zone()
	changed.emit()


func _process(delta: float) -> void:
	wheel.advance(delta)
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or key.echo:
		return
	if key.physical_keycode == KEY_SPACE:
		if key.pressed:
			press()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if is_tap(event):
		press()
		accept_event()


func _draw() -> void:
	var center := size / 2
	var radius := minf(size.x, size.y) * 0.4
	var ring := Color(1, 1, 1, 0.25)
	if _flash > 0.0:
		ring = ring.lerp(_flash_color, _flash / FLASH_SECONDS)
	draw_arc(center, radius, 0, TAU, 48, ring, 3.0)
	# Wheel angles start at 12 o'clock; draw_arc's start at 3 o'clock.
	var start := wheel.zone_start - PI / 2
	draw_arc(center, radius, start, start + wheel.zone, 12, GOLD, 5.0)
	var tip := center + Vector2.from_angle(wheel.angle - PI / 2) * (radius + 3)
	draw_line(center, tip, Color.WHITE, 2.0)
	draw_circle(center, 2.5, Color.WHITE)
	if not practice or not marks.is_empty():
		_draw_marks(Vector2(center.x, center.y + radius + 10))


## The presses as a row of pips: gold for a hit, red for a miss, hollow for
## one still to come.
func _draw_marks(middle: Vector2) -> void:
	for i in presses:
		var at := middle + Vector2((i - (presses - 1) / 2.0) * 10, 0)
		if i < marks.size():
			draw_circle(at, 3, GOLD if marks[i] else MISS_COLOR)
		else:
			draw_arc(at, 3, 0, TAU, 12, Color(1, 1, 1, 0.4), 1.0)
