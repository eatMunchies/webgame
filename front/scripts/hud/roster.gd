extends ParchmentPanel

## The roster: every player, and what you can do to each of them right now.
## It is the HUD's main panel, a parchment Sheet of the simulated Salem: a
## column of its own on the right of a wide screen, and under the town on a
## tall one (see hud.gd). docs/DESIGN.md has the rules it follows.
##
## From the top:
## - the prompt, saying what to do now as a title ("The Town Votes",
##   "Night"), with
##   how many votes put someone on trial in wax; hidden when there's nothing
##   to do;
## - the buttons that stand alone (Guilty / Innocent / Abstain in a trial,
##   Cancel, Unvote, a night ability with no target), and before a game the
##   host's Start game, sealed in wax;
## - a heading: how many players, or how many are alive;
## - a row per player, in lot order: their SeatBadge (their number in their
##   seat's dye; what commands like `/vote 3` take), name, a note (their
##   votes, the role their death revealed, away, host), and that player's
##   buttons: the action aimed at them, and Whisper by day, except to or
##   from someone on trial. You are in woad blue; the dead are ash, struck
##   through, their badge faded.
##
## Nothing here gives your role away to someone looking at your screen: your
## role isn't written, the prompt for your night ability or the Jailer's
## choice is just "Night" or "Day", and their buttons say "Choose" or "Use"
## instead of the ability's name (the role card says what it does). A vote
## is a ballot-box icon, wax red once it's yours.
##
## Action buttons come from client.actions() and submit the same command
## typing would, so the server's answer shows in the chat log either way. The
## current choice shows pressed, filled with ink. Whisper asks the HUD for a
## whisper (`whisper_requested`), which opens the text box for the message.
##
## The panel draws from a model (show_model()), which _update() collects
## from Session; the style gallery feeds it models of its own.

## Asks for a whisper to the player with this number and name. The HUD opens
## its text prompt for the message.
signal whisper_requested(number: int, player_name: String)

## Actions everyone has, which may say what they are. Anything else is a
## role's own and is named neutrally.
const PUBLIC_ACTIONS := ["Vote", "Guilty", "Innocent", "Abstain", "Cancel", "Unvote"]
## What a role's own action aimed at a player is called on its buttons, and
## one that stands alone.
const CHOOSE := "Choose"
const USE := "Use"
## Verdicts in their meaning's ink.
const VERDICT_COLORS := {
	"Guilty": Tokens.DANGER,
	"Innocent": Tokens.SAFE,
}
## How tall a row is, in units: the least a finger can tap.
const ROW_HEIGHT := float(Tokens.TOUCH_MIN)
## The whisper icon's size in a row, in units, so it doesn't make the row
## taller than ROW_HEIGHT.
const ROW_ICON := 13.0

@onready var prompt: Label = %Prompt
@onready var choice_row: HFlowContainer = %ChoiceRow
@onready var start_button: Button = %StartButton
@onready var heading: Label = %Heading
@onready var scroll: ScrollContainer = %RosterScroll
@onready var rows: VBoxContainer = %PlayerRows

## What the panel was last built from, to skip rebuilding when nothing
## changed: actions_changed fires for every server message.
var _shown := {}
## The most the player rows may take before they scroll, in units, or 0 for
## no limit (where the panel has a column of its own). Set by the HUD.
var max_rows_height := 0.0:
	set(value):
		max_rows_height = value
		_fit_scroll.call_deferred()
## Set by the style gallery, so the panel shows only the models it's given.
var preview := false
## The votes a trial needs, in wax, under the prompt.
var _needed := Label.new()


func _ready() -> void:
	paper_theme = true
	super()
	_needed.theme_type_variation = "Dim"
	_needed.add_theme_color_override("font_color", Tokens.WAX)
	_needed.add_theme_font_override("font", Fonts.BODY_BOLD)
	_needed.visible = false
	prompt.add_sibling(_needed)
	start_button.pressed.connect(_on_start_button_pressed)
	if preview:
		return
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	Session.actions_changed.connect(_update)
	_update()


func _update() -> void:
	show_model(collect())


