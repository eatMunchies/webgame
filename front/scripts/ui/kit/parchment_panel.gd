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
## padding is the design system's (Tokens.SPACE_SM at the sides, a step less
## top and bottom, a step more on a Document); its fill is the shader's. The
## material shades only the panel's own drawing: children (text above all)
## draw plainly.

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
## Give everything in the panel the paper theme (UiTheme.paper()), kept in
## step with the night like the paper itself.
@export var paper_theme := false:
	set(value):
		paper_theme = value
		_apply()

var _material := ShaderMaterial.new()
var _candle := -1.0


func _init() -> void:
	_material.shader = SHADER
	material = _material


func _ready() -> void:
	# Padding only: the paper is the shader's, not a box's.
	var margins := StyleBoxEmpty.new()
	var side_pad := Tokens.SPACE_SM if tier == Tier.SHEET else Tokens.SPACE_MD
	margins.content_margin_left = side_pad
	margins.content_margin_right = side_pad
	margins.content_margin_top = side_pad - 1
	margins.content_margin_bottom = side_pad - 1
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
	if paper_theme:
		theme = UiTheme.paper()
	queue_redraw()
