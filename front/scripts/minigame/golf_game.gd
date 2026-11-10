class_name GolfGame
extends RefCounted

## Flappy Golf: a golf ball that flaps. Each flap throws the ball up and to
## the left or right, and it falls, bounces and rolls (downhill, too) on a hilly course
## until it drops into the cup at the far end. The score is the flaps it
## took, against par.
##
## The ground is a height for every field unit across (`ground`). Each hole
## mixes a few random features (hills, dips, flat-topped mesas, runs of
## bumps) between the tee and the cup, a narrow dip near the far edge, and
## sometimes mirrors the lot so the cup is on the left. A rise steeper than
## STEP is a wall the ball bounces off, which is what keeps it in the cup.
##
## Some holes also have floating blocks (`blocks`): the ball bounces off
## their sides and bottoms, and lands and rolls on their tops. They always
## leave room to roll under them, and never cover the cup.
##
## Positions are in ArcadeCheck field units, y pointing down.

const FIELD := ArcadeCheck.FIELD
const BALL_RADIUS := 2.0
const GRAVITY := 260.0
const FLAP_UP := -105.0
const FLAP_SIDE := 48.0
## How fast rolling slows the ball, in field units per second per second.
const ROLL_FRICTION := 70.0
const BOUNCE := 0.35
## The highest rise the ball rolls up; anything steeper is a wall.
const STEP := 2.5
const CUP_WIDTH := 7
const CUP_DEPTH := 7.0
## How far in from its edge the tee is.
const TEE_X := 14.0
## The tee's height, and the highest any ground can rise to: about what two
## flaps can clear from the tee.
const BASE := FIELD.y - 14
const HIGHEST_GROUND := BASE - 44
## What a course can be made of, between the tee and the cup.
const FEATURES := ["hill", "hill", "dip", "mesa", "bumps"]
## How often a hole has floating blocks, and the gap left under them, more
## than enough for the ball to roll through.
const BLOCK_CHANCE := 0.5
const BLOCK_CLEARANCE := 12.0
## How often a course is flipped to play right to left.
const MIRROR_CHANCE := 0.35
## How much of its speed along the ground a landing ball keeps; the turf
## takes the rest.
const IMPACT_KEEP := 0.6
## How hard a ball has to hit the ground, in field units per second straight
## into it, to bounce rather than settle and roll.
const BOUNCE_MIN := 30.0
## How much faster than gravity the ground has to fall away under a rolling
## ball, in field units per second, before the ball flies off it, as off a
## crest or into the cup. Less than this, it follows the ground.
const LEAVE_SPEED := 25.0
## Physics steps per frame, so a fast ball can't skip through a wall.
const SUBSTEPS := 4

## The ground's height at each whole x, from 0 to FIELD.x.
var ground := PackedFloat32Array()
## The cup's left edge; it spans CUP_WIDTH to the right.
var cup_x := 0
## Where the ball starts, near whichever edge the cup isn't.
var tee_x := TEE_X
## Floating blocks, in field units.
var blocks: Array[Rect2] = []
var ball := Vector2.ZERO
var velocity := Vector2.ZERO
## Flaps taken on this hole.
var flaps := 0
var holed := false
## Whether the ball is rolling on the ground, rather than in the air.
var on_ground := false

var _rng := RandomNumberGenerator.new()


