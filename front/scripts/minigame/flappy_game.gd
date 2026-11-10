class_name FlappyGame
extends RefCounted

## Flappy Bird: the bird falls, a flap throws it up, and pipes scroll toward
## it with a gap to fly through. Touching a pipe or the ground ends the run;
## the top of the field is a ceiling the bird just bumps.
##
## Nothing moves until the first flap, so the player starts when ready.
## Positions are in ArcadeCheck field units, y pointing down.

const FIELD := ArcadeCheck.FIELD
const BIRD_X := 32.0
const BIRD_RADIUS := 3.5
const GROUND := FIELD.y - 8
const GRAVITY := 400.0
const FLAP_SPEED := -125.0
const PIPE_WIDTH := 12.0
## How far apart the pipes are, and how fast they come.
const PIPE_SPACING := 58.0
const SCROLL_SPEED := 60.0
## Where the first pipe starts, so it arrives a second or so after the first flap.
const FIRST_PIPE_X := 100.0

## How tall the gap in each pipe is.
var gap := 38.0
var bird_y := FIELD.y * 0.4
var velocity := 0.0
## Each pipe as Vector2(left edge, middle of its gap).
var pipes: Array[Vector2] = []
## Pipes flown through this run.
var passed := 0
var started := false
var crashed := false

var _rng := RandomNumberGenerator.new()
## Pipes passed, counting removed ones, so each counts once.
var _next_pipe := 0


## A seed of -1 picks a random one.
func _init(seed_value := -1, gap_size := 38.0) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	gap = gap_size
	reset()


## Puts the bird back at the start, waiting for its first flap.
func reset() -> void:
	bird_y = FIELD.y * 0.4
	velocity = 0.0
	passed = 0
	_next_pipe = 0
	started = false
	crashed = false
	pipes = []
	for i in 3:
		pipes.append(Vector2(FIRST_PIPE_X + i * PIPE_SPACING, _gap_middle()))


func flap() -> void:
	if crashed:
		return
	started = true
	velocity = FLAP_SPEED


## Moves time on. Returns how many pipes were passed in this step.
func advance(delta: float) -> int:
	if not started or crashed:
		return 0
	velocity += GRAVITY * delta
	bird_y += velocity * delta
	if bird_y < BIRD_RADIUS:
		bird_y = BIRD_RADIUS
		velocity = maxf(velocity, 0.0)
	var before := passed
	for i in pipes.size():
		pipes[i].x -= SCROLL_SPEED * delta
	# A pipe is passed once its right edge is behind the bird.
	while _next_pipe < pipes.size() and pipes[_next_pipe].x + PIPE_WIDTH < BIRD_X - BIRD_RADIUS:
		_next_pipe += 1
		passed += 1
	if pipes[0].x + PIPE_WIDTH < 0:
		pipes.pop_front()
		_next_pipe -= 1
	if pipes[-1].x < FIELD.x:
		pipes.append(Vector2(pipes[-1].x + PIPE_SPACING, _gap_middle()))
	if bird_y + BIRD_RADIUS >= GROUND or _hits_pipe():
		crashed = true
		bird_y = minf(bird_y, GROUND - BIRD_RADIUS)
	return passed - before


## The top and bottom of a pipe's gap.
func gap_top(pipe: Vector2) -> float:
	return pipe.y - gap / 2


func gap_bottom(pipe: Vector2) -> float:
	return pipe.y + gap / 2


func _hits_pipe() -> bool:
	for pipe in pipes:
		if BIRD_X + BIRD_RADIUS > pipe.x and BIRD_X - BIRD_RADIUS < pipe.x + PIPE_WIDTH:
			if bird_y - BIRD_RADIUS < gap_top(pipe) or bird_y + BIRD_RADIUS > gap_bottom(pipe):
				return true
	return false


func _gap_middle() -> float:
	var margin := gap / 2 + 8
	return _rng.randf_range(margin, GROUND - margin)
