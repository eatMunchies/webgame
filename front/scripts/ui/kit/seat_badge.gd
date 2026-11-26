class_name SeatBadge
extends Control

## A player's number in a circle of their seat's dye (Tokens.seat), a
## parchment numeral in the middle: how a player is spotted at a glance, the
## same in the roster and before their lines in the chat. Two digits widen
## the circle into a pill. The numeral is centered by the font's own
## measurements, not its line box, so it sits in the middle of the dye.

## How tall the badge is, in units; the numeral is sized to it.
const HEIGHT := 9.0

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
	var font_size := roundi(size.y * 0.72)
	var text := str(number)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# The digits' own height is the font's ascent less its internal leading;
	# center that, not the whole line box.
	var ascent := font.get_ascent(font_size)
	var digit_height := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y \
			- font.get_descent(font_size)
	var cap := minf(digit_height, ascent) * 0.92
	var baseline := (size.y + cap) / 2.0
	draw_string(font, Vector2((size.x - width) / 2.0, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Tokens.INK_ON_DARK)