## What the panel shows, from Session and the client.
static func collect() -> Dictionary:
	var members: Array[Dictionary] = []
	for member: Dictionary in Session.client.members():
		var entry := member.duplicate()
		entry["can_whisper"] = Session.client.can_whisper(member["number"] - 1)
		members.append(entry)
	var info: Dictionary = Session.client.phase_info()
	return {
		"in_game": Session.in_game(),
		"night": info["night"],
		"voting": info["voting"],
		"judging": str(info["stage"]).begins_with("Judgement"),
		"needed": Session.client.votes_needed(),
		"host_can_start": Session.is_host and not Session.in_game(),
		"player_count": Session.players.size(),
		"ready_count": Session.players.filter(func(p: LobbyPlayer) -> bool: return p.ready).size(),
		"members": members,
		"actions": Session.client.actions(),
	}


## Draws the panel for `model` (see collect() for what's in it).
func show_model(model: Dictionary) -> void:
	if model == _shown:
		return
	_shown = model
	var members: Array = model["members"]
	var actions: Array = model["actions"]

	_update_prompt(model)
	_update_choices(actions, model)

	if model["in_game"]:
		var alive := members.filter(func(m: Dictionary) -> bool: return m["alive"]).size()
		heading.text = "Players · %d of %d alive" % [alive, members.size()]
	else:
		heading.text = "Players · %d of %d" % [members.size(), Session.MAX_PLAYERS]

	var aimed := {}
	for action: Dictionary in actions:
		var lot: int = action["lot"]
		if lot >= 0:
			aimed.get_or_add(lot, []).append(action)
	for child in rows.get_children():
		# Removed now so the panel never holds both lists for a frame.
		rows.remove_child(child)
		child.queue_free()
	for member: Dictionary in members:
		rows.add_child(_row(member, model, aimed.get(member["number"] - 1, [])))
	_fit_scroll.call_deferred()


## Says what to do now, without naming a role's ability.
func _update_prompt(model: Dictionary) -> void:
	var text := ""
	for action: Dictionary in model["actions"]:
		if action["lot"] >= 0:
			if action["label"] == "Vote":
				text = "The Town Votes"
			else:
				text = "Night" if model["night"] else "Day"
			break
	if text == "" and model["judging"]:
		text = "Judge the Accused"
	prompt.text = text
	prompt.visible = text != ""
	# The votes a trial needs, in wax, under the prompt.
	var needed: int = model["needed"]
	_set_needed(needed if model["voting"] and needed > 0 else 0)


func _set_needed(needed: int) -> void:
	_needed.text = "%d votes put someone on trial" % needed
	_needed.visible = needed > 0


## The buttons that stand alone, and the host's Start game.
func _update_choices(actions: Array, model: Dictionary) -> void:
	for child in choice_row.get_children():
		choice_row.remove_child(child)
		child.queue_free()
	for action: Dictionary in actions:
		if action["lot"] < 0:
			var button := _action_button(action)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice_row.add_child(button)
	choice_row.visible = choice_row.get_child_count() > 0
	var count: int = model["player_count"]
	var ready: int = model["ready_count"]
	start_button.visible = model["host_can_start"]
	start_button.disabled = count < 4 or ready < count
	if count < 4:
		start_button.text = "Start game · needs 4"
	elif ready < count:
		start_button.text = "Start game · %d of %d ready" % [ready, count]
	else:
		start_button.text = "Start game"


