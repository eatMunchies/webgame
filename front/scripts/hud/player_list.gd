extends PanelContainer

## The list of players at the top left of the town: each player's number
## (what commands like `/vote 3` take) and name, in lot order. You are
## marked in blue. The dead are greyed and struck through, with the role
## their death revealed. While voting, each player's vote count shows beside
## them, and the heading says how many put someone on trial. Your role is at
## the bottom.
##
## Before a game it lists the lobby, with the host marked.

## The room a row has for the name and the note beside it: the list's width
## less its padding, the number column and the gaps between them.
const NAME_ROOM := 44.0

@onready var heading: Label = %Heading
@onready var rows: VBoxContainer = %PlayerRows
@onready var role_label: Label = %RoleLabel

## What the rows were last built from, to skip rebuilding when nothing
## changed: actions_changed fires for every server message.
var _shown: Array = []


func _ready() -> void:
	Session.lobby_changed.connect(_update)
	Session.phase_changed.connect(_update)
	# Vote counts arrive without a lobby change, but every message ends with
	# actions_changed.
	Session.actions_changed.connect(_update)
	_update()


func _update() -> void:
	var members: Array[Dictionary] = []
	members.assign(Session.client.members())
	var in_game := Session.in_game()
	var voting: bool = Session.client.phase_info()["voting"]
	var needed: int = Session.client.votes_needed()
	var role := Session.client.role_name()
	# Only what the rows show, so a change elsewhere (like a new look)
	# doesn't rebuild them.
	var summary: Array = [in_game, voting, needed, role]
	for member in members:
		summary.append([member["number"], member["name"], member["alive"], member["is_me"],
				member["role"], member["votes"], member["connected"], member["is_host"]])
	if summary == _shown:
		return
	_shown = summary

	var alive := members.filter(func(m: Dictionary) -> bool: return m["alive"]).size()
	if voting and needed > 0:
		heading.text = "Trial at %d votes" % needed
	elif in_game:
		heading.text = "Players: %d/%d alive" % [alive, members.size()]
	else:
		heading.text = "Players %d/%d" % [members.size(), Session.MAX_PLAYERS]
	role_label.text = "Role: %s" % role
	role_label.visible = role != "" and in_game

	for child in rows.get_children():
		# Removed now so the panel never holds both lists for a frame.
		rows.remove_child(child)
		child.queue_free()
	for member in members:
		rows.add_child(_row(member, in_game, voting))


## One player's row: number, name, and on the right their revealed role,
## their votes, or a lobby marker.
func _row(member: Dictionary, in_game: bool, voting: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var alive: bool = member["alive"]
	var number := Label.new()
	number.text = str(member["number"])
	number.custom_minimum_size.x = 8
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.theme_type_variation = "HudHeading"
	row.add_child(number)

	var name_label := Label.new()
	name_label.text = member["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if member["is_me"]:
		name_label.add_theme_color_override("font_color", HudStyle.YOU_COLOR)
	row.add_child(name_label)

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
		note.text = str(votes)
		note.theme_type_variation = "HudHeading"
	elif member["role"] != "":
		# After the game everyone's role is public, the living included.
		note.text = member["role"]
	elif not member["connected"]:
		note.text = "away"
	elif not in_game and member["is_host"]:
		note.text = "host"
	note.visible = note.text != ""
	_share_width(name_label, note)
	row.add_child(note)
	return row


## Splits the row between the name and the note when both don't fit, as with
## a dead player's long role: the name keeps at least half, so the player is
## still recognizable, and the note gets the rest, trimmed with an ellipsis.
func _share_width(name_label: Label, note: Label) -> void:
	if not note.visible:
		return
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var name_width := minf(_text_width(name_label.text), NAME_ROOM * 0.5)
	note.custom_minimum_size.x = minf(_text_width(note.text), NAME_ROOM - name_width)


## How wide text is in the HUD's font, which is the engine's default.
func _text_width(text: String) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.FONT_SIZE).x + 1


## Draws a line through a label's text, as wide as the text shows.
func _strike(label: Label) -> void:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var width := minf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, label.size.x)
	var y := roundf(label.size.y / 2.0) + 0.5
	label.draw_line(Vector2(0, y), Vector2(width, y), HudStyle.DEAD_COLOR, 1.0)
