class_name ParchmentPanel
extends PanelContainer

## A panel of the simulated Salem: parchment, drawn by
## shaders/parchment.gdshader under whatever the panel holds. Two tiers:
## - SHEET, for the HUD's working panels (roster, clock, chat): flat edges,
##   so many panels side by side don't turn into noise.
## - DOCUMENT, for things handed to you (the role card, the text box): a
##   torn edge and darker margins, like a page.
##
## It follows Tokens.candle, so it turns candlelit at night by itself. Its
## padding comes from the theme's PanelContainer box; its fill is the
## shader's. The material shades only the panel's own drawing: children
## (text above all) draw plainly.

enum Tier { SHEET, DOCUMENT }

const SHADER := preload("res://shaders/parchment.gdshader")

@export var tier := Tier.SHEET:
	set(value):
		tier = value
		_apply()
## Makes this panel's grain its own, so neighbours don't match.
@export var seed := 0.0:
	set(value):
		seed = value
		_apply()

var _material := ShaderMaterial.new()
var _candle := -1.0


func _init() -> void:
	_material.shader = SHADER
	material = _material


func _ready() -> void:
	# Keep the theme's padding, but draw no box of its own under the paper.
	var box := get_theme_stylebox("panel")
	var margins := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		margins.set_content_margin(side, box.get_content_margin(side) if box else 0.0)
	add_theme_stylebox_override("panel", margins)
	resized.connect(_apply)
	_apply()


func _process(_delta: float) -> void:
	if not is_equal_approx(_candle, Tokens.candle):
		_apply()


func _draw() -> void:
	# The shader paints over this, using its UV for where on the sheet it is.
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


## Keeps the panel's look in step with its size, tier and the night.
func _apply() -> void:
	_candle = Tokens.candle
	_material.set_shader_parameter("size", size)
	_material.set_shader_parameter("deckle", 1.0 if tier == Tier.DOCUMENT else 0.0)
	_material.set_shader_parameter("candle", Tokens.candle)
	_material.set_shader_parameter("seed", seed)
	_material.set_shader_parameter("paper_day", Palette.PAPER)
	_material.set_shader_parameter("paper_night", Palette.PAPER_NIGHT)
	_material.set_shader_parameter("edge_day", Palette.PAPER_EDGE)
	_material.set_shader_parameter("edge_night", Palette.PAPER_EDGE_NIGHT)
	_material.set_shader_parameter("candle_light", Palette.CANDLE)
	queue_redraw()
