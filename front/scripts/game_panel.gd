extends PanelContainer

## The game's side panel in the town: the phase and time left, the player's
## role, a log of everything that happens (chat, votes, night results,
## deaths), and a box to type in. Typing works like the terminal client:
## plain text is chat on whatever channel the player can use now, and
## commands like `/vote 3` or `/target 2` are actions. `/help` lists them.
##
## Press Enter to start typing and Enter again to send; Escape goes back to
## walking. The player doesn't move while the box has focus.
##
## Below the log are buttons for what the player can do right now (vote,
## judge, use their night ability), built from client.actions(). A button
## submits the same command typing would, so both go through one parser and
## the server's answer appears in the log either way. The current choice is
## shown pressed. The Will button opens an editor for the last will.

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

@onready var phase_label: Label = %PhaseLabel
@onready var role_label: Label = %RoleLabel
@onready var log_view: RichTextLabel = %Log
@onready var start_button: Button = %StartButton
@onready var input: LineEdit = %Input
@onready var actions_box: ScrollContainer = %Actions
@onready var action_list: VBoxContainer = %ActionList
@onready var choice_row: HFlowContainer = %ChoiceRow
@onready var will_button: Button = %WillButton
@onready var will_editor: Control = %WillEditor
@onready var will_text: TextEdit = %WillText
@onready var rows: Control = $Rows

## The actions the buttons were last built from, to skip rebuilding when
## nothing changed (actions_changed fires for every server message).
var _shown_actions: Array[Dictionary] = []


func _ready() -> void:
	for line in Session.log_lines:
		_add_line(line)
	Session.log_line.connect(_add_line)
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	Session.actions_changed.connect(_update_actions)
	_update()
	_update_actions()


func _process(_delta: float) -> void:
	# The label counts down, so it is refreshed every frame.
	phase_label.text = Session.client.phase_label()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
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
	var role := Session.client.role_name()
	role_label.text = "You are the %s. /role for details." % role if role != "" else ""
	role_label.visible = role != "" and Session.in_game()
	start_button.visible = Session.is_host and not Session.in_game()
	start_button.disabled = Session.players.size() < 4
	start_button.text = "Start game" if Session.players.size() >= 4 \
			else "Start game (needs 4 players)"
	will_button.visible = Session.in_game()
	if not Session.in_game() and will_editor.visible:
		_close_will()


## Rebuilds the action buttons: a row per player with buttons aimed at them,
## then the buttons that stand alone (Guilty, Alert, Cancel ...).
func _update_actions() -> void:
	var actions: Array[Dictionary] = []
	actions.assign(Session.client.actions())
	if actions == _shown_actions:
		return
	_shown_actions = actions
	for child in action_list.get_children() + choice_row.get_children():
		child.queue_free()
	var rows_by_lot := {}
	for action in actions:
		var button := _action_button(action)
		var lot: int = action["lot"]
		if lot < 0:
			choice_row.add_child(button)
			continue
		if not rows_by_lot.has(lot):
			rows_by_lot[lot] = _player_row(lot)
			action_list.add_child(rows_by_lot[lot])
		rows_by_lot[lot].add_child(button)
	actions_box.visible = not rows_by_lot.is_empty()
	choice_row.visible = actions.any(func(a: Dictionary) -> bool: return a["lot"] < 0)


func _player_row(lot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	var resident := Session.player_on_lot(lot)
	label.text = "%d %s" % [lot + 1, resident.display_name if resident else "?"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 6)
	row.add_child(label)
	return row


func _action_button(action: Dictionary) -> Button:
	var button := Button.new()
	button.text = action["label"]
	# Shown pressed when it is the current choice. Pressing rebuilds the
	# buttons once the server confirms, so the toggle is never left stale.
	button.toggle_mode = true
	button.button_pressed = action["selected"]
	# Buttons never take keyboard focus, so arrow keys keep walking.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 6)
	var command: String = action["command"]
	button.pressed.connect(_on_action_pressed.bind(command))
	return button


func _on_action_pressed(command: String) -> void:
	var error := Session.submit(command)
	if error != "":
		_add_line("! " + error)
	# Undo the local toggle; the server's answer decides what is selected.
	_shown_actions = []
	_update_actions.call_deferred()


func _on_will_button_pressed() -> void:
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


## Adds one line to the log. Lines are added as plain text, never BBCode,
## because they include what other players typed.
func _add_line(text: String) -> void:
	var color := Color.WHITE
	var bare := text.strip_edges()
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


func _on_input_text_submitted(_text: String) -> void:
	_send()
	input.release_focus()


func _on_send_button_pressed() -> void:
	_send()


func _on_start_button_pressed() -> void:
	Session.client.start_game()
