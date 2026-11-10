extends Control

## The HUD over the town during a lobby and a game. It is laid out in two
## parts that an AspectFlowContainer (Shell) puts side by side on a wide
## screen and one above the other on a tall one:
## - the strip, everything about the game at a glance: the players with their
##   numbers (PlayerList), and beside them the day or night, its stage and the
##   time left (PhaseClock), the lobby bar the town hands over (code, Copy,
##   Leave), and the Last will button, a paper and quill that opens the will
##   editor in the chat panel. On a tall screen the strip is a solid band
##   across the top; on a wide one its panels stack down the left edge.
## - the focus area, the town and the chat (ChatPanel), which another
##   AspectFlowContainer (Focus) puts side by side on a wide screen and the
##   chat under the town on a tall one.
##
## The town itself is drawn behind the whole HUD; WorldSpace marks the part
## of the screen the HUD leaves for it, and the town centers its camera there
## (see town.gd). What the player can do now (ActionBar) sits at the bottom of
## WorldSpace, and the town puts its touch joystick and the night's
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

## The strip's width on a wide screen, where it is a column.
const STRIP_WIDTH := 64.0
## The chat's width on a wide screen, where it is a column.
const CHAT_WIDTH := 96.0
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

var _band := HudStyle.band_box()
## Whether a minigame was showing at the last check, to collapse the chat
## only when one begins.
var _in_minigame := false


func _ready() -> void:
	theme = HudStyle.build()
	%WillButton.pressed.connect(chat_panel.open_will)
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


func _on_minigame_changed() -> void:
	var in_minigame := Session.in_minigame()
	if in_minigame and not _in_minigame and shell.vertical:
		chat_panel.collapse()
	_in_minigame = in_minigame


func _update_will_button() -> void:
	%WillButton.visible = Session.in_game() and Session.me != null and Session.me.alive