## A seed of -1 picks a random one.
func _init(seed_value := -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	new_hole()


## Lays out a new course and puts the ball on the tee.
func new_hole() -> void:
	# Laid out tee on the left, then maybe mirrored at the end.
	cup_x = _rng.randi_range(92, 126)
	var features := _pick_features()
	# The course can climb to a raised green or fall to a sunken one.
	var green_rise := _rng.randf_range(-16.0, 8.0)
	var wave_height := _rng.randf_range(0.0, 4.0)
	var wave_length := _rng.randf_range(0.05, 0.16)
	var wave := _rng.randf_range(0, TAU)
	ground = PackedFloat32Array()
	for x in int(FIELD.x) + 1:
		var y := BASE + lerpf(0.0, green_rise, smoothstep(TEE_X + 10, cup_x - 10, x))
		y += sin(x * wave_length + wave) * wave_height
		for feature in features:
			y += _feature_height(feature, x)
		# A level tee, easing into the course.
		y = lerpf(BASE, y, smoothstep(TEE_X + 4, TEE_X + 14, x))
		ground.append(clampf(y, HIGHEST_GROUND, FIELD.y - 3))
	# Level the green round the cup, easing into the course either side,
	# high enough that the cup's floor stays above the field's bottom.
	var green := minf(ground[cup_x], FIELD.y - CUP_DEPTH - 3)
	for x in range(cup_x - 16, cup_x + CUP_WIDTH + 16):
		if x >= 0 and x < ground.size():
			var away := maxf(cup_x - 5 - x, x - (cup_x + CUP_WIDTH + 4))
			ground[x] = lerpf(green, ground[x], smoothstep(0.0, 11.0, away))
	for x in range(cup_x, cup_x + CUP_WIDTH):
		ground[x] = green + CUP_DEPTH
	_place_blocks()
	tee_x = TEE_X
	if _rng.randf() < MIRROR_CHANCE:
		_mirror()
	ball = Vector2(tee_x, ground[int(tee_x)] - BALL_RADIUS)
	velocity = Vector2.ZERO
	flaps = 0
	holed = false
	on_ground = true


## One to three random features for the stretch between the tee and the
## cup, each as {kind, x, width, height}.
func _pick_features() -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for i in _rng.randi_range(1, 3):
		var kind: String = FEATURES[_rng.randi_range(0, FEATURES.size() - 1)]
		var feature := {"kind": kind, "x": _rng.randf_range(TEE_X + 22, cup_x - 24)}
		match kind:
			"hill":
				feature["width"] = _rng.randf_range(8, 20)
				feature["height"] = _rng.randf_range(12, 38)
			"dip":
				feature["width"] = _rng.randf_range(6, 14)
				feature["height"] = -_rng.randf_range(5, 10)
			"mesa":
				feature["width"] = _rng.randf_range(8, 18)
				feature["height"] = _rng.randf_range(10, 26)
				# How long its sides are: short ones make cliffs.
				feature["edge"] = _rng.randf_range(3, 12)
			"bumps":
				feature["width"] = _rng.randf_range(14, 24)
				feature["height"] = _rng.randf_range(4, 9)
		features.append(feature)
	return features


## How much `feature` raises the ground at `x` (y points down, so raising
## is negative).
func _feature_height(feature: Dictionary, x: float) -> float:
	var from_middle: float = x - feature["x"]
	var width: float = feature["width"]
	var height: float = feature["height"]
	match feature["kind"]:
		"hill", "dip":
			return -height * exp(-pow(from_middle / width, 2))
		"mesa":
			var edge: float = feature["edge"]
			return -height * (1.0 - smoothstep(width - edge, width, absf(from_middle)))
		"bumps":
			return -height * maxf(sin(from_middle * 0.4), 0.0) * exp(-pow(from_middle / width, 2))
	return 0.0


## Sometimes floats a block or two over the course, with room to roll under
## it and clear of the tee and the cup's mouth.
func _place_blocks() -> void:
	blocks.clear()
	if _rng.randf() >= BLOCK_CHANCE:
		return
	for i in _rng.randi_range(1, 2):
		for attempt in 12:
			var width := _rng.randf_range(8, 18)
			var height := _rng.randf_range(3, 5)
			var left := _rng.randf_range(TEE_X + 12, cup_x - 8 - width)
			var top_ground := FIELD.y
			for x in range(floori(left) - 2, ceili(left + width) + 3):
				top_ground = minf(top_ground, ground[clampi(x, 0, ground.size() - 1)])
			var lowest_top := top_ground - BLOCK_CLEARANCE - height
			if lowest_top < 12:
				continue
			var block := Rect2(left, _rng.randf_range(12, lowest_top), width, height)
			if blocks.all(func(other: Rect2) -> bool: return not other.grow(6).intersects(block)):
				blocks.append(block)
				break


## Flips the course left to right, so the tee is on the right.
func _mirror() -> void:
	ground.reverse()
	# The cup's whole x run from cup_x to cup_x + CUP_WIDTH - 1 maps to
	# FIELD.x - that.
	cup_x = int(FIELD.x) - (cup_x + CUP_WIDTH - 1)
	tee_x = FIELD.x - TEE_X
	for i in blocks.size():
		var block := blocks[i]
		blocks[i] = Rect2(FIELD.x - block.end.x, block.position.y, block.size.x, block.size.y)


## Flaps the ball up, and sideways by `direction`: -1 left, 1 right, 0 straight up.
func flap(direction: int) -> void:
	if holed:
		return
	flaps += 1
	velocity = Vector2(FLAP_SIDE * signi(direction), FLAP_UP)
	on_ground = false


## The ground's height under `x`, a straight line between the heights at
## whole x, as it's drawn, so the ball rolls smoothly. A rise steeper than
## STEP is a wall instead, kept sharp: the ground stays level up to it.
func ground_at(x: float) -> float:
	var left := clampi(floori(x), 0, ground.size() - 1)
	var right := mini(left + 1, ground.size() - 1)
	if absf(ground[right] - ground[left]) > STEP:
		return ground[left]
	return lerpf(ground[left], ground[right], clampf(x - left, 0.0, 1.0))


## How steeply the ground falls away to the right under `x`: positive when
## it's lower to the right (y points down), 1 for a 45 degree slope.
func slope_at(x: float) -> float:
	return (ground_at(x + 1) - ground_at(x - 1)) / 2


## Whether `x` is over the cup.
func over_cup(x: float) -> bool:
	return x >= cup_x and x < cup_x + CUP_WIDTH


## Moves time on. Returns true on the step the ball drops in.
func advance(delta: float) -> bool:
	if holed:
		return false
	var step := delta / SUBSTEPS
	for i in SUBSTEPS:
		_step(step)
		if holed:
			return true
	return false


## The direction along the ground under `x`, rightward: (1, slope), made
## unit length. Its y is the sine of the slope's angle, positive downhill.
func tangent_at(x: float) -> Vector2:
	return Vector2(1, slope_at(x)).normalized()


func _step(delta: float) -> void:
	if on_ground:
		_roll(delta)
	else:
		_fly(delta)


## A ball in the air: gravity pulls it down, and it bounces off walls and
## lands on the ground.
func _fly(delta: float) -> void:
	velocity.y += GRAVITY * delta
	var next := ball + velocity * delta
	# The sides of the field are walls too.
	if next.x < BALL_RADIUS or next.x > FIELD.x - BALL_RADIUS:
		next.x = clampf(next.x, BALL_RADIUS, FIELD.x - BALL_RADIUS)
		velocity.x = -velocity.x * BOUNCE
	if next.y < BALL_RADIUS:
		next.y = BALL_RADIUS
		velocity.y = maxf(velocity.y, 0.0)
	# Rising more than a step to reach the next x is hitting a wall.
	if floori(next.x) != floori(ball.x) and ground_at(next.x) < minf(ground_at(ball.x), ball.y + BALL_RADIUS) - STEP:
		next.x = ball.x
		velocity.x = -velocity.x * BOUNCE
	next = _hit_blocks(next)
	if on_ground:
		ball = next
		return
	var floor_y := ground_at(next.x)
	if next.y + BALL_RADIUS >= floor_y:
		next.y = floor_y - BALL_RADIUS
		_land(next.x, tangent_at(next.x), true)
	ball = next


## Keeps the ball at `next` out of every block, as a round ball against a
## box: if the nearest point of a block is closer than the ball's radius,
## the ball is pushed straight away from it. Coming down on the flat top, it
## lands as on the ground. Anywhere else (a side, the bottom, or a corner,
## which pushes it off at an angle) the part of its speed into the block
## bounces back if it's hard, or stops if it's soft, and the rest carries
## on, so a ball rolling off an edge curves round the corner. Returns where
## the ball ends up.
func _hit_blocks(next: Vector2) -> Vector2:
	for block in blocks:
		var nearest := next.clamp(block.position, block.end)
		var away := next - nearest
		var normal: Vector2
		if away.length() >= BALL_RADIUS:
			continue
		# Only straight over the top, not past a corner, is landing on it.
		var on_top := away.x == 0.0 and away.y < 0.0
		if away.length() > 0.0001:
			normal = away.normalized()
		else:
			# The ball's middle got inside: out through the nearest face.
			var faces := [next.x - block.position.x, block.end.x - next.x, next.y - block.position.y, block.end.y - next.y]
			var face: int = faces.find(faces.min())
			normal = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN][face]
			nearest = [Vector2(block.position.x, next.y), Vector2(block.end.x, next.y),
					Vector2(next.x, block.position.y), Vector2(next.x, block.end.y)][face]
		next = nearest + normal * BALL_RADIUS
		if on_top:
			_land(next.x, Vector2.RIGHT, false)
			if on_ground:
				return next
			continue
		var into := -velocity.dot(normal)
		if into > 0.0:
			velocity += normal * into * (1.0 + (BOUNCE if into > BOUNCE_MIN else 0.0))
	return next


