class_name TextPrompt
extends Control

## A text box that opens in the middle of the screen, over everything, to
## type into: a whisper, the last will, or on a touch screen any text field
## the player taps. A phone's keyboard covers the bottom of the screen and
## would hide a text box down there, so the prompt sits in the upper middle,
## where it stays in sight while the keyboard is up.
##
## `ask()` opens it with a title, the text to start from, and a callback
## that gets the text when the player confirms; Cancel, Escape or a tap on
## the dimmed backdrop closes it without calling back. Multiline prompts (the
## will) have a Paste button, which reads the clipboard (on the web it asks
## the browser, which may ask the player first).
##
## `attach()` makes a LineEdit open the prompt when tapped on a touch screen,
## instead of taking the keyboard where it sits.
##
## Make one per screen with `TextPrompt.create(parent)`, which fills the
## parent and stays hidden until asked.

## Where the panel's top sits, as a share of the screen's height.
const TOP_SHARE := 0.14
## The panel's width in units, and its share of the screen at most.
const WIDTH := 220.0
const WIDTH_SHARE := 0.92
## How tall the multiline box is, in units.
const MULTILINE_HEIGHT := 84.0
const BACKDROP := Color(0, 0, 0, 0.55)
## The text size in the boxes, and the room between a multiline box's lines:
## bigger than the HUD's, so a click or tap lands the caret where it's meant.
const TEXT_SIZE := 8
const LINE_SPACING := 3
## How long after opening a tap on the backdrop is ignored. One tap on a
## phone arrives as a touch and a made-up mouse click; when the first opens
## the prompt, the second would land on the backdrop and close it again.
const BACKDROP_GRACE_MSEC := 400

## Whether this device has a touch screen, where tapped text fields open the
## prompt. A browser doesn't always say so up front, so a phone's browser
## (Godot's web_android and web_ios features) counts too, and the first real
## touch on any screen with a prompt switches it on (see _input).
static var touch := _detect_touch()


static func _detect_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
			or OS.has_feature("web_android") or OS.has_feature("web_ios")

var _panel := PanelContainer.new()
var _title := Label.new()
var _line := LineEdit.new()
var _multi := TextEdit.new()
var _paste := Button.new()
var _confirm := Button.new()
var _on_done := Callable()
## When the prompt last opened, for BACKDROP_GRACE_MSEC.
var _opened_msec := 0
var _backdrop := ColorRect.new()
## Kept while the browser reads the clipboard, which calls it back later.
var _paste_callback: JavaScriptObject


## Makes a hidden prompt that fills `parent` (a Control, or a CanvasLayer
## for the whole screen), drawn over its other children.
static func create(parent: Node) -> TextPrompt:
	var prompt := TextPrompt.new()
	parent.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return prompt


func _init() -> void:
	visible = false
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	theme = HudStyle.build()
	_backdrop.color = BACKDROP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	_panel.add_child(rows)
	_title.theme_type_variation = "HudTitle"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_title)
	_line.text_submitted.connect(func(_text: String) -> void: _finish())
	_line.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	rows.add_child(_line)
	_multi.custom_minimum_size.y = MULTILINE_HEIGHT
	for box: Control in [_line, _multi]:
		box.add_theme_font_size_override("font_size", TEXT_SIZE)
	_multi.add_theme_constant_override("line_spacing", LINE_SPACING)
	_multi.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	rows.add_child(_multi)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	rows.add_child(buttons)
	_paste.text = "Paste"
	_paste.focus_mode = Control.FOCUS_NONE
	_paste.pressed.connect(_on_paste_pressed)
	buttons.add_child(_paste)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_finish)
	buttons.add_child(_confirm)
	resized.connect(_place)


## Opens the prompt. `on_done` gets the text when the player confirms.
## Options: `multiline` (a box for several lines), `paste` (a Paste button,
## on by default for multiline), `confirm` (the confirm button's text, "Send"
## by default) and `placeholder`.
func ask(title: String, text: String, on_done: Callable, options := {}) -> void:
	var multiline: bool = options.get("multiline", false)
	_title.text = title
	_on_done = on_done
	_confirm.text = options.get("confirm", "Send")
	_line.visible = not multiline
	_multi.visible = multiline
	_paste.visible = options.get("paste", multiline)
	var box: Control = _multi if multiline else _line
	box.set("text", text)
	box.set("placeholder_text", options.get("placeholder", ""))
	visible = true
	_opened_msec = Time.get_ticks_msec()
	_place()
	box.grab_focus()
	if multiline:
		_multi.set_caret_line(_multi.get_line_count() - 1)
		_multi.set_caret_column(_multi.get_line(_multi.get_line_count() - 1).length())
	else:
		_line.caret_column = _line.text.length()


## Closes without calling back.
func close() -> void:
	_line.release_focus()
	_multi.release_focus()
	visible = false
	_on_done = Callable()


## Makes `field` open the prompt when tapped, titled `title`. Confirming puts
## the text in the field; with `submit` it also submits it, as pressing Enter
## in the field would. Options: `always` (on every screen; otherwise only on
## a touch screen, and the field works as it is elsewhere), `paste` (a
## Paste button), `confirm` (the confirm button's text) and `placeholder`
## (the box's, if not the field's).
func attach(field: LineEdit, title: String, submit := false, options := {}) -> void:
	var always: bool = options.get("always", false)
	# Decided at each tap, since a touch screen may only make itself known
	# with its first touch.
	field.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed)
		if not pressed or visible or not (touch or always):
			return
		# The field never takes the keyboard itself; the prompt does.
		field.virtual_keyboard_enabled = false
		field.accept_event()
		field.release_focus()
		ask(title, field.text, func(text: String) -> void:
			field.text = text
			field.text_changed.emit(text)
			if submit:
				field.text_submitted.emit(text),
			{"placeholder": options.get("placeholder", field.placeholder_text),
				"confirm": options.get("confirm", "Send" if submit else "Done"),
				"paste": options.get("paste", false)}))


func _place() -> void:
	if not visible:
		return
	var width := minf(WIDTH, size.x * WIDTH_SHARE)
	# The wrapped title gets the panel's inner width up front: a wrapping label
	# measures its height at the width it has, and with none it would wrap
	# every word onto its own line and stretch the panel.
	var inner := width - _panel.get_theme_stylebox("panel").get_minimum_size().x
	_title.custom_minimum_size.x = inner
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width, 0)
	_panel.position = Vector2((size.x - width) / 2.0, roundf(size.y * TOP_SHARE))
	# Wrapped labels only know their height after a layout pass.
	_shrink.call_deferred()


func _shrink() -> void:
	_panel.size = Vector2(_panel.size.x, 0)


func _finish() -> void:
	var text: String = _multi.text if _multi.visible else _line.text
	var done := _on_done
	close()
	if done.is_valid():
		done.call(text)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch = true
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - _opened_msec < BACKDROP_GRACE_MSEC:
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		close()


func _on_paste_pressed() -> void:
	if OS.has_feature("web"):
		# The page can't read the clipboard on its own; the browser hands it
		# over later, if the player allows it.
		var clipboard: JavaScriptObject = JavaScriptBridge.get_interface("navigator").clipboard
		if clipboard == null:
			return
		_paste_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
			_insert(str(args[0]) if args.size() > 0 else ""))
		clipboard.readText().then(_paste_callback)
	else:
		_insert(DisplayServer.clipboard_get())


func _insert(text: String) -> void:
	if text == "" or not visible:
		return
	if _multi.visible:
		_multi.insert_text_at_caret(text)
		_multi.grab_focus()
	else:
		_line.insert_text_at_caret(text.strip_edges())
		_line.grab_focus()
