extends PanelContainer

## The roster: every player, and what you can do to each of them right now.
## It is the HUD's main panel: a column of its own on the right of a wide
## screen, and under the town on a tall one (see hud.gd).
##
## From the top:
## - the prompt, saying what to do now in big gold letters ("Vote: put
##   someone on trial"), hidden when there's nothing to do;
## - the buttons that stand alone (Guilty / Innocent / Abstain in a trial,
##   Alert, Ignite, Unvote, Cancel), and before a game the host's Start game;
## - a heading with how many are alive, or while voting how many votes put
##   someone on trial;
## - a row per player, in lot order: their number in a circle of their
##   seat's color (NumberBadge; what commands like `/vote 3` take), name, a
##   note (their votes while voting, the role their death revealed, away,
##   host), and that player's buttons: the action aimed at them (Vote, Jail,
##   or your night ability like Heal), and Whisper by day, except to or from
##   someone on trial. You are in blue; the dead are greyed and struck
##   through.
##
## Your own role isn't written here, so nobody reads it over your shoulder;
## the role card (the ID card button) has it.
##
## Action buttons come from client.actions() and submit the same command
## typing would, so the server's answer shows in the chat log either way. The
## current choice shows pressed. Whisper asks the HUD for a whisper
## (`whisper_requested`), which opens a text box in the middle of the screen
## for the message.

## Asks for a whisper to the player with this number and name. The HUD opens
## its text prompt for the message.
signal whisper_requested(number: int, player_name: String)

## What the prompt says for an action aimed at players, by its label. Any
## other label (a night ability) reads "Heal: pick a player".
const PROMPTS := {
	"Vote": "Vote: put someone on trial",
	"Jail": "Jail: pick tonight's prisoner",
}
## Standalone buttons whose meaning a color helps with.
const BUTTON_COLORS := {
	"Guilty": HudStyle.DANGER_COLOR,
	"Innocent": HudStyle.SAFE_COLOR,
	"Execute": HudStyle.DANGER_COLOR,
}
const WHISPER := "Whisper"

@onready var prompt: Label = %Prompt
@onready var choice_row: HFlowContainer = %ChoiceRow
@onready var start_button: Button = %StartButton
@onready var heading: Label = %Heading
@onready var scroll: ScrollContainer = %RosterScroll
@onready var rows: VBoxContainer = %PlayerRows

## What the panel was last built from, to skip rebuilding when nothing
## changed: actions_changed fires for every server message.
var _shown: Array = []
## The most the player rows may take before they scroll, in units, or 0 for
## no limit (where the panel has a column of its own). Set by the HUD.
var max_rows_height := 0.0:
	set(value):
		max_rows_height = value
		_fit_scroll.call_deferred()


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	Session.actions_changed.connect(_update)
	_update()


func _update() -> void:
	var members: Array[Dictionary] = []
	members.assign(Session.client.members())
	var actions: Array[Dictionary] = []
	actions.assign(Session.client.actions())
	var info: Dictionary = Session.client.phase_info()
	var in_game := Session.in_game()
	var voting: bool = info["voting"]
	var needed: int = Session.client.votes_needed()
	var role := Session.client.role_name()
	var host_can_start := Session.is_host and not in_game
	# Only what the panel shows, so a change elsewhere (like a new look)
	# doesn't rebuild it.
	var summary: Array = [in_game, voting, needed, role, host_can_start,
			Session.players.size(), actions]
	var whisperable := {}
	for member in members:
		var lot: int = member["number"] - 1
		whisperable[lot] = Session.client.can_whisper(lot)
		summary.append([member["number"], member["name"], member["alive"], member["is_me"],
				member["role"], member["votes"], member["connected"], member["is_host"],
				whisperable[lot]])
	if summary == _shown:
		return
	_shown = summary

	_update_prompt(actions, info, voting, needed)
	_update_choices(actions, host_can_start)

	var alive := members.filter(func(m: Dictionary) -> bool: return m["alive"]).size()
	if in_game:
		heading.text = "Players: %d/%d alive" % [alive, members.size()]
	else:
		heading.text = "Players %d/%d" % [members.size(), Session.MAX_PLAYERS]

	var aimed := {}
	for action in actions:
		var lot: int = action["lot"]
		if lot >= 0:
			aimed.get_or_add(lot, []).append(action)
	for child in rows.get_children():
		# Removed now so the panel never holds both lists for a frame.
		rows.remove_child(child)
		child.queue_free()
	for member in members:
		var lot: int = member["number"] - 1
		rows.add_child(_row(member, in_game, voting, aimed.get(lot, []), whisperable[lot]))
	_fit_scroll.call_deferred()