## The floating block the ball rests on at `x`, with its bottom at `bottom`,
## or -1 if it's not on one.
func block_under(x: float, bottom: float) -> int:
	for i in blocks.size():
		var block := blocks[i]
		if x >= block.position.x and x <= block.end.x and absf(block.position.y - bottom) < 0.5:
			return i
	return -1


## The ball hits the ground at `x`, running along `along_dir` there (a
## block's top is flat), and `is_ground` when it's the course rather than a
## block, so over the cup it drops in. Its speed is split into the part along
## the ground and the part straight into it. The part into the ground bounces
## back (or, if it's soft, dies and the ball settles), and the turf takes
## some of the part along it. So a ball dropping onto an uphill has little
## speed left up the slope, and gravity soon rolls it back.
func _land(x: float, along_dir: Vector2, is_ground: bool) -> void:
	if is_ground and over_cup(x):
		holed = true
		velocity = Vector2.ZERO
		return
	# Out of the ground, perpendicular to the slope (y points down).
	var out := Vector2(along_dir.y, -along_dir.x)
	var along := velocity.dot(along_dir) * IMPACT_KEEP
	var into := -velocity.dot(out)
	if into > BOUNCE_MIN:
		velocity = along_dir * along + out * into * BOUNCE
	else:
		velocity = along_dir * along
		on_ground = true


