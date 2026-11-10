class_name GolfCheck
extends ArcadeCheck

## Flappy Golf (see GolfGame). Holing out in par or fewer passes for sure;
## each flap over par takes some chance off, and a ball not holed when the
## stage ends is worth nothing. In practice each hole is followed by a new
## one, and it counts holes and how many were under par. Tuned by a
## GolfCheckDef.
##
## Left or A flaps left, Right or D flaps right, Up, W or Space flaps
## straight up. A tap on the left or right half of the course flaps that
## way.

const GRASS := Color(0.27, 0.6, 0.27)
const DIRT := Color(0.36, 0.26, 0.17)
const FLAG := Color(0.92, 0.3, 0.3)
## Floating blocks, with a lighter top edge to show where the ball can land.
const STONE := Color(0.45, 0.47, 0.55)
const STONE_TOP := Color(0.7, 0.72, 0.8)
## How long a holed ball shows before practice tees up the next hole.
const NEXT_HOLE_SECONDS := 1.0

var tuning: GolfCheckDef
var game := GolfGame.new()
## Practice holes played, and those holed in par or fewer.
var holes := 0
var holes_in_par := 0

var _next_hole_left := 0.0


func _ready() -> void:
	tuning = def as GolfCheckDef
	if tuning == null:
		tuning = GolfCheckDef.new()


func hint() -> String:
	return "Left/A and Right/D flap that way, Up/Space flaps straight up, or tap a side. Get it in the cup in par %d." % tuning.par


func status() -> String:
	if game.flaps == 0:
		return ""
	return "%d flap%s, par %d" % [game.flaps, "" if game.flaps == 1 else "s", tuning.par]


func practice_status() -> String:
	return "%d/%d in par" % [holes_in_par, holes]


## What holing out in `flaps` flaps is worth.
func chance_for(flaps: int) -> float:
	var over := maxi(flaps - tuning.par, 0)
	return maxf(1.0 - over * tuning.chance_per_extra_flap, tuning.min_chance)


func flap(direction: int) -> void:
	if not game.holed:
		game.flap(direction)
		changed.emit()


func _process(delta: float) -> void:
	if game.advance(delta):
		if practice:
			holes += 1
			if game.flaps <= tuning.par:
				holes_in_par += 1
		else:
			report(chance_for(game.flaps), true)
		_next_hole_left = NEXT_HOLE_SECONDS
		changed.emit()
	if game.holed and practice:
		_next_hole_left -= delta
		if _next_hole_left <= 0.0:
			game.new_hole()
			changed.emit()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or key.echo:
		return
	var direction := 0
	match key.physical_keycode:
		KEY_LEFT, KEY_A:
			direction = -1
		KEY_RIGHT, KEY_D:
			direction = 1
		KEY_UP, KEY_W, KEY_SPACE:
			direction = 0
		_:
			return
	if key.pressed:
		flap(direction)
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if is_tap(event):
		flap(-1 if to_field(event.position).x < FIELD.x / 2 else 1)
		accept_event()


func _draw() -> void:
	fit_field()
	var hills := PackedVector2Array([Vector2(0, FIELD.y)])
	for x in game.ground.size():
		hills.append(Vector2(x, game.ground[x]))
	hills.append(FIELD)
	draw_colored_polygon(hills, DIRT)
	draw_polyline(hills.slice(1, -1), GRASS, 2.0)
	for block in game.blocks:
		draw_rect(block, STONE)
		draw_rect(Rect2(block.position, Vector2(block.size.x, 1)), STONE_TOP)
	# The cup, then the flag above it.
	var green := game.ground[game.cup_x - 1]
	draw_rect(Rect2(game.cup_x, green, GolfGame.CUP_WIDTH, GolfGame.CUP_DEPTH), Color(0.05, 0.05, 0.05))
	var pole_x := game.cup_x + GolfGame.CUP_WIDTH / 2.0
	draw_line(Vector2(pole_x, green), Vector2(pole_x, green - 16), Color.WHITE, 0.8)
	draw_colored_polygon(PackedVector2Array([
		Vector2(pole_x, green - 16), Vector2(pole_x + 7, green - 13.5), Vector2(pole_x, green - 11),
	]), FLAG)
	draw_circle(game.ball, GolfGame.BALL_RADIUS, Color.WHITE)
	# Which way a tap on each half flaps, for touch screens.
	var arrow := Color(1, 1, 1, 0.3)
	draw_colored_polygon(PackedVector2Array([Vector2(5, 20), Vector2(11, 16), Vector2(11, 24)]), arrow)
	draw_colored_polygon(PackedVector2Array([Vector2(FIELD.x - 5, 20), Vector2(FIELD.x - 11, 16), Vector2(FIELD.x - 11, 24)]), arrow)
	draw_string(ThemeDB.fallback_font, Vector2(4, 9), "Flaps %d  Par %d" % [game.flaps, tuning.par],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.8))
	if game.holed:
		var word := "Hole in one!" if game.flaps == 1 else ("Under par!" if game.flaps < tuning.par else "In!")
		draw_centered(word, Vector2(FIELD.x / 2, FIELD.y * 0.35), 10, GOLD)
