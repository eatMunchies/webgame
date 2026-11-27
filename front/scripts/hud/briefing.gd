class_name Briefing
extends Modal

## The briefing: the machine explaining the simulation before a game, on its
## glass, and the box each player ticks to say they're ready. Its topics, in
## order: an intro (an expanded Mafia experience), the factions, how a game
## flows and what the minigames are for, and what the HUD's icons mean.
## They scroll on a short screen; the ready box stays at the bottom, under
## them.
##
## Between games the box sends GameClient.set_ready, and the host can only
## start once everyone has ticked it; starting a game clears it, so everyone
## ticks it again before the next. During a game the briefing is reading
## only. It opens by itself the first time a player enters a lobby (see
## open_on_joining), and from the briefing button beside the Last will
## button any time.

## The card's width, in units.
const WIDTH := 210.0
## The most of the screen's height the topics take before they scroll.
const SCROLL_SHARE := 0.66
## The close icon and the icons in the icon list, in units.
const CLOSE_ICON := 9
const LIST_ICON := 9
const READY_TEXT := "I understand and am ready to participate"

## The topics, in order: a heading and its points. Kept to one short line
## each, key word first, so the whole briefing scans in 10 to 15 seconds.
const TOPICS: Array[Dictionary] = [
	{"heading": "intro: an expanded mafia experience", "points": [
		"Mafia for one table: talk out loud.",
		"Your role is secret. Keep it that way.",
	]},
	{"heading": "the factions", "points": [
		"Town: find and execute the Mafia.",
		"Mafia: kill nightly, outnumber Town.",
		"Neutral: each has their own goal.",
	]},
	{"heading": "game flow and minigames", "points": [
		"Night: act, then play minigames.",
		"Minigames: do well or your act fails.",
		"Morning: see who died, role and will.",
		"Day: talk, vote, judge at the guillotine.",
	]},
]

## The icons explained in the last topic: icon name and what it means.
const ICON_MEANINGS: Array[Array] = [
	[&"briefing", "This briefing; ready up"],
	[&"role", "Your role (keep it private)"],
	[&"will", "Your last will"],
	[&"vote", "Vote for a trial"],
	[&"whisper", "Whisper to a player"],
	[&"host", "The host"],
	[&"copy", "Copy the town code"],
	[&"leave", "Leave the town"],
]

## Lobby codes the briefing has opened by itself for.
static var _opened_for: Array[String] = []

var _scroll := ScrollContainer.new()
var _ready_box := CheckBox.new()


## Makes a hidden briefing that fills `parent`.
static func create(parent: Control) -> Briefing:
	var card := Briefing.new()
	card.system = true
	card.fill(parent)
	return card


func _init() -> void:
	super()
	z_index = Tokens.Z_CARD
	width = WIDTH
	place = Place.CENTER


func _ready() -> void:
	super()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Tokens.SPACE_SM)
	rows.add_child(head)
	var title := Label.new()
	title.text = "> briefing"
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.theme_type_variation = "IconButton"
	close_button.icon = Icons.get_icon("close")
	close_button.add_theme_constant_override("icon_max_width", CLOSE_ICON)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Close"
	close_button.pressed.connect(close)
	head.add_child(close_button)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	# Each topic is a heading with its points close under it, and the topics
	# stand apart, so the eye can run down the headings.
	var topics := VBoxContainer.new()
	topics.add_theme_constant_override("separation", Tokens.SPACE_LG)
	topics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(topics)
	for topic: Dictionary in TOPICS:
		var section := _section(topics, topic["heading"])
		for point: String in topic["points"]:
			_add_label(section, "- " + point, "Body")
	var icons := _section(topics, "icon meanings")
	for meaning: Array in ICON_MEANINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Tokens.SPACE_SM)
		var icon := TextureRect.new()
		icon.texture = Icons.get_icon(meaning[0])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(LIST_ICON, LIST_ICON)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.modulate = Tokens.SYS_TEXT
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
		var label := Label.new()
		label.text = meaning[1]
		label.theme_type_variation = "Body"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.set_meta("beside_icon", true)
		row.add_child(label)
		icons.add_child(row)

	_ready_box.text = READY_TEXT
	_ready_box.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ready_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ready_box.focus_mode = Control.FOCUS_NONE
	_ready_box.toggled.connect(func(on: bool) -> void: Session.client.set_ready(on))
	rows.add_child(_ready_box)
	Session.lobby_changed.connect(_sync_ready)
	Session.phase_changed.connect(_sync_ready)
	_sync_ready()


## Shows the briefing.
func open() -> void:
	_sync_ready()
	show_modal()


## Opens the briefing the first time this player is in a lobby, between
## games and not yet ready.
func open_on_joining() -> void:
	if Session.code == "" or Session.in_game() or Session.me == null or Session.me.ready:
		return
	if Session.code in _opened_for:
		return
	_opened_for.append(Session.code)
	open()


## Whether this player still has to ready up for the next game.
static func waiting_on_me() -> bool:
	return Session.code != "" and not Session.in_game() and Session.me != null \
			and not Session.me.ready


## The ready box shows the player's readiness as the server last said, and
## only between games.
func _sync_ready() -> void:
	_ready_box.visible = Session.code != "" and not Session.in_game()
	_ready_box.set_pressed_no_signal(Session.me != null and Session.me.ready)


func _place() -> void:
	if not visible:
		return
	# The topics scroll in the room the screen has; the ready box stays below.
	_scroll.custom_minimum_size.y = roundf(size.y * SCROLL_SHARE)
	super()
	# Modal gave every wrapping label the panel's inner width; the topics
	# also leave room for the scroll bar, and the icon list for its icons.
	var bar := _scroll.get_v_scroll_bar().get_combined_minimum_size().x + Tokens.SPACE_XS
	for label: Label in _scroll.find_children("*", "Label", true, false):
		label.custom_minimum_size.x -= bar
		if label.has_meta("beside_icon"):
			label.custom_minimum_size.x -= LIST_ICON + Tokens.SPACE_SM
	# The panel grew to fit the wider labels Modal gave it first; take it
	# back to its width now they're narrower.
	panel.size = Vector2(panel.custom_minimum_size.x, 0)


## A topic: its "> heading", and a column for its points, returned.
func _section(parent: Control, heading: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", Tokens.SPACE_HAIR)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)
	_add_label(section, "> " + heading, "Heading")
	return section


func _add_label(parent: Control, text: String, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
