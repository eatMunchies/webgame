extends Control

## The HUD over the town during a lobby and a game. The game is played around
## one table, out loud, with each phone as an assistant, so the HUD is about
## who is who and what you can do to them; the chat is a log of what happens
## (and how terminal bots talk).
##
## Three parts, which an AspectFlowContainer (Shell) puts side by side on a
## wide screen and one above the other on a tall one:
## - Info: the day or night, its stage and the time left, and the town's
##   code with Copy and Leave, on one sheet (PhaseClock). On a wide screen
##   the chat (ChatPanel) fills the rest of this column.
## - Middle: where the town shows through (WorldSpace). The town centers its
##   camera there (see town.gd) and puts its touch joystick and the night's
##   MinigameOverlay in it.
## - Side: the Roster, every player with what you can do to each of them, and
##   the Last will button under it.
##
## So a wide screen reads [clock, lobby, chat | town | roster, buttons], and
## a tall one, top to bottom: clock and lobby, the town, the roster (at most
## a third of the screen; its rows scroll) and the buttons. The buttons are
## the Last will (a paper and quill) and the role card (an ID card; see
## RoleCard, which also opens on its own when a game starts).
##
## On a tall screen the chat is a sheet over the town, open by default, with
## a tab on its top edge: a small rounded grip with three bars. Drag the tab
## down to uncover the town and walk around, and up to bring the chat back; a
## tap does either. While the chat is down, a dot on the tab says new lines
## came in. During a night minigame the game takes the bottom half of the
## town's part (MinigameSpace) and the roster steps aside; the chat sheet sits
## above the game, so what happened the night before stays a pull away.
##
## Typing goes through one TextPrompt, a box in the upper middle of the
## screen, clear of a phone's keyboard: whispering from the roster, writing
## the last will (with Paste), and on a touch screen the chat's own box.
##
## Every panel shares HudStyle's theme, set here so the scene file stays
## free of styles.

## The gap between the parts on a wide screen.
const SECTION_GAP := 2
## The Info and Side columns' widths on a wide screen.
const INFO_WIDTH := 88.0
const SIDE_WIDTH := 96.0
## On a tall screen, the share of the HUD's height the roster may take.
const ROSTER_SHARE := 0.45
## How long the tall screen's chat sheet takes to slide.
const SHEET_SECONDS := 0.2
## How far the handle must be dragged, in units, to count as a drag.
const DRAG_THRESHOLD := 6.0
## The tall screen's chat tab, in units, and the radius of its top corners.
const TAB_SIZE := Vector2(30, 13)
const TAB_RADIUS := 6
## On a tall screen, the share of the town's part a night minigame takes,
## at the bottom, under the chat.
const MINIGAME_SHARE := 0.5
## What the machine says while the connection is down (see docs/LORE.md).
const RECONNECTING_LINES: PackedStringArray = ["desync detected, resyncing", "hold on, getting you back in"]
const WILL_TITLE := "Last will"
const WILL_PLACEHOLDER := "Everyone reads this when you die. N1: checked 3, not suspicious"

@onready var shell: AspectFlowContainer = %Shell
@onready var info: PanelContainer = %Info
@onready var info_box: VBoxContainer = %InfoBox
@onready var middle: Control = %Middle
@onready var side: VBoxContainer = %Side
@onready var chat_panel: PanelContainer = %ChatPanel
@onready var roster: PanelContainer = %Roster
@onready var will_button: Button = %WillButton
## Where the town shows through, for the town's camera and its overlays.
@onready var world_space: Control = %WorldSpace
## Where the town puts the night's MinigameOverlay: all of WorldSpace, or on a
## tall screen its bottom half.
@onready var minigame_space: Control = %MinigameSpace

var prompt: TextPrompt
## The machine's notice at the top of the town: resyncing after a drop.
var notice := Notice.new()
var role_card: RoleCard
## The tall screen's tab on the chat sheet's top edge.
var chat_tab := Button.new()
var role_button := Button.new()
## Whether a game was running at the last check, to show the role card when
## one starts.
var _was_in_game := false
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
## Whether a minigame was showing at the last check, and whether it had the
## on-screen keyboard up.
var _in_minigame := false
var _keyboard_was := false


