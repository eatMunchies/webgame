class_name Guillotine
extends Node2D

## The guillotine in the middle of the town, where the podium used to be,
## drawn in code as pixel art so its blade can fall. Its origin is where the
## front of its stone base meets the ground. The accused stands just in front
## of it (ACCUSED_SPOT) through their trial, with their head at the lunette,
## the wooden collar between the posts.
##
## drop() lets the blade fall; raise() winches it back up. It's world art
## like the cul-de-sac, so its colors are the art's own.

## Where the accused stands, from the guillotine's origin.
const ACCUSED_SPOT := Vector2(0, 9)
const DROP_SECONDS := 0.22
const RAISE_SECONDS := 1.6

const STONE := Color(0.56, 0.55, 0.57)
const STONE_DARK := Color(0.38, 0.37, 0.4)
const STONE_LIGHT := Color(0.7, 0.69, 0.7)
const WOOD := Color(0.45, 0.29, 0.17)
const WOOD_DARK := Color(0.29, 0.18, 0.1)
const WOOD_LIGHT := Color(0.58, 0.4, 0.24)
const STEEL := Color(0.78, 0.81, 0.85)
const STEEL_EDGE := Color(0.95, 0.96, 0.98)
const IRON := Color(0.24, 0.24, 0.27)
const ROPE := Color(0.76, 0.66, 0.45)
const OUTLINE := Color(0.12, 0.09, 0.07)

## The blade's top edge when raised, and where it stops on the lunette.
const BLADE_TOP := -55.0
const BLADE_BOTTOM := -35.0

## How far down the blade is: 0 raised, 1 fallen.
var fall := 0.0:
	set(value):
		fall = value
		queue_redraw()

var _tween: Tween


func drop() -> void:
	_animate(1.0, DROP_SECONDS, Tween.EASE_IN)


func raise() -> void:
	_animate(0.0, RAISE_SECONDS, Tween.EASE_IN_OUT)


func _animate(to: float, seconds: float, ease: Tween.EaseType) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	_tween.tween_property(self, "fall", to, seconds)


func _draw() -> void:
	# The stone base, two steps.
	_box(Rect2(-21, -9, 42, 9), STONE, STONE_DARK)
	draw_rect(Rect2(-20, -8, 40, 1), STONE_LIGHT)
	_box(Rect2(-16, -13, 32, 5), STONE, STONE_DARK)
	draw_rect(Rect2(-15, -12, 30, 1), STONE_LIGHT)
	# The two posts, with grooves for the blade.
	for x: float in [-12.0, 8.0]:
		_box(Rect2(x, -62, 4, 50), WOOD, OUTLINE)
		draw_rect(Rect2(x + 1, -61, 1, 48), WOOD_LIGHT)
	# The crossbeam.
	_box(Rect2(-14, -65, 28, 5), WOOD, OUTLINE)
	draw_rect(Rect2(-13, -64, 26, 1), WOOD_LIGHT)
	# The rope from the crossbeam down the right post to a cleat.
	draw_rect(Rect2(12, -60, 1, 36), ROPE)
	draw_rect(Rect2(12, -25, 3, 2), IRON)
	# The blade and its weight, between the posts.
	var top := lerpf(BLADE_TOP, BLADE_BOTTOM, fall)
	draw_rect(Rect2(0, -60, 1, top - (-60)), ROPE)
	_box(Rect2(-8, top, 16, 5), IRON, OUTLINE)
	var blade := PackedVector2Array([
		Vector2(-8, top + 5), Vector2(8, top + 5), Vector2(8, top + 9), Vector2(-8, top + 13)])
	draw_colored_polygon(blade, STEEL)
	draw_line(Vector2(-8, top + 13), Vector2(8, top + 9), STEEL_EDGE, 1.0)
	# The lunette: a wooden collar with a hole for the neck.
	_box(Rect2(-8, -26, 16, 8), WOOD, OUTLINE)
	draw_rect(Rect2(-7, -25, 14, 1), WOOD_LIGHT)
	draw_rect(Rect2(-8, -22, 16, 1), WOOD_DARK)
	draw_circle(Vector2(0, -22), 2.5, OUTLINE)


## A filled box with a one-pixel outline.
func _box(rect: Rect2, fill: Color, edge: Color) -> void:
	draw_rect(rect, edge)
	draw_rect(rect.grow(-1), fill)
