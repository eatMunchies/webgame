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
## Beside the box is the channel plain text goes to right now (town, jail,
## mafia, dead, or whisper while a `/w` line is typed). Typing works like the
## terminal client: plain text is chat, and commands like `/vote 3` are
## actions; `/help` lists them. Press Enter to start typing and Enter again
## to send; Escape goes back to walking. On a touch screen, tapping the box
## opens the HUD's TextPrompt instead, clear of the keyboard.

## A line was added to the log.
signal line_added

## Whispers, in the log and beside the box while typing one.
const WHISPER_COLOR := Color(0.45, 0.72, 1)
## Line colors, by kind.
const KIND_COLORS := {
	Session.LINE_CHAT: Color(0.96, 0.95, 0.92),
	Session.LINE_WHISPER: WHISPER_COLOR,
	Session.LINE_GAME: Color(1, 0.84, 0.4),
	Session.LINE_SYSTEM: Color(0.78, 0.62, 1),
}
## How each channel from client.chat_channel() is named and colored beside
## the input. "" is when nobody can hear.
const CHANNELS := {
	"lobby": ["lobby", Color(0.93, 0.87, 0.74)],
	"town": ["town", Color(0.93, 0.87, 0.74)],
	"jail": ["jail", Color(0.75, 0.75, 0.85)],
	"mafia": ["mafia", Color(0.95, 0.4, 0.4)],
	"dead": ["dead", Color(0.6, 0.65, 0.75)],
	"whisper": ["whisper", WHISPER_COLOR],
	"": ["muted", Color(0.62, 0.56, 0.46)],
}

@onready var log_view: RichTextLabel = %Log
@onready var input: LineEdit = %Input
@onready var channel_label: Label = %Channel

## The HUD's prompt, which the box opens on a touch screen. Set by the HUD.
var prompt: TextPrompt:
	set(value):
		prompt = value
		prompt.attach(input, "Chat", true)


func _ready() -> void:
	for line in Session.log_lines:
		_add_line(line["text"], line["kind"], line["lot"])
	Session.log_line.connect(_add_line)
	Session.lobby_changed.connect(_update_channel)
	Session.phase_changed.connect(_update_channel)
	# Dying or being jailed changes the channel without a new phase.
	Session.actions_changed.connect(_update_channel)
	input.text_changed.connect(func(_text: String) -> void: _update_channel())
	_update_channel()


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


## Shows where the line being typed will go. A `/w N` line is a whisper; any
## other command isn't chat, so the plain text channel stays shown.
func _update_channel() -> void:
	var channel: String = Session.client.chat_channel()
	var typed := input.text.strip_edges()
	if typed.begins_with("/w ") or typed.begins_with("/whisper "):
		channel = "whisper"
	var shown: Array = CHANNELS.get(channel, CHANNELS[""])
	channel_label.text = shown[0]
	channel_label.add_theme_color_override("font_color", shown[1])


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
	_update_channel()


func _on_input_text_submitted(_text: String) -> void:
	_send()
	input.release_focus()


func _on_send_button_pressed() -> void:
	_send()
