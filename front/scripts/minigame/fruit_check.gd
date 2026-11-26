class_name FruitCheck
extends ArcadeCheck

## Fruit Ninja (see FruitGame). Each fruit sliced is an equal share of the
## chance, so 6 of 8 is 75%. It's finished when every fruit has been sliced
## or dropped, or straight away when a bomb is sliced, keeping the fruit
## sliced so far. In practice the waves keep coming, and it counts the
## fruit. Tuned by a FruitCheckDef.
##
## Swipe across the fruit: drag with the mouse or a finger.

## Fruit are targets: rings of the simulation's amber and grey over a dark
## fill, each kind its own shade, and a sliced half shows its dark inside.
const FRUIT_COLORS: Array[Color] = [
	SIM_TARGET, SIM_TEXT, Color(0.86, 0.62, 0.36), SIM_EDGE,
]
## A fruit's fill, and its inside once sliced.
const FRUIT_FILL := SIM_SOLID
const FLESH_COLOR := SIM_FIELD
## How long a swipe's trail lasts, in seconds.
const TRAIL_SECONDS := 0.15
## How long a finished wave shows before practice throws the next.
const NEXT_WAVE_SECONDS := 1.0

var game: FruitGame
## Fruit sliced over every practice wave.
var practice_sliced := 0

var _swiping := false
var _last_point := Vector2.ZERO
## The swipe's recent points in field units, each with its age, as Vector3(x, y, age).
var _trail: Array[Vector3] = []
var _next_wave_left := 0.0
var _was_over := false


func _ready() -> void:
	var tuning := def as FruitCheckDef
	if tuning == null:
		tuning = FruitCheckDef.new()
	game = FruitGame.new(-1, tuning.fruit, tuning.bombs)


func hint() -> String:
	return "Swipe across the fruit with the mouse or a finger. Don't hit the bombs."


func status() -> String:
	if game.sliced + game.dropped == 0 and not game.bombed:
		return ""
	return "%d/%d fruit%s" % [game.sliced, game.fruit_per_wave, ", bomb!" if game.bombed else ""]


func practice_status() -> String:
	return "%d fruit" % practice_sliced


## Slices along a swipe between two points on the control.
func swipe(from: Vector2, to: Vector2) -> void:
	var cut := game.swipe(to_field(from), to_field(to))
	if cut > 0 and practice:
		practice_sliced += cut
	if cut > 0 or game.bombed:
		_report()
		changed.emit()


func _report() -> void:
	report(float(game.sliced) / game.fruit_per_wave, game.over())


func _process(delta: float) -> void:
	var dropped := game.dropped
	game.advance(delta)
	if game.dropped != dropped:
		_report()
		changed.emit()
	if game.over() and not _was_over:
		_next_wave_left = NEXT_WAVE_SECONDS
	_was_over = game.over()
	if game.over() and practice:
		_next_wave_left -= delta
		if _next_wave_left <= 0.0:
			game.new_wave()
			_was_over = false
			changed.emit()
	for i in range(_trail.size() - 1, -1, -1):
		_trail[i].z += delta
		if _trail[i].z > TRAIL_SECONDS:
			_trail.remove_at(i)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# A touch also arrives as a made-up mouse event; only one may swipe.
	if is_emulated(event):
		return
	var press := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if press != null and press.button_index == MOUSE_BUTTON_LEFT or touch != null:
		_swiping = event.pressed
		_last_point = event.position
		accept_event()
	elif _swiping and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		swipe(_last_point, event.position)
		var at := to_field(event.position)
		_trail.append(Vector3(at.x, at.y, 0.0))
		_last_point = event.position
		accept_event()


func _draw() -> void:
	fit_field()
	for item in game.thrown:
		if item.bomb:
			_draw_bomb(item)
		else:
			_draw_fruit(item)
	for i in range(1, _trail.size()):
		var fade := 1.0 - _trail[i].z / TRAIL_SECONDS
		draw_line(Vector2(_trail[i - 1].x, _trail[i - 1].y), Vector2(_trail[i].x, _trail[i].y),
				Color(SIM_PLAYER, fade), 1.0 + fade * 1.5)
	draw_string(Fonts.MONO, Vector2(4, 9), "%d/%d" % [game.sliced, game.fruit_per_wave],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, SIM_TEXT)
	if game.bombed:
		draw_centered("Boom!", FIELD / 2, 12, MISS_COLOR)


## A whole fruit, or once sliced its two halves flying apart.
func _draw_fruit(item: FruitGame.Thrown) -> void:
	var skin := FRUIT_COLORS[item.kind]
	if not item.sliced:
		draw_circle(item.position, item.radius, FRUIT_FILL)
		draw_arc(item.position, item.radius, 0, TAU, 20, skin, 1.0)
		draw_arc(item.position, item.radius * 0.5, -PI * 0.9, -PI * 0.4, 6, skin, 0.6)
		return
	var apart := Vector2(item.since_sliced * 20, item.since_sliced * 6)
	for side in [-1, 1]:
		var center: Vector2 = item.position + apart * Vector2(side, 1)
		var start := PI / 2 if side < 0 else -PI / 2
		var half := PackedVector2Array([center])
		for i in 9:
			half.append(center + Vector2.from_angle(start + PI * i / 8) * item.radius)
		draw_colored_polygon(half, FLESH_COLOR)
		half.append(center)
		draw_polyline(half, skin, 0.8)


## A bomb: dark, ringed in the danger color, with a lit fuse.
func _draw_bomb(item: FruitGame.Thrown) -> void:
	if item.sliced:
		draw_circle(item.position, item.radius + item.since_sliced * 30, Color(SIM_DANGER, maxf(0.8 - item.since_sliced, 0.0)))
		return
	draw_circle(item.position, item.radius, SIM_FIELD)
	draw_arc(item.position, item.radius, 0, TAU, 16, MISS_COLOR, 0.8)
	var fuse := item.position + Vector2.from_angle(-PI / 3 + sin(item.spin) * 0.3) * (item.radius + 2.5)
	draw_line(item.position + Vector2(1.5, -item.radius + 0.5), fuse, SIM_EDGE, 0.8)
	draw_circle(fuse, 1.2 + absf(sin(item.spin * 3)) * 0.6, SIM_DANGER)
