class_name SimBackdrop
extends Control

## The machine's menus' background: near-black glass with a faint grid,
## darker toward the corners, like the floor of a simulation before anything
## is loaded into it. Fills whatever it's added to.

## The grid's spacing and line width, in this Control's units.
@export var step := 48.0
@export var line := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.SYS_BG)
	var grid := Color(Tokens.SYS_LINE, 0.45)
	var x := fmod(size.x / 2.0, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid, line)
		x += step
	var y := fmod(size.y / 2.0, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, line)
		y += step
	# Darker toward the corners: rings of black, fainter inward.
	var middle := size / 2.0
	var reach := middle.length()
	for i in 6:
		var r := reach * (1.0 - i * 0.08)
		draw_arc(middle, r, 0, TAU, 64, Color(Tokens.SYS_BG, 0.12), reach * 0.16)
