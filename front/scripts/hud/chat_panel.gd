extends PanelContainer

## The chat on the right of the town: a log of everything that happens
## (chat, votes, night results, deaths) and a box to type in, with the
## channel plain text goes to right now shown beside it (town, jail, mafia,
## dead, or whisper while a `/w` line is typed). Typing works like the
## terminal client: plain text is chat, and commands like `/vote 3` or
## `/target 2` are actions. `/help` lists them.
##
## Press Enter to start typing and Enter again to send; Escape goes back to
## walking. The player doesn't move while the box has focus.
##
## The HUD's Last will button (bottom left) opens an editor for the will in
## place of the log (open_will), opening the panel for it if it was collapsed.
##
## The game is played in one room, so the town talks out loud and the chat
## is mostly for whispers and night chat. It opens and closes on the clock,
## the same for everyone, so nobody's screen gives away that they have a
## night chat: open at night, through the morning's discussion (where night
## results land) and at game over; collapsed to a small tab from voting until
## nightfall, and in the lobby. While collapsed, the tab counts unread
## whispers and private notices, and the player can open it themselves (or
## press Enter to type).

## Line colors, by how a line starts.
const COLORS := {
	"! ": Color(1, 0.45, 0.4),
	"* ": Color(1, 0.86, 0.5),
	"[mafia]": Color(0.95, 0.4, 0.4),
	"[jail]": Color(0.75, 0.75, 0.85),
	"[dead]": Color(0.6, 0.65, 0.75),
	"[whisper": Color(0.8, 0.6, 1),
	"===": Color(0.55, 0.85, 1),
}
## How each channel from client.chat_channel() is named and colored beside
## the input, matching its lines in the log. "" is when nobody can hear.
const CHANNELS := {
	"lobby": ["lobby", Color(0.93, 0.87, 0.74)],
	"town": ["town", Color(0.93, 0.87, 0.74)],
	"jail": ["jail", Color(0.75, 0.75, 0.85)],
	"mafia": ["mafia", Color(0.95, 0.4, 0.4)],
	"dead": ["dead", Color(0.6, 0.65, 0.75)],
	"whisper": ["whisper", Color(0.8, 0.6, 1)],
	"": ["muted", Color(0.62, 0.56, 0.46)],
}

@onready var log_view: RichTextLabel = %Log
@onready var input: LineEdit = %Input
@onready var channel_label: Label = %Channel
@onready var will_editor: Control = %WillEditor
@onready var will_text: TextEdit = %WillText
@onready var rows: Control = $Rows
@onready var log_and_input: Array[Control] = [%Log, $Rows/InputRow]

## Whether the log and input show, or only the header as a tab.
var expanded := true
## Whispers and private notices that arrived while collapsed.
var _unread := 0
## Whether the clock last said the chat should be open, so it only opens or
## closes itself when that changes and otherwise keeps the player's choice.
var _was_open_time := false
var _toggle := Button.new()
## Whether the panel was open before the will editor opened it, to put it
## back when the editor closes.
var _expanded_before_will := true
## The panel's bottom edge when expanded, from the scene.
var _full_anchor_bottom := 0.0
var _full_offset_bottom := 0.0


func _ready() -> void:
	_full_anchor_bottom = anchor_bottom
	_full_offset_bottom = offset_bottom
	_toggle.focus_mode = FOCUS_NONE
	_toggle.pressed.connect(func() -> void: _set_expanded(not expanded))
	$Rows/Header.add_child(_toggle)
	_was_open_time = chat_time()
	_set_expanded(_was_open_time)
	for line in Session.log_lines:
		_add_line(line)
	Session.log_line.connect(_add_line)
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	# Dying or being jailed changes the channel without a new phase.
	Session.actions_changed.connect(_update_channel)
	input.text_changed.connect(func(_text: String) -> void: _update_channel())
	_update()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_set_expanded(true)
		input.grab_focus()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if will_editor.visible:
		_close_will()
		get_viewport().set_input_as_handled()
	elif input.has_focus():
		input.release_focus()
		get_viewport().set_input_as_handled()


func _update() -> void:
	if not Session.in_game() and will_editor.visible:
		_close_will()
	var open_time := chat_time()
	# Never collapse under a will being written; closing the editor does.
	if open_time != _was_open_time and not will_editor.visible:
		_set_expanded(open_time)
	_was_open_time = open_time
	# At chat time the panel stays open for everyone, so it can't be hidden.
	_toggle.visible = not open_time
	_update_channel()


## Whether the clock says the chat is open now: at night, in the morning's
## discussion, and once the game is over.
static func chat_time() -> bool:
	var info: Dictionary = Session.client.phase_info()
	return info["night"] or info["stage"] == "Discussion" or info["title"] == "Game over"


func _set_expanded(open: bool) -> void:
	expanded = open
	for part in log_and_input:
		part.visible = open
	if open:
		_unread = 0
		anchor_bottom = _full_anchor_bottom
		offset_bottom = _full_offset_bottom
		grow_vertical = GROW_DIRECTION_BOTH
	else:
		input.release_focus()
		# Shrink to the header, hanging from the top edge.
		grow_vertical = GROW_DIRECTION_END
		anchor_bottom = anchor_top
		offset_bottom = offset_top
	_update_toggle()


func _update_toggle() -> void:
	if expanded:
		_toggle.text = "Hide"
	elif _unread > 0:
		_toggle.text = "Open (%d)" % _unread
	else:
		_toggle.text = "Open"


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


func open_will() -> void:
	if will_editor.visible:
		return
	_expanded_before_will = expanded
	_set_expanded(true)
	will_text.text = Session.client.last_will()
	rows.visible = false
	will_editor.visible = true
	will_text.grab_focus()


func _on_save_will_button_pressed() -> void:
	Session.client.set_last_will(will_text.text.strip_edges())
	_close_will()


func _close_will() -> void:
	will_text.release_focus()
	will_editor.visible = false
	rows.visible = true
	if not _expanded_before_will and not chat_time():
		_set_expanded(false)


## Adds one line to the log. Lines are added as plain text, never BBCode,
## because they include what other players typed.
func _add_line(text: String) -> void:
	var color := RpgTheme.TEXT
	var bare := text.strip_edges()
	if not expanded and (bare.begins_with("[whisper") or bare.begins_with("* ")):
		_unread += 1
		_update_toggle()
	for prefix in COLORS:
		if bare.begins_with(prefix):
			color = COLORS[prefix]
			break
	log_view.push_color(color)
	log_view.add_text(text)
	log_view.pop()
	log_view.newline()


func _send() -> void:
	var text := input.text.strip_edges()
	if text == "":
		input.release_focus()
		return
	var error := Session.submit(text)
	if error != "":
		_add_line("! " + error)
		return
	input.clear()
	_update_channel()


func _on_input_text_submitted(_text: String) -> void:
	_send()
	input.release_focus()


func _on_send_button_pressed() -> void:
	_send()
