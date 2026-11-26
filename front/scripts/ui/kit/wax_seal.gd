class_name WaxSeal
extends Control

## A round seal of wax pressed with a letter: the role card's faction mark
## (town verdigris, mafia wax red, neutral logwood), the initial in IM Fell
## small caps in pale parchment, a darker rim like the lip of real wax. A
## faction's color shows only on the role card (DESIGN.md), so this does too.

## The seal's diameter, in units.
@export var diameter := 18.0:
	set(value):
		diameter = value
		custom_minimum_size = Vector2(value, value)
		queue_redraw()
@export var color := Tokens.WAX:
	set(value):
		color = value
		queue_redraw()
@export var letter := "":
	set(value):
		letter = value
		queue_redraw()

## The letter's size, as a share of the diameter.
const LETTER_SHARE := 0.6


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(diameter, diameter)


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	# A rim a shade darker, a little lower, then the face.
	draw_circle(c + Vector2(0, r * 0.08), r, color.darkened(0.35), true, -1.0, true)
	draw_circle(c, r * 0.92, color, true, -1.0, true)
	draw_arc(c, r * 0.72, 0, TAU, 48, color.darkened(0.2), maxf(1.0, r * 0.06), true)
	if letter == "":
		return
	var font := Fonts.HEADING
	var font_size := maxi(1, roundi(diameter * LETTER_SHARE))
	var bounds := SeatBadge.glyph_bounds(font, letter, font_size)
	draw_string(font, c - bounds.get_center(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Tokens.INK_ON_DARK)
