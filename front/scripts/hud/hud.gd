extends Control

## The HUD over the town during a lobby and a game. The game is played around
## one table, out loud, with each phone as an assistant, so the HUD is about
## who is who and what you can do to them; the chat is a log of what happens
## (and how terminal bots talk).
##
## Three parts, which an AspectFlowContainer (Shell) puts side by side on a
## wide screen and one above the other on a tall one:
## - Info: the day or night, its stage and the time left (PhaseClock), and
##   the lobby bar the town hands over (code, Copy, Leave). On a wide screen
##   the chat (ChatPanel) fills the rest of this column.
## - Middle: where the town shows through (WorldSpace). The town centers its
##   camera there (see town.gd) and puts its touch joystick and the night's
##   MinigameOverlay in it.
## - Side: the Roster, every player with what you can do to each of them, and
##   the Last will button under it.
##
## So a wide screen reads [clock, lobby, chat | town | roster, will], and a
## tall one, top to bottom: clock and lobby, the town, the roster (at most a
## third of the screen; its rows scroll) and the will button. On a tall
## screen the chat is a sheet over the town, open by default. A handle above
## the roster hides it to show the town, so the player can walk around, and
## shows it again; it can be tapped, or dragged up and down. While hidden,
## the handle counts new lines. When a night minigame begins the sheet hides
## and the roster steps aside, so the minigame has the room; both come back
## when it ends.
##
## Typing goes through one TextPrompt, a box in the upper middle of the
## screen, clear of a phone's keyboard: whispering from the roster, writing
## the last will (with Paste), and on a touch screen the chat's own box.
##
## Every panel shares HudStyle's theme, set here so the scene file stays
## free of styles.

## The Info and Side columns' widths on a wide screen.
const INFO_WIDTH := 88.0
const SIDE_WIDTH := 96.0
## On a tall screen, the share of the HUD's height the roster may take.
const ROSTER_SHARE := 1.0 / 3.0
## How long the tall screen's chat sheet takes to slide.
const SHEET_SECONDS := 0.2
## How far the handle must be dragged, in units, to count as a drag.
const DRAG_THRESHOLD := 6.0
const WILL_TITLE := "Last will"
const WILL_PLACEHOLDER := "Everyone reads this when you die. N1: checked 3, not suspicious"

@onready var shell: AspectFlowContainer = %Shell
@onready var info: PanelContainer = %Info
@onready var info_box: VBoxContainer = %InfoBox
@onready var middle: Control = %Middle
@onready var side: VBoxContainer = %Side
@onready var chat_panel: PanelContainer = %ChatPanel
@onready var chat_handle: Button = %ChatHandle
@onready var roster: PanelContainer = %Roster
@onready var will_button: Button = %WillButton
## Where the town shows through, for the town's camera and its overlays.
@onready var world_space: Control = %WorldSpace

var prompt: TextPrompt
var _band := HudStyle.band_box()
## On a tall screen, how much of the town the chat sheet covers, 0 to 1.
var _sheet := 1.0
## Whether the player wants the sheet open; a minigame hides it meanwhile.
var _sheet_wanted := true
var _sheet_tween: Tween
## Lines the chat got while its sheet was hidden.
var _unread := 0
## Where a drag on the handle started, and the sheet's share then.
var _drag_from := Vector2.ZERO
var _drag_sheet := 0.0
var _dragging := false
var _pressing := false
## Whether a minigame was showing at the last check.
var _in_minigame := false


func _ready() -> void:
	theme = HudStyle.build()
	prompt = TextPrompt.create(self)
	chat_panel.prompt = prompt
	will_button.pressed.connect(_open_will)
	roster.whisper_requested.connect(_whisper)
	chat_panel.line_added.connect(_on_chat_line_added)
	chat_handle.gui_input.connect(_on_handle_input)
	shell.flow_changed.connect(func(_vertical: bool) -> void: _apply_layout())
	middle.resized.connect(_place_sheet)
	resized.connect(_apply_layout)
	Session.lobby_changed.connect(_update_will_button)
	Session.phase_changed.connect(_update_will_button)
	Session.minigame_changed.connect(_on_minigame_changed)
	_update_will_button()
	_apply_layout()


## Puts the lobby bar in the Info column, under the clock.
func add_lobby_bar(bar: Control) -> void:
	bar.reparent(info_box, false)
	info_box.move_child(bar, 1)


