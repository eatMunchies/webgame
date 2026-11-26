class_name TextPrompt
extends Modal

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
## It's a Modal: a parchment Document in Salem with the title in IM Fell, the
## paper's ruled field, and a wax seal to confirm; on the machine's screens
## (`create(parent, true)`) the same on glass.
##
## Make one per screen with `TextPrompt.create(parent)`, which fills the
## parent and stays hidden until asked.

## The panel's width in units.
const WIDTH := 220.0
## How tall the multiline box is, in units.
const MULTILINE_HEIGHT := 84.0
## The room between a multiline box's lines.
const LINE_SPACING := 3
## The caret is thick (the theme's) and doesn't blink, so it's always clear
## where typing goes; a multiline box also tints the line the caret is on.
const CURRENT_LINE := Color(Palette.INK, 0.06)
## The Paste button's icon, in units.
const PASTE_ICON := 9

## Whether this device has a touch screen, where tapped text fields open the
## prompt. A browser doesn't always say so up front, so a phone's browser
## (Godot's web_android and web_ios features) counts too, and the first real
## touch on any screen with a prompt switches it on (see _input).
static var touch := _detect_touch()


static func _detect_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
			or OS.has_feature("web_android") or OS.has_feature("web_ios")

var _title := Label.new()
var _line := LineEdit.new()
var _multi := TextEdit.new()
var _paste := Button.new()
var _confirm := Button.new()
var _on_done := Callable()
## Kept while the browser reads the clipboard, which calls it back later.
var _paste_callback: JavaScriptObject


## Makes a hidden prompt that fills `parent` (a Control, or a CanvasLayer
## for the whole screen), drawn over its other children; on the machine's
## glass with `on_glass`.
static func create(parent: Node, on_glass := false) -> TextPrompt:
	var prompt := TextPrompt.new()
	prompt.system = on_glass
	prompt.fill(parent)
	return prompt


func _init() -> void:
	super()
	z_index = Tokens.Z_PROMPT
	width = WIDTH
	place = Place.UPPER


func _ready() -> void:
	super()
	_title.theme_type_variation = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_title)
	_line.text_submitted.connect(func(_text: String) -> void: _finish())
	_line.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	rows.add_child(_line)
	_multi.custom_minimum_size.y = MULTILINE_HEIGHT
	_line.caret_blink = false
	_multi.caret_blink = false
	_multi.highlight_current_line = true
	_multi.add_theme_color_override("current_line_color",
			Color(Tokens.SYS_ACCENT, 0.08) if system else CURRENT_LINE)
	_multi.add_theme_constant_override("line_spacing", LINE_SPACING)
	_multi.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	rows.add_child(_multi)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", Tokens.SPACE_SM)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(buttons)
	_paste.text = "Paste"
	_paste.theme_type_variation = "QuietButton"
	_paste.icon = Icons.get_icon("paste")
	_paste.add_theme_constant_override("icon_max_width", PASTE_ICON)
	_paste.focus_mode = Control.FOCUS_NONE
	_paste.pressed.connect(_on_paste_pressed)
	buttons.add_child(_paste)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = "QuietButton"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_confirm.theme_type_variation = "SysPrimary" if system else "WaxButton"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_finish)
	buttons.add_child(_confirm)


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
	show_modal()
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
	_on_done = Callable()
	super()


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


func _finish() -> void:
	var text: String = _multi.text if _multi.visible else _line.text
	var done := _on_done
	close()
	if done.is_valid():
		done.call(text)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch = true
	super(event)


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
