class_name TypingView
extends Control

## The typing test's words, drawn by its TypingCheck, inside the text prompt
## that a touch screen types it in. A tap on it brings the keyboard back if
## it was put away.

const HEIGHT := 44.0

var check: TypingCheck


func _ready() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if is_instance_valid(check):
		check.draw_words_on(self, size)