func _apply_layout() -> void:
	var tall := shell.vertical
	info.add_theme_stylebox_override("panel", _band if tall else StyleBoxEmpty.new())
	info.custom_minimum_size.x = 0.0 if tall else INFO_WIDTH
	side.custom_minimum_size.x = 0.0 if tall else SIDE_WIDTH
	# The roster fills its column on a wide screen; on a tall one it is as
	# tall as its rows, up to a share of the screen.
	roster.size_flags_vertical = SIZE_FILL if tall else SIZE_EXPAND_FILL
	var roster_rows := 0.0
	if tall:
		# Less the prompt, heading, buttons and role around the rows.
		roster_rows = maxf(size.y * ROSTER_SHARE - 40.0, 24.0)
	roster.max_rows_height = roster_rows
	chat_handle.visible = tall

	if tall:
		if chat_panel.get_parent() != middle:
			chat_panel.reparent(middle, false)
		chat_panel.size_flags_vertical = SIZE_FILL
		_place_sheet()
	else:
		if chat_panel.get_parent() != info_box:
			chat_panel.reparent(info_box, false)
		info_box.move_child(chat_panel, -1)
		chat_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		chat_panel.size_flags_vertical = SIZE_EXPAND_FILL
		chat_panel.visible = true
	_update_side()


## The roster gives a tall screen's room to a night minigame.
func _update_side() -> void:
	roster.visible = not (shell.vertical and Session.in_minigame())
	_update_will_button()


## Sizes the tall screen's chat sheet: anchored to the bottom of the town's
## part, covering `_sheet` of it.
func _place_sheet() -> void:
	if not shell.vertical:
		return
	var height := roundf(middle.size.y * _sheet)
	chat_panel.visible = height >= 1.0
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_right = 1.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 0.0
	chat_panel.offset_right = 0.0
	chat_panel.offset_top = -height
	chat_panel.offset_bottom = 0.0
	_update_handle()


func _update_handle() -> void:
	var open := _sheet > 0.5
	if open:
		chat_handle.text = "Hide chat"
	elif _unread > 0:
		chat_handle.text = "Show chat (%d new)" % _unread
	else:
		chat_handle.text = "Show chat"


func _slide_sheet(to: float) -> void:
	if _sheet_tween != null:
		_sheet_tween.kill()
	if to > 0.5:
		_unread = 0
	_sheet_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sheet_tween.tween_method(func(value: float) -> void:
		_sheet = value
		_place_sheet(), _sheet, to, SHEET_SECONDS)


## A tap on the handle shows or hides the chat; a drag pulls the sheet up or
## down with the finger, and it settles open or shut by which way it went.
func _on_handle_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			_pressing = true
			_dragging = false
			_drag_from = press.global_position
			_drag_sheet = _sheet
		elif _pressing:
			_pressing = false
			var moved := press.global_position.y - _drag_from.y
			if _dragging:
				_sheet_wanted = moved < 0.0
			else:
				_sheet_wanted = _sheet <= 0.5
			_slide_sheet(1.0 if _sheet_wanted else 0.0)
		chat_handle.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressing:
		var moved := motion.global_position.y - _drag_from.y
		if absf(moved) >= DRAG_THRESHOLD:
			_dragging = true
		if _dragging and middle.size.y > 0.0:
			_sheet = clampf(_drag_sheet - moved / middle.size.y, 0.0, 1.0)
			_place_sheet()
		chat_handle.accept_event()


func _on_chat_line_added() -> void:
	if shell.vertical and _sheet <= 0.5:
		_unread += 1
		_update_handle()


func _on_minigame_changed() -> void:
	var in_minigame := Session.in_minigame()
	if shell.vertical and in_minigame != _in_minigame:
		# A minigame takes the sheet's place; the player's choice comes back
		# after it.
		_slide_sheet(0.0 if in_minigame else (1.0 if _sheet_wanted else 0.0))
	_in_minigame = in_minigame
	_update_side()


func _update_will_button() -> void:
	will_button.visible = Session.in_game() and Session.me != null and Session.me.alive \
			and roster.visible


func _open_will() -> void:
	prompt.ask(WILL_TITLE, Session.client.last_will(), func(text: String) -> void:
		Session.client.set_last_will(text.strip_edges())
		Session.add_log_line("Your last will is saved.", Session.LINE_GAME),
		{"multiline": true, "confirm": "Save", "placeholder": WILL_PLACEHOLDER})


## Opens the prompt to whisper to player `number`, and sends what's typed.
func _whisper(number: int, player_name: String) -> void:
	prompt.ask("Whisper to %d %s" % [number, player_name], "", func(text: String) -> void:
		var message := text.strip_edges()
		if message == "":
			return
		var error := Session.submit("/w %d %s" % [number, message])
		if error != "":
			Session.add_log_line("! " + error))
