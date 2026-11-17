class_name PlazaFloor
extends ColorRect

## The start screen's endless checkerboard floor (shaders/plaza_floor.gdshader).
## Each frame it stretches over whatever the camera sees, and the shader
## fades the tiles into a void around `focus`, so wherever the player walks
## there is floor under them and haze beyond.
##
## The town puts one over itself when the player arrives and dissolves it
## from their house outward with `reveal`, so the town forms around them.

const SHADER := preload("res://shaders/plaza_floor.gdshader")
## How far past the view's edges to draw, in world pixels, so a frame where
## the camera moves before this does shows no gap.
const MARGIN := 32.0

var _shader := ShaderMaterial.new()

## Where the floor is clearest, in world pixels.
var focus := Vector2.ZERO:
	set(value):
		focus = value
		_shader.set_shader_parameter("focus", value)
## From 0, all floor, to 1, all gone. See the shader.
var reveal := 0.0:
	set(value):
		reveal = value
		_shader.set_shader_parameter("reveal", value)
## Where the dissolve starts, in world pixels.
var reveal_origin := Vector2.ZERO:
	set(value):
		reveal_origin = value
		_shader.set_shader_parameter("reveal_origin", value)


func _init() -> void:
	_shader.shader = SHADER
	material = _shader
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	cover_view()


## Stretches over everything the camera shows.
func cover_view() -> void:
	var viewport := get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	global_position = view.position - Vector2(MARGIN, MARGIN)
	size = view.size + Vector2(MARGIN, MARGIN) * 2.0