## A ball rolling on the ground, or on a block's flat top. Its speed is along the slope: gravity's pull
## along it (g times the sine of its angle) speeds it downhill and slows it
## uphill, and friction slows it either way, so it stops on gentle ground.
func _roll(delta: float) -> void:
	var bottom := ball.y + BALL_RADIUS
	var on_block := block_under(ball.x, bottom) >= 0
	var along_dir := Vector2.RIGHT if on_block else tangent_at(ball.x)
	# Keep the speed round bends in the ground, pointed along the new slope.
	var speed := velocity.length() * signf(velocity.dot(along_dir))
	speed += GRAVITY * along_dir.y * delta
	speed = move_toward(speed, 0.0, ROLL_FRICTION * delta)
	var next_x := ball.x + speed * along_dir.x * delta
	if next_x < BALL_RADIUS or next_x > FIELD.x - BALL_RADIUS:
		next_x = clampf(next_x, BALL_RADIUS, FIELD.x - BALL_RADIUS)
		speed = -speed * BOUNCE
	if not on_block and floori(next_x) != floori(ball.x) and ground_at(next_x) < ground_at(ball.x) - STEP:
		next_x = ball.x
		speed = -speed * BOUNCE
	velocity = along_dir * speed
	# Following the ground means falling (or rising) this fast. If that's
	# faster than gravity could pull it down, the ground has fallen away and
	# the ball flies off.
	var next_block := block_under(next_x, bottom)
	var floor_y := blocks[next_block].position.y if next_block >= 0 else ground_at(next_x)
	var follow := (floor_y - BALL_RADIUS - ball.y) / delta
	if follow > velocity.y + GRAVITY * delta + LEAVE_SPEED:
		on_ground = false
		velocity.y += GRAVITY * delta
		ball = Vector2(next_x, ball.y + velocity.y * delta)
		return
	ball = Vector2(next_x, floor_y - BALL_RADIUS)
	if next_block < 0 and over_cup(next_x):
		holed = true
		velocity = Vector2.ZERO