## One player's row: badge, name, a note, and their buttons.
func _row(member: Dictionary, model: Dictionary, aimed: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	row.custom_minimum_size.y = ROW_HEIGHT
	var alive: bool = member["alive"]
	var badge := SeatBadge.new()
	badge.number = member["number"]
	badge.faded = not alive
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.tooltip_text = "Player %d" % member["number"]
	row.add_child(badge)

	var name_label := Label.new()
	name_label.text = member["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", Tokens.TYPE_NAME)
	if member["is_me"]:
		name_label.add_theme_color_override("font_color", Tokens.YOU)
		name_label.add_theme_font_override("font", Fonts.BODY_BOLD)
	row.add_child(name_label)

	# The note is never clipped; the name gives way instead.
	var note := Label.new()
	note.theme_type_variation = "Dim"
	var votes: int = member["votes"]
	if not alive:
		# Struck through as well as greyed, so it reads without color too.
		name_label.add_theme_color_override("font_color", Tokens.DEAD)
		name_label.draw.connect(_strike.bind(name_label))
		note.text = member["role"] if member["role"] != "" else "dead"
	elif model["voting"] and votes > 0:
		note.text = "%d vote%s" % [votes, "" if votes == 1 else "s"]
		note.add_theme_color_override("font_color", Tokens.WAX)
		note.add_theme_font_override("font", Fonts.BODY_BOLD)
	elif member["role"] != "":
		# After the game everyone's role is public, the living included.
		note.text = member["role"]
	elif not member["connected"]:
		note.text = "away"
	elif not model["in_game"] and member["is_host"]:
		note.text = "host"
	# Between games, who has ticked the briefing's ready box, in verdigris.
	if not model["in_game"] and member["ready"]:
		note.text = "ready" if note.text == "" else note.text + " · ready"
		note.add_theme_color_override("font_color", Tokens.SAFE)
	note.visible = note.text != ""
	row.add_child(note)

	for action: Dictionary in aimed:
		row.add_child(_action_button(action))
	if member.get("can_whisper", false):
		var whisper := Button.new()
		whisper.icon = Icons.get_icon(&"whisper")
		whisper.theme_type_variation = "IconButton"
		whisper.focus_mode = Control.FOCUS_NONE
		whisper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		whisper.tooltip_text = "Whisper to %s" % member["name"]
		whisper.expand_icon = true
		whisper.custom_minimum_size = Vector2(ROW_ICON, ROW_HEIGHT)
		whisper.add_theme_constant_override("icon_max_width", int(ROW_ICON))
		whisper.pressed.connect(func() -> void: whisper_requested.emit(member["number"], member["name"]))
		row.add_child(whisper)
	return row


func _action_button(action: Dictionary) -> Button:
	var label: String = action["label"]
	var button := Button.new()
	if label == "Vote" and action["lot"] >= 0:
		# The ballot box, drawn straight on the paper like the whisper icon;
		# wax red once it's your vote.
		button.icon = Icons.get_icon(&"vote")
		button.theme_type_variation = "IconButton"
		button.expand_icon = true
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.tooltip_text = "Vote"
		button.custom_minimum_size.x = ROW_ICON
		button.add_theme_constant_override("icon_max_width", int(ROW_ICON))
		for state in ["icon_normal_color", "icon_focus_color"]:
			button.add_theme_color_override(state, Tokens.INK)
		for state in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			button.add_theme_color_override(state, Tokens.WAX)
	else:
		button.text = label if label in PUBLIC_ACTIONS else (CHOOSE if action["lot"] >= 0 else USE)
	# Buttons never take keyboard focus, so arrow keys keep walking.
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = ROW_HEIGHT
	# Shown pressed when it is the current choice. The server's answer
	# rebuilds the panel, so the toggle is never left stale.
	button.toggle_mode = true
	button.button_pressed = action["selected"]
	if VERDICT_COLORS.has(label):
		button.add_theme_color_override("font_color", VERDICT_COLORS[label])
	button.pressed.connect(_on_action_pressed.bind(action["command"]))
	return button


func _on_action_pressed(command: String) -> void:
	if preview:
		return
	var error := Session.submit(command)
	if error != "":
		Session.add_log_line("! " + error)
	# Undo the local toggle; the server's answer decides what is selected.
	_shown = {}
	_update.call_deferred()


func _on_start_button_pressed() -> void:
	if not preview:
		Session.client.start_game()


## Lets the rows grow to max_rows_height, then scroll. A ScrollContainer
## doesn't grow with what it holds, so its height is set by hand.
func _fit_scroll() -> void:
	if max_rows_height <= 0.0:
		scroll.custom_minimum_size.y = 0.0
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		return
	scroll.size_flags_vertical = Control.SIZE_FILL
	# Rounded up with a pixel spare, or a fractional shortfall shows a scroll
	# bar for nothing.
	var height := ceilf(rows.get_combined_minimum_size().y) + 1
	scroll.custom_minimum_size.y = minf(height, max_rows_height)


## Draws a line through a label's text, as wide as the text shows.
func _strike(label: Label) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := minf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, label.size.x)
	var y := roundf(label.size.y / 2.0) + 0.5
	label.draw_line(Vector2(0, y), Vector2(width, y), Tokens.DEAD, 1.0)
