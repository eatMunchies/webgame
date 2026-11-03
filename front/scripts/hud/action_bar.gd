extends PanelContainer

## What the player can do right now, in the middle of the screen below the
## town: Vote while voting, Guilty / Innocent / Abstain in a trial, Jail for
## the Jailer, and at night their role's ability. Before a game the host's
## Start button is here too. It hides when there is nothing to do, and while
## a night minigame has the middle of the screen.
##
## The buttons come from client.actions(). Actions aimed at a player are
## grouped under their label ("Vote", "Heal") as a grid of player buttons,
## and the ones that stand alone (Guilty, Alert, Cancel) form a row under
## them. A button submits the same command typing would, so both go through
## one parser and the server's answer appears in the chat log either way.
## The current choice is shown pressed.

## Player buttons per row. Three fit a 15 player lobby in five rows.
const COLUMNS := 3
## The grids scroll past this height, so the town above stays visible.
const MAX_GRID_HEIGHT := 92.0
## Standalone buttons whose meaning a color helps with.
const BUTTON_COLORS := {
	"Guilty": HudStyle.DANGER_COLOR,
	"Innocent": HudStyle.SAFE_COLOR,
	"Execute": HudStyle.DANGER_COLOR,
}

@onready var scroll: ScrollContainer = %Scroll
@onready var groups: VBoxContainer = %Groups
@onready var choice_row: HFlowContainer = %ChoiceRow
@onready var start_button: Button = %StartButton

## The actions the buttons were last built from, to skip rebuilding when
## nothing changed (actions_changed fires for every server message).
var _shown_actions: Array[Dictionary] = []


func _ready() -> void:
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	Session.actions_changed.connect(_update)
	Session.minigame_changed.connect(_update)
	_update()


func _update() -> void:
	start_button.visible = Session.is_host and not Session.in_game()
	start_button.disabled = Session.players.size() < 4
	start_button.text = "Start game" if Session.players.size() >= 4 \
			else "Start game (needs 4 players)"
	_update_actions()
	var has_actions := scroll.visible or choice_row.visible
	visible = (has_actions or start_button.visible) and not Session.in_minigame()


## Rebuilds the buttons: a heading and grid of players per label, then the
## buttons that stand alone.
func _update_actions() -> void:
	var actions: Array[Dictionary] = []
	actions.assign(Session.client.actions())
	if actions == _shown_actions:
		return
	_shown_actions = actions
	for child in groups.get_children() + choice_row.get_children():
		# Removed now, not at the end of the frame, so _fit_scroll measures
		# only the new buttons.
		child.get_parent().remove_child(child)
		child.queue_free()
	var grids := {}
	for action in actions:
		var button := _action_button(action)
		var lot: int = action["lot"]
		if lot < 0:
			choice_row.add_child(button)
			continue
		var label: String = action["label"]
		if not grids.has(label):
			grids[label] = _group(label)
		var resident := Session.player_on_lot(lot)
		button.text = "%d %s" % [lot + 1, resident.display_name if resident else "?"]
		button.tooltip_text = "%s %s" % [label, button.text]
		grids[label].add_child(button)
	scroll.visible = not grids.is_empty()
	choice_row.visible = actions.any(func(a: Dictionary) -> bool: return a["lot"] < 0)
	_fit_scroll.call_deferred()


## Adds a group's heading and returns its empty grid.
func _group(label: String) -> GridContainer:
	var heading := Label.new()
	heading.text = label
	heading.theme_type_variation = "HudHeading"
	groups.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	groups.add_child(grid)
	return grid


## Sizes the scroll area to its content, up to MAX_GRID_HEIGHT. A
## ScrollContainer doesn't grow with what it holds, so it is set by hand once
## the new buttons have their sizes. The panel grows up from the bottom edge
## to fit.
func _fit_scroll() -> void:
	var height := groups.get_combined_minimum_size().y
	# Rounded up with a pixel spare, or a fractional shortfall shows a
	# scroll bar for nothing.
	scroll.custom_minimum_size.y = minf(ceilf(height) + 1, MAX_GRID_HEIGHT)


func _action_button(action: Dictionary) -> Button:
	var button := Button.new()
	var label: String = action["label"]
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Shown pressed when it is the current choice. Pressing rebuilds the
	# buttons once the server confirms, so the toggle is never left stale.
	button.toggle_mode = true
	button.button_pressed = action["selected"]
	# Buttons never take keyboard focus, so arrow keys keep walking.
	button.focus_mode = Control.FOCUS_NONE
	if BUTTON_COLORS.has(label):
		button.add_theme_color_override("font_color", BUTTON_COLORS[label])
	var command: String = action["command"]
	button.pressed.connect(_on_action_pressed.bind(command))
	return button


func _on_action_pressed(command: String) -> void:
	var error := Session.submit(command)
	if error != "":
		Session.add_log_line("! " + error)
	# Undo the local toggle; the server's answer decides what is selected.
	_shown_actions = []
	_update_actions.call_deferred()


func _on_start_button_pressed() -> void:
	Session.client.start_game()
