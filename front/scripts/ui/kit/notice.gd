class_name Notice
extends SystemPanel

## The machine speaking about itself, over whatever is on screen: a small
## pane of glass at the top of the town with a line or two in its terse log
## voice ("> desync detected, resyncing"), and a blinking cursor so it
## reads as live. It never takes input; what's under it keeps working. It
## glitches in as it appears.
##
## say() shows it with new lines (the first in the accent, the rest dim);
## clear() hides it. See DESIGN.md, Modals and dialogs.

## How often the cursor blinks, in seconds per half cycle.
const BLINK_SECONDS := 0.5

var _lines := VBoxContainer.new()
var _cursor := Label.new()


func _init() -> void:
	theme = UiTheme.system()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Tokens.Z_NOTICE
	visible = false


func _ready() -> void:
	super()
	_lines.add_theme_constant_override("separation", 0)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)


func _process(_delta: float) -> void:
	_cursor.visible = int(Time.get_ticks_msec() / (BLINK_SECONDS * 1000.0)) % 2 == 0


## Shows the notice with `lines`: the first is the news, the rest detail.
## Saying the same lines again changes nothing (and doesn't glitch).
func say(lines: PackedStringArray) -> void:
	var text := "\n".join(lines)
	if visible and get_meta("said", "") == text:
		return
	set_meta("said", text)
	if _cursor.get_parent() != null:
		_cursor.get_parent().remove_child(_cursor)
	for child in _lines.get_children():
		child.queue_free()
	for i in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var label := Label.new()
		label.theme_type_variation = "Accent" if i == 0 else "Caption"
		label.text = ("> " if i == 0 else "  ") + lines[i]
		row.add_child(label)
		if i == 0:
			_cursor.theme_type_variation = "Accent"
			_cursor.text = "_"
			row.add_child(_cursor)
		_lines.add_child(row)
	var was_visible := visible
	visible = true
	if not was_visible:
		glitch_in()


func clear() -> void:
	visible = false
	set_meta("said", "")


func _notification(what: int) -> void:
	# The cursor lives in the first line; with nothing said it has no parent
	# to free it.
	if what == NOTIFICATION_PREDELETE and _cursor.get_parent() == null:
		_cursor.free()
