extends SystemPanel

## The chat: a log of everything that happens, and a box to type in. The
## game is played around one table, out loud, so for people the log is mostly
## a record (your role, night results, deaths, votes), and the box is how
## terminal bots talk. It is always open; on a tall screen the HUD slides it
## over the town as a sheet, and the player can hide it to see the town.
##
## The chat is the machine's log of the session (docs/LORE.md), so it's on
## its glass, in its mono type, and see-through enough that the town shows
## behind it on a phone. Lines are colored by kind (see Session.log_line):
## what players said in light grey, led by the speaker's SeatBadge; whispers
## in cyan; game news (your role, its results, deaths, votes) in amber; and
## the machine's own lines (the lobby, the connection, errors, help) dim,
## after a `>`.
##
## The box doesn't say which channel plain text goes to (town, jail, mafia,
## dead): someone looking over your shoulder would learn your role from it.
## Typing works like the terminal client: plain text is chat, and commands like `/vote 3` are
## actions; `/help` lists them. Press Enter to start typing and Enter again
## to send; Escape goes back to walking. On a touch screen, tapping the box
## opens the HUD's TextPrompt instead, clear of the keyboard.

## A line was added to the log.
signal line_added

## Line colors, by kind.
const KIND_COLORS := {
	Session.LINE_CHAT: Tokens.LOG_SAID,
	Session.LINE_WHISPER: Tokens.LOG_WHISPER,
	Session.LINE_GAME: Tokens.LOG_GAME,
	Session.LINE_SYSTEM: Tokens.LOG_MACHINE,
}
## The speaker's badge before a line, in units: about a line's height.
const BADGE_HEIGHT := 7.0
## The send icon, in units.
const SEND_ICON := 11

## A chat line's "Name (N):" at its start.
static var _SPEAKER_NUMBER := RegEx.create_from_string("^([^\\n]*?) \\(\\d+\\):")

## Set by the style gallery, so the panel shows only the lines it's given
## (show_lines).
var preview := false

@onready var log_view: RichTextLabel = %Log
@onready var input: LineEdit = %Input
@onready var send_button: Button = %SendButton

## The HUD's prompt, which the box opens on a touch screen. Set by the HUD.
var prompt: TextPrompt:
	set(value):
		prompt = value
		prompt.attach(input, "Chat", true, {"placeholder": "Type a message"})


func _process(_delta: float) -> void:
	# Enter is how a keyboard starts typing; a phone taps the box.
	var hint := "Tap to chat" if TextPrompt.touch else "Enter to chat"
	if input.placeholder_text != hint:
		input.placeholder_text = hint


func _ready() -> void:
	theme = UiTheme.system()
	super()
	var glass := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	glass.bg_color.a = Tokens.LOG_GLASS_ALPHA
	add_theme_stylebox_override("panel", glass)
	log_view.add_theme_constant_override("line_separation", Tokens.SPACE_HAIR)
	# Plex Mono runs larger than Atkinson at the same size.
	log_view.add_theme_font_size_override("normal_font_size", Tokens.TYPE_MONO_SMALL)
	log_view.add_theme_font_size_override("bold_font_size", Tokens.TYPE_MONO_SMALL)
	input.add_theme_font_size_override("font_size", Tokens.TYPE_MONO)
	send_button.theme_type_variation = "IconButton"
	send_button.text = ""
	send_button.icon = Icons.get_icon("send")
	send_button.tooltip_text = "Send"
	send_button.add_theme_constant_override("icon_max_width", SEND_ICON)
	send_button.add_theme_color_override("icon_normal_color", Tokens.SYS_DIM)
	for state in ["icon_hover_color", "icon_pressed_color"]:
		send_button.add_theme_color_override(state, Tokens.SYS_ACCENT)
	if preview:
		return
	show_lines(Session.log_lines)
	Session.log_line.connect(_add_line)
	# Wired here rather than in hud.tscn: the HUD moves this panel between
	# screen shapes, and a scene connection is lost when its node path changes,
	# which once left Enter, Send and the touch prompt sending nothing.
	input.text_submitted.connect(_on_input_text_submitted)
	send_button.pressed.connect(_on_send_button_pressed)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and is_visible_in_tree():
		input.grab_focus()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and input.has_focus():
		input.release_focus()
		get_viewport().set_input_as_handled()


## Adds `lines` to the log: Dictionaries of text, kind and lot, as in
## Session.log_lines.
func show_lines(lines: Array) -> void:
	for line: Dictionary in lines:
		_add_line(line["text"], line["kind"], line["lot"])


## Adds one line to the log, a player's chat line led by their SeatBadge.
## Lines are added as plain text, never BBCode, because they include what
## other players typed.
func _add_line(text: String, kind: String, lot := -1) -> void:
	if lot >= 0:
		# "Bram (2): hi" reads "Bram: hi" after the badge, which has the 2.
		text = _SPEAKER_NUMBER.sub(text, "$1:", false)
		var badge := SeatBadge.texture(lot + 1, BADGE_HEIGHT)
		log_view.add_image(badge, badge.get_width(), badge.get_height(), Color.WHITE,
				INLINE_ALIGNMENT_CENTER)
		log_view.add_text(" ")
	if kind == Session.LINE_SYSTEM and not text.begins_with("!"):
		text = "> " + text
	log_view.push_color(KIND_COLORS.get(kind, KIND_COLORS[Session.LINE_GAME]))
	log_view.add_text(text)
	log_view.pop()
	log_view.newline()
	line_added.emit()


func _send() -> void:
	var text := input.text.strip_edges()
	if text == "":
		input.release_focus()
		return
	var error := Session.submit(text)
	if error != "":
		Session.add_log_line("! " + error)
		return
	input.clear()


func _on_input_text_submitted(_text: String) -> void:
	_send()
	input.release_focus()


func _on_send_button_pressed() -> void:
	_send()
