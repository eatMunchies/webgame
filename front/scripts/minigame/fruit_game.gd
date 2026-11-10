class_name FruitGame
extends RefCounted

## Fruit Ninja: fruit is thrown up from below the field, a few at a time,
## and the player slices it with swipes before it falls back out. A wave is
## a set number of fruit with some bombs mixed in. Slicing a bomb ends the
## wave on the spot.
##
## Positions are in ArcadeCheck field units, y pointing down.

const FIELD := ArcadeCheck.FIELD
const GRAVITY := 150.0
## Seconds between throws.
const THROW_GAP := 0.45
const FRUIT_RADIUS := 6.0
const BOMB_RADIUS := 5.0
## How many kinds of fruit there are to draw.
const KINDS := 4


## One thing thrown.
class Thrown:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius := FruitGame.FRUIT_RADIUS
	var bomb := false
	## Which fruit it is, from 0 to KINDS - 1.
	var kind := 0
	var sliced := false
	## Seconds since it was sliced, for the halves flying apart.
	var since_sliced := 0.0
	## Fell back out of the field without being sliced.
	var dropped := false
	var spin := 0.0


## Everything thrown this wave, in the order thrown.
var thrown: Array[Thrown] = []
var fruit_per_wave := 8
var bombs_per_wave := 2
## Fruit sliced and fruit dropped this wave.
var sliced := 0
var dropped := 0
## A bomb was sliced, which ends the wave.
var bombed := false

var _rng := RandomNumberGenerator.new()
## What's left to throw this wave, true for a bomb.
var _to_throw: Array[bool] = []
var _throw_left := 0.0


## A seed of -1 picks a random one.
func _init(seed_value := -1, fruit := 8, bombs := 2) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	fruit_per_wave = fruit
	bombs_per_wave = bombs
	new_wave()


## Starts a wave: fruit and bombs to throw in a shuffled order. A bomb is
## never first, so the opening swipe is safe.
func new_wave() -> void:
	thrown = []
	sliced = 0
	dropped = 0
	bombed = false
	_to_throw = []
	for i in fruit_per_wave:
		_to_throw.append(false)
	for i in bombs_per_wave:
		_to_throw.insert(_rng.randi_range(1, _to_throw.size()), true)
	_throw_left = 0.3


## Whether every fruit was sliced or dropped, or a bomb went off.
func over() -> bool:
	return bombed or sliced + dropped >= fruit_per_wave


## Moves time on.
func advance(delta: float) -> void:
	if not over() and not _to_throw.is_empty():
		_throw_left -= delta
		if _throw_left <= 0.0:
			_throw(_to_throw.pop_front())
			_throw_left = THROW_GAP
	for item in thrown:
		item.velocity.y += GRAVITY * delta
		item.position += item.velocity * delta
		item.spin += delta * 4
		if item.sliced:
			item.since_sliced += delta
		elif not item.dropped and item.velocity.y > 0 and item.position.y - item.radius > FIELD.y:
			item.dropped = true
			if not item.bomb and not over():
				dropped += 1


## Slices whatever the swipe from `from` to `to` crosses. Returns the fruit
## it sliced; a bomb it crosses sets `bombed`.
func swipe(from: Vector2, to: Vector2) -> int:
	if over():
		return 0
	var cut := 0
	for item in thrown:
		if item.sliced or item.dropped:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(item.position, from, to)
		if nearest.distance_to(item.position) > item.radius:
			continue
		item.sliced = true
		if item.bomb:
			bombed = true
			return cut
		cut += 1
		sliced += 1
	return cut


## Throws one fruit or bomb up from below the field, aimed to peak in its
## upper half and drift toward the middle.
func _throw(bomb: bool) -> void:
	var item := Thrown.new()
	item.bomb = bomb
	item.radius = BOMB_RADIUS if bomb else FRUIT_RADIUS
	item.kind = _rng.randi_range(0, KINDS - 1)
	var x := _rng.randf_range(20, FIELD.x - 20)
	item.position = Vector2(x, FIELD.y + item.radius)
	var peak := _rng.randf_range(FIELD.y * 0.12, FIELD.y * 0.45)
	var rise := item.position.y - peak
	item.velocity = Vector2((FIELD.x / 2 - x) * _rng.randf_range(0.2, 0.45), -sqrt(2 * GRAVITY * rise))
	thrown.append(item)
