extends PanelContainer

## The chat: a log of everything that happens, and a box to type in. The
## game is played around one table, out loud, so for people the log is mostly
## a record (your role, night results, deaths, votes), and the box is how
## terminal bots talk. It is always open; on a tall screen the HUD slides it
## over the town as a sheet, and the player can hide it to see the town.
##
## Lines are colored by kind (see Session.log_line): what players said in
## white, led by the speaker's number in a colored circle, whispers in blue, game updates (your role, its results, deaths, votes) in yellow, and
## system lines (the lobby, the connection, errors, help) in purple.
##
## The box doesn't say which channel plain text goes to (town, jail, mafia,
## dead): someone looking over your shoulder would learn your role from it.
## Typing works like the terminal client: plain text is chat, and commands like `/vote 3` are
## actions; `/help` lists them. Press Enter to start typing and Enter again
## to send; Escape goes back to walking. On a touch screen, tapping the box
## opens the HUD's TextPrompt instead, clear of the keyboard.

## A line was added to the log.
signal line_added

## Whispers, in the log.
const WHISPER_COLOR := Color(0.45, 0.72, 1)
## Line colors, by kind.
const KIND_COLORS := {
	Session.LINE_CHAT: Color(0.96, 0.95, 0.92),
	Session.LINE_WHISPER: WHISPER_COLOR,
	Session.LINE_GAME: Color(1, 0.84, 0.4),
	Session.LINE_SYSTEM: Color(0.78, 0.62, 1),
}

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
	for line in Session.log_lines:
		_add_line(line["text"], line["kind"], line["lot"])
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


## Adds one line to the log, a player's chat line led by their number in its
## colored circle (NumberBadge). Lines are added as plain text, never BBCode,
## because they include what other players typed.
func _add_line(text: String, kind: String, lot := -1) -> void:
	if lot >= 0:
		log_view.add_image(NumberBadge.texture(lot + 1), 0, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		log_view.add_text(" ")
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
