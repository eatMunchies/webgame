class_name SeatBadge
extends Control

## A player's number in a circle of their seat's dye (Tokens.seat), a
## parchment numeral in the middle: how a player is spotted at a glance, the
## same in the roster and before their lines in the chat. Two digits widen
## the circle into a pill.
##
## The numeral is centered on its glyphs' actual outlines, measured from the
## font (TextServer), not on the font's line box, whose ascent and descent
## would leave it sitting low or high.

## How tall the badge is, in units; the numeral is sized to it.
const HEIGHT := 10.0
## The numeral's size, as a share of the badge's height.
const NUMERAL_SHARE := 0.68

@export var number := 1:
	set(value):
		number = value
		_resize()
## Grey the badge out, for the dead.
@export var faded := false:
	set(value):
		faded = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func _resize() -> void:
	var digits := str(number).length()
	custom_minimum_size = Vector2(HEIGHT if digits < 2 else HEIGHT + 3.0, HEIGHT)
	queue_redraw()


func _draw() -> void:
	var dye := Tokens.seat(number)
	if faded:
		dye = dye.lerp(Tokens.DEAD, 0.7)
	var box := StyleBoxFlat.new()
	box.bg_color = dye
	box.set_corner_radius_all(ceili(size.y / 2.0))
	box.anti_aliasing = true
	draw_style_box(box, Rect2(Vector2.ZERO, size))

	var font := Fonts.BODY_BOLD
	var font_size := maxi(1, roundi(size.y * NUMERAL_SHARE))
	var text := str(number)
	var bounds := glyph_bounds(font, text, font_size)
	# Place the outline's middle on the badge's middle.
	var origin := size / 2.0 - bounds.get_center()
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Tokens.INK_ON_DARK)


## The box the glyphs of `text` actually cover, relative to where drawing
## starts on the baseline: y is negative above it.
static func glyph_bounds(font: FontFile, text: String, font_size: int) -> Rect2:
	var server := TextServerManager.get_primary_interface()
	var rid := font.get_rids()[0]
	var size := Vector2i(font_size, 0)
	var bounds := Rect2()
	var x := 0.0
	for i in text.length():
		var glyph := server.font_get_glyph_index(rid, font_size, text.unicode_at(i), 0)
		# Metrics exist once the glyph is rendered at this size.
		server.font_render_glyph(rid, size, glyph)
		var offset := server.font_get_glyph_offset(rid, size, glyph)
		var extent := server.font_get_glyph_size(rid, size, glyph)
		var rect := Rect2(Vector2(x, 0) + offset, extent)
		bounds = rect if i == 0 else bounds.merge(rect)
		x += server.font_get_glyph_advance(rid, font_size, glyph).x
	return bounds
