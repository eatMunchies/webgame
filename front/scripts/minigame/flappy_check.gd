class_name FlappyCheck
extends ArcadeCheck

## Flappy Bird (see FlappyGame). Each pipe flown through is an equal share
## of the chance, so 3 of 5 is 60%; crashing finishes the check with the
## pipes so far. In practice a crash starts a new run, and it keeps the best.
## Tuned by a FlappyCheckDef.
##
## Space, Up or W flaps, and so does a tap.

const PIPE_COLOR := Color(0.3, 0.72, 0.32)
const GROUND_COLOR := Color(0.55, 0.42, 0.25)
const BIRD_COLOR := Color(1, 0.82, 0.25)
## How long a crash shows before a practice run starts over.
const RESTART_SECONDS := 0.8

var pipes_needed := 5
var game: FlappyGame
## The most pipes in a practice run.
var best := 0

var _restart_left := 0.0


func _ready() -> void:
	var tuning := def as FlappyCheckDef
	if tuning == null:
		tuning = FlappyCheckDef.new()
	pipes_needed = tuning.pipes
	game = FlappyGame.new(-1, tuning.gap)


func hint() -> String:
	return "Space, Up or tap to flap. Fly through the pipes."


func status() -> String:
	return "%d/%d pipes" % [mini(game.passed, pipes_needed), pipes_needed] if game.started else ""


func practice_status() -> String:
	return "Best %d" % best


func flap() -> void:
	if not game.crashed:
		game.flap()


func _process(delta: float) -> void:
	var was_crashed := game.crashed
	if game.advance(delta) > 0:
		if practice:
			best = maxi(best, game.passed)
		else:
			report(float(mini(game.passed, pipes_needed)) / pipes_needed, game.passed >= pipes_needed)
		changed.emit()
	if game.crashed and not was_crashed:
		report(float(game.passed) / pipes_needed, true)
		_restart_left = RESTART_SECONDS
		changed.emit()
	# Practice starts over after a crash, including one made for real before
	# the check turned into practice.
	if game.crashed and practice:
		_restart_left -= delta
		if _restart_left <= 0.0:
			game.reset()
			changed.emit()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or key.echo:
		return
	if key.physical_keycode in [KEY_SPACE, KEY_UP, KEY_W]:
		if key.pressed:
			flap()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if is_tap(event):
		flap()
		accept_event()


func _draw() -> void:
	fit_field()
	for pipe in game.pipes:
		_draw_pipe(Rect2(pipe.x, 0, FlappyGame.PIPE_WIDTH, game.gap_top(pipe)), false)
		_draw_pipe(Rect2(pipe.x, game.gap_bottom(pipe), FlappyGame.PIPE_WIDTH,
				FlappyGame.GROUND - game.gap_bottom(pipe)), true)
	draw_rect(Rect2(0, FlappyGame.GROUND, FIELD.x, FIELD.y - FlappyGame.GROUND), GROUND_COLOR)
	draw_rect(Rect2(0, FlappyGame.GROUND, FIELD.x, 1.5), PIPE_COLOR)
	_draw_bird(Vector2(FlappyGame.BIRD_X, game.bird_y))
	draw_centered(str(game.passed), Vector2(FIELD.x / 2, 10), 10, Color.WHITE)


## A pipe with a lip at the end facing the gap.
func _draw_pipe(rect: Rect2, lip_on_top: bool) -> void:
	if rect.size.y <= 0.0:
		return
	draw_rect(rect, PIPE_COLOR)
	draw_rect(Rect2(rect.position.x + 2, rect.position.y, 2, rect.size.y), PIPE_COLOR.lightened(0.3))
	var lip_y := rect.position.y if lip_on_top else rect.end.y - 4
	draw_rect(Rect2(rect.position.x - 1.5, lip_y, rect.size.x + 3, 4), PIPE_COLOR.darkened(0.15))


## The bird, tipped up when rising and down when falling.
func _draw_bird(at: Vector2) -> void:
	var tilt := clampf(game.velocity / 300.0, -0.5, 1.0)
	var color := MISS_COLOR if game.crashed else BIRD_COLOR
	draw_set_transform(field_corner() + at * field_scale(), tilt, Vector2.ONE * field_scale())
	draw_circle(Vector2.ZERO, FlappyGame.BIRD_RADIUS, color)
	draw_circle(Vector2(-1, 0.8), 1.6, color.lightened(0.35))
	draw_circle(Vector2(1.4, -1.2), 1.0, Color.WHITE)
	draw_circle(Vector2(1.7, -1.2), 0.5, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([Vector2(3, -0.6), Vector2(5.5, 0.4), Vector2(3, 1.2)]), Color(0.95, 0.5, 0.15))
	field_transform()