## Says what to do now: the action aimed at players, or a trial's verdict.
func _update_prompt(actions: Array[Dictionary], info: Dictionary, voting: bool, needed: int) -> void:
	var text := ""
	for action in actions:
		if action["lot"] >= 0:
			var label: String = action["label"]
			text = PROMPTS.get(label, "%s: pick a player" % label)
			break
	if text == "" and str(info["stage"]).begins_with("Judgement"):
		text = "Judge the accused"
	if voting and needed > 0:
		text += " · %d votes" % needed if text != "" else "Trial at %d votes" % needed
	prompt.text = text
	prompt.visible = text != ""


## The buttons that stand alone, and the host's Start game.
func _update_choices(actions: Array[Dictionary], host_can_start: bool) -> void:
	for child in choice_row.get_children():
		choice_row.remove_child(child)
		child.queue_free()
	for action in actions:
		if action["lot"] < 0:
			var button := _action_button(action)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice_row.add_child(button)
	choice_row.visible = choice_row.get_child_count() > 0
	var count := Session.players.size()
	start_button.visible = host_can_start
	start_button.disabled = count < 4
	start_button.text = "Start game" if count >= 4 else "Start game (needs 4 players)"


## One player's row: number, name, a note, and their buttons.
func _row(member: Dictionary, in_game: bool, voting: bool, aimed: Array,
		can_whisper: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var alive: bool = member["alive"]
	var number := TextureRect.new()
	number.texture = NumberBadge.texture(member["number"])
	number.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	number.custom_minimum_size.x = 11
	number.tooltip_text = "Player %d" % member["number"]
	row.add_child(number)

	var name_label := Label.new()
	name_label.text = member["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if member["is_me"]:
		name_label.add_theme_color_override("font_color", HudStyle.YOU_COLOR)
	row.add_child(name_label)

	# The note is never clipped; the name gives way instead. A clipped label in
	# a row is sized to its minimum, which is a pixel, so votes, deaths and
	# the host never showed.
	var note := Label.new()
	note.theme_type_variation = "HudDim"
	var votes: int = member["votes"]
	if not alive:
		# Struck through as well as greyed, so it reads without color too.
		name_label.add_theme_color_override("font_color", HudStyle.DEAD_COLOR)
		number.modulate = HudStyle.DEAD_COLOR
		name_label.draw.connect(_strike.bind(name_label))
		note.text = member["role"] if member["role"] != "" else "dead"
	elif voting and votes > 0:
		note.text = "%d vote%s" % [votes, "" if votes == 1 else "s"]
		note.theme_type_variation = "HudHeading"
	elif member["role"] != "":
		# After the game everyone's role is public, the living included.
		note.text = member["role"]
	elif not member["connected"]:
		note.text = "away"
	elif not in_game and member["is_host"]:
		note.text = "host"
	note.visible = note.text != ""
	row.add_child(note)

	for action: Dictionary in aimed:
		row.add_child(_action_button(action))
	if can_whisper:
		var whisper := _button(WHISPER)
		whisper.tooltip_text = "Whisper to %s" % member["name"]
		whisper.pressed.connect(func() -> void: whisper_requested.emit(member["number"], member["name"]))
		row.add_child(whisper)
	return row


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	# Buttons never take keyboard focus, so arrow keys keep walking.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _action_button(action: Dictionary) -> Button:
	var label: String = action["label"]
	var button := _button(label)
	# Shown pressed when it is the current choice. The server's answer
	# rebuilds the panel, so the toggle is never left stale.
	button.toggle_mode = true
	button.button_pressed = action["selected"]
	if BUTTON_COLORS.has(label):
		button.add_theme_color_override("font_color", BUTTON_COLORS[label])
	button.pressed.connect(_on_action_pressed.bind(action["command"]))
	return button


func _on_action_pressed(command: String) -> void:
	var error := Session.submit(command)
	if error != "":
		Session.add_log_line("! " + error)
	# Undo the local toggle; the server's answer decides what is selected.
	_shown = []
	_update.call_deferred()


func _on_start_button_pressed() -> void:
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
	var size := label.get_theme_font_size("font_size")
	var width := minf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, label.size.x)
	var y := roundf(label.size.y / 2.0) + 0.5
	label.draw_line(Vector2(0, y), Vector2(width, y), HudStyle.DEAD_COLOR, 1.0)
