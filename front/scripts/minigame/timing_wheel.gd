class_name TimingWheel
extends RefCounted

## The skill check's dial: a needle sweeps around a circle, and the player
## presses while it is inside the target zone. A passive game uses the same
## dial for practice, so the two look alike from across the room.
##
## Angles are in radians, clockwise from straight up.

## How fast the needle turns, in radians per second.
const SPEED := TAU * 0.75
## How wide the target zone is.
const ZONE := deg_to_rad(60.0)

var angle := 0.0
var zone_start := 0.0

var _rng := RandomNumberGenerator.new()


## A seed of -1 picks a random one.
func _init(seed_value := -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	move_zone()


## Puts the zone somewhere new, at least a quarter turn ahead of the needle
## so there is time to react.
func move_zone() -> void:
	zone_start = fposmod(angle + _rng.randf_range(PI / 2, TAU - ZONE - PI / 4), TAU)


func advance(delta: float) -> void:
	angle = fposmod(angle + SPEED * delta, TAU)


func in_zone() -> bool:
	return fposmod(angle - zone_start, TAU) <= ZONE
