extends Control

## The HUD over the town during a lobby and a game. It is laid out in two
## parts that an AspectFlowContainer (Shell) puts side by side on a wide
## screen and one above the other on a tall one:
## - the strip: the day or night, its stage and the time left (PhaseClock),
##   the lobby bar the town hands over (code, Copy, Leave), and the Last will
##   button, a paper and quill that opens the will editor in the chat panel.
##   On a tall screen the strip is a solid band across the top; on a wide one
##   it is a column down the left edge.
## - the focus area, the town and the chat (ChatPanel), which another
##   AspectFlowContainer (Focus) puts side by side on a wide screen and the
##   chat under the town on a tall one.
##
## The Roster, every player with what you can do to each of them (vote, your
## night ability, whisper), is the HUD's main panel. On a wide screen it fills
## the strip's column under the clock; on a tall one it moves into the focus
## area, between the town and the chat, where a thumb reaches it.
##
## The town itself is drawn behind the whole HUD; WorldSpace marks the part
## of the screen the HUD leaves for it, and the town centers its camera there
## (see town.gd). The town puts its touch joystick and the night's
## MinigameOverlay in it too.
##
## On a tall screen the chat brings either the town or itself into focus: a
## collapsed chat is a bar under the town, and an open one takes most of the
## focus area, leaving the town a strip. When a night minigame begins the
## chat collapses, so the minigame has the room; that happens on the clock,
## the same for every living player, so it gives nothing away. On a wide
## screen the chat is a column on the right, collapsed to a tab at its top.
##
## Every panel shares HudStyle's theme, set here so the scene file stays
## free of styles.

## The strip's width on a wide screen, where it is a column holding the
## roster.
const STRIP_WIDTH := 100.0
## The chat's width on a wide screen, where it is a column.
const CHAT_WIDTH := 88.0
## On a tall screen, the most the roster's player rows take before they
## scroll: with the chat collapsed, and open.
const ROSTER_ROWS_TALL := 76.0
const ROSTER_ROWS_TALL_CHAT := 36.0
## How much of the focus area an open chat takes on a tall screen, against 1
## for the town.
const CHAT_FOCUS_RATIO := 3.0
## The least height the town keeps under an open chat on a tall screen.
const WORLD_MIN_HEIGHT := 56.0

@onready var shell: AspectFlowContainer = %Shell
@onready var strip: PanelContainer = %Strip
@onready var strip_box: BoxContainer = %StripBox
@onready var chat_panel: PanelContainer = %ChatPanel
## Where the town shows through, for the town's camera and its overlays.
@onready var world_space: Control = %WorldSpace
## The strip's column beside the players, where the town puts its lobby bar.
@onready var side: VBoxContainer = %Side
@onready var roster: PanelContainer = %Roster
@onready var focus: AspectFlowContainer = %Focus

var _band := HudStyle.band_box()
## Whether a minigame was showing at the last check, to collapse the chat
## only when one begins.
var _in_minigame := false


func _ready() -> void:
	theme = HudStyle.build()
	%WillButton.pressed.connect(chat_panel.open_will)
	roster.whisper_requested.connect(chat_panel.start_whisper)
	shell.flow_changed.connect(func(_vertical: bool) -> void: _apply_layout())
	chat_panel.expanded_changed.connect(func(_expanded: bool) -> void: _apply_layout())
	Session.lobby_changed.connect(_update_will_button)
	Session.phase_changed.connect(_update_will_button)
	Session.minigame_changed.connect(_on_minigame_changed)
	_update_will_button()
	_apply_layout()


## Puts the lobby bar in the strip, under the clock.
func add_lobby_bar(bar: Control) -> void:
	bar.reparent(side, false)
	side.move_child(bar, 1)


func _apply_layout() -> void:
	var tall := shell.vertical
	strip_box.vertical = not tall
	strip.add_theme_stylebox_override("panel", _band if tall else StyleBoxEmpty.new())
	strip.custom_minimum_size.x = 0.0 if tall else STRIP_WIDTH
	_place_roster(tall)

	var open: bool = chat_panel.expanded
	if tall:
		chat_panel.custom_minimum_size.x = 0.0
		chat_panel.size_flags_vertical = SIZE_EXPAND_FILL if open else SIZE_FILL
		chat_panel.size_flags_stretch_ratio = CHAT_FOCUS_RATIO
		world_space.custom_minimum_size.y = WORLD_MIN_HEIGHT if open else 0.0
	else:
		chat_panel.custom_minimum_size.x = CHAT_WIDTH
		chat_panel.size_flags_vertical = SIZE_FILL if open else SIZE_SHRINK_BEGIN
		chat_panel.size_flags_stretch_ratio = 1.0
		world_space.custom_minimum_size.y = 0.0


## Puts the roster under the clock in the strip's column on a wide screen,
## or between the town and the chat on a tall one. On a tall screen it gives
## its room to a night minigame while one plays, and keeps less while the
## chat is open.
func _place_roster(tall: bool) -> void:
	var parent := focus if tall else strip_box
	if roster.get_parent() != parent:
		roster.reparent(parent, false)
	if tall:
		focus.move_child(roster, world_space.get_index() + 1)
		roster.max_rows_height = ROSTER_ROWS_TALL_CHAT if chat_panel.expanded else ROSTER_ROWS_TALL
		# As tall as its rows, so the town keeps the rest.
		roster.size_flags_vertical = SIZE_FILL
		roster.visible = not Session.in_minigame()
	else:
		strip_box.move_child(roster, side.get_index() + 1)
		roster.max_rows_height = 0.0
		roster.size_flags_vertical = SIZE_EXPAND_FILL
		roster.visible = true


func _on_minigame_changed() -> void:
	var in_minigame := Session.in_minigame()
	if in_minigame and not _in_minigame and shell.vertical:
		chat_panel.collapse()
	_in_minigame = in_minigame
	_place_roster(shell.vertical)


func _update_will_button() -> void:
	%WillButton.visible = Session.in_game() and Session.me != null and Session.me.alive