func _ready() -> void:
	theme = HudStyle.build()
	prompt = TextPrompt.create(self)
	role_card = RoleCard.create(self)
	chat_panel.prompt = prompt
	_add_buttons()
	_add_chat_tab()
	_add_notice()
	will_button.pressed.connect(_open_will)
	roster.whisper_requested.connect(_whisper)
	chat_panel.line_added.connect(_on_chat_line_added)
	shell.flow_changed.connect(func(_vertical: bool) -> void: _apply_layout())
	middle.resized.connect(_place_sheet)
	resized.connect(_apply_layout)
	Session.lobby_changed.connect(_update_will_button)
	Session.phase_changed.connect(_update_will_button)
	Session.lobby_changed.connect(_show_role_at_start)
	Session.phase_changed.connect(_show_role_at_start)
	Session.minigame_changed.connect(_on_minigame_changed)
	Session.keyboard_minigame_changed.connect(_on_minigame_changed)
	_update_will_button()
	_apply_layout()


## The notice hangs from the top middle of the town's part, over the town
## (and on a tall screen under the faded clock).
func _add_notice() -> void:
	world_space.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE,
			Tokens.SPACE_MD)
	notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	Session.reconnecting_changed.connect(_update_notice)
	_update_notice()


func _update_notice() -> void:
	if Session.reconnecting:
		notice.say(RECONNECTING_LINES)
	else:
		notice.clear()


func _apply_layout() -> void:
	var tall := shell.vertical
	# Stacked, the parts sit flush, so the chat tab rests right on what's
	# under it.
	shell.add_theme_constant_override("separation", 0 if tall else SECTION_GAP)
	info.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
	chat_tab.visible = tall

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


## The roster gives a tall screen's room to a night minigame, which takes
## the bottom of the town's part there, under the chat.
func _update_side() -> void:
	var tall_minigame := shell.vertical and Session.in_minigame()
	roster.visible = not tall_minigame
	# A minigame that has the on-screen keyboard up (the typing test) goes to
	# the top instead, above the keyboard, with the chat put away.
	var keyboard := tall_minigame and Session.keyboard_minigame
	minigame_space.anchor_top = 0.0 if keyboard or not tall_minigame else 1.0 - MINIGAME_SHARE
	minigame_space.anchor_bottom = MINIGAME_SHARE if keyboard else 1.0
	minigame_space.offset_top = 0.0
	minigame_space.offset_bottom = 0.0
	chat_tab.visible = shell.vertical and not keyboard
	_update_will_button()
	_place_sheet()


## How much of the bottom of the town's part the chat sheet stays above: the
## minigame's share during a tall screen's night minigame, or none.
func _sheet_floor() -> float:
	if shell.vertical and Session.in_minigame():
		return roundf(middle.size.y * MINIGAME_SHARE)
	return 0.0


## Sizes the tall screen's chat sheet: resting on the bottom of the town's
## part (or on a night minigame's top), covering `_sheet` of the room above
## (all but the tab's height, open), with the tab on its top edge.
func _place_sheet() -> void:
	if not shell.vertical:
		return
	var floor_height := _sheet_floor()
	var room := middle.size.y - floor_height - TAB_SIZE.y
	var height := roundf(room * _sheet)
	chat_panel.visible = height >= 1.0
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_right = 1.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 0.0
	chat_panel.offset_right = 0.0
	chat_panel.offset_top = -floor_height - height
	chat_panel.offset_bottom = -floor_height
	chat_tab.size = TAB_SIZE
	chat_tab.position = Vector2(roundf((middle.size.x - TAB_SIZE.x) / 2.0),
			middle.size.y - floor_height - height - TAB_SIZE.y)
	_update_handle()


func _update_handle() -> void:
	chat_tab.queue_redraw()


