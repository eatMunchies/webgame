class_name SystemPanel
extends PanelContainer

## A panel of the machine that runs the simulation: black glass with a
## hairline border, corner brackets, and scanlines over everything in it
## (shaders/scanlines.gdshader). Opening it can glitch for a moment
## (glitch_in()); it never glitches on its own, so it stays easy to read.
## Its box comes from the system theme (UiTheme.system()).

const SCANLINES := preload("res://shaders/scanlines.gdshader")
## How long the corner brackets are, in units.
const BRACKET := 4.0

var _glass := ColorRect.new()
var _material := ShaderMaterial.new()


func _ready() -> void:
	_material.shader = SCANLINES
	_material.set_shader_parameter("accent", Tokens.SYS_ACCENT)
	_glass.material = _material
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.color = Color.WHITE
	# Over the contents, but not part of the layout.
	_glass.top_level = false
	_glass.z_index = 1
	add_child(_glass, false, Node.INTERNAL_MODE_BACK)
	resized.connect(_fit_glass)
	_fit_glass()


func _fit_glass() -> void:
	_glass.position = Vector2.ZERO
	_glass.size = size
	queue_redraw()


func _draw() -> void:
	# Corner brackets in the accent, over the border.
	var c := Tokens.SYS_ACCENT
	var w := 1.0
	var s := size
	for corner in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), s]:
		var dx := BRACKET if corner.x == 0 else -BRACKET
		var dy := BRACKET if corner.y == 0 else -BRACKET
		draw_line(corner, corner + Vector2(dx, 0), c, w)
		draw_line(corner, corner + Vector2(0, dy), c, w)


## A moment of glitch, as the machine brings the panel up.
func glitch_in() -> void:
	_material.set_shader_parameter("glitch", 1.0)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("glitch", v),
			1.0, 0.0, Tokens.DUR_GLITCH)