func _slide_sheet(to: float) -> void:
	if _sheet_tween != null:
		_sheet_tween.kill()
	if to > 0.5:
		_unread = 0
	_sheet_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sheet_tween.tween_method(func(value: float) -> void:
		_sheet = value
		_place_sheet(), _sheet, to, SHEET_SECONDS)


## The chat tab: a small tab, well rounded on top, with three stacked bars
## to grab, riding on the sheet's top edge. A gold dot on its corner says
## new lines came in while the chat was down.
func _add_chat_tab() -> void:
	chat_tab.focus_mode = Control.FOCUS_NONE
	chat_tab.tooltip_text = "Chat"
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := HudStyle.panel_box()
		box.corner_radius_top_left = TAB_RADIUS
		box.corner_radius_top_right = TAB_RADIUS
		box.corner_radius_bottom_left = 0
		box.corner_radius_bottom_right = 0
		box.border_width_bottom = 0
		if state.begins_with("hover"):
			box.border_color = RpgTheme.GOLD_BRIGHT
		chat_tab.add_theme_stylebox_override(state, box)
	chat_tab.draw.connect(func() -> void:
		var x := roundf(chat_tab.size.x / 2.0)
		for y in [4.5, 7.5, 10.5]:
			chat_tab.draw_line(Vector2(x - 6, y), Vector2(x + 6, y), RpgTheme.TEXT, 1.0)
		if _unread > 0 and _sheet <= 0.5:
			chat_tab.draw_circle(Vector2(chat_tab.size.x - 5, 4), 2.0, RpgTheme.GOLD_BRIGHT))
	chat_tab.gui_input.connect(_on_handle_input)
	middle.add_child(chat_tab)


## The Last will and role card buttons, side by side under the roster.
func _add_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	side.add_child(row)
	will_button.reparent(row, false)
	role_button.icon = preload("res://assets/sprites/ui/role.png")
	role_button.tooltip_text = "Your role"
	role_button.focus_mode = Control.FOCUS_NONE
	role_button.pressed.connect(role_card.open)
	row.add_child(role_button)


## Shows the role card when a game starts (or when joining one in progress).
func _show_role_at_start() -> void:
	# A reconnect drops the game and brings it back; that's no new game.
	if Session.reconnecting:
		return
	var in_game := Session.in_game()
	if in_game and not _was_in_game and not Session.client.role_info().is_empty():
		role_card.open()
	_was_in_game = in_game


## A tap on the tab shows or hides the chat; a drag pulls the sheet up or
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
		chat_tab.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressing:
		var moved := motion.global_position.y - _drag_from.y
		if absf(moved) >= DRAG_THRESHOLD:
			_dragging = true
		var room := middle.size.y - _sheet_floor() - TAB_SIZE.y
		if _dragging and room > 0.0:
			_sheet = clampf(_drag_sheet - moved / room, 0.0, 1.0)
			_place_sheet()
		chat_tab.accept_event()


func _on_chat_line_added() -> void:
	if shell.vertical and _sheet <= 0.5:
		_unread += 1
		_update_handle()


func _on_minigame_changed() -> void:
	var in_minigame := Session.in_minigame()
	var keyboard := shell.vertical and in_minigame and Session.keyboard_minigame
	if shell.vertical:
		if keyboard:
			# The keyboard covers the bottom, so the chat is put away.
			_slide_sheet(0.0)
		elif in_minigame and (not _in_minigame or _keyboard_was):
			# The chat opens above the game, so the night before is in view.
			_slide_sheet(1.0)
		elif not in_minigame and _in_minigame:
			# The player's own choice comes back after the minigame.
			_slide_sheet(1.0 if _sheet_wanted else 0.0)
	_in_minigame = in_minigame
	_keyboard_was = keyboard
	_update_side()


func _update_will_button() -> void:
	will_button.visible = Session.in_game() and Session.me != null and Session.me.alive \
			and roster.visible
	role_button.visible = Session.in_game() and roster.visible


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
