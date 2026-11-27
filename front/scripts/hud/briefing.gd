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
const SCROLL_SHARE := 0.58
## The close icon and the icons in the icon list, in units.
const CLOSE_ICON := 9
const LIST_ICON := 9
const READY_TEXT := "I understand and am ready to participate"

## The topics, in order: a heading and its paragraphs.
const TOPICS: Array[Dictionary] = [
	{"heading": "intro: an expanded mafia experience", "text": [
		"Table of Salem is Mafia for one table. Everyone plays face to face and talks out loud; your phone is your assistant.",
		"Each of you is secretly given a role. Work out who is who from what people say, what your role learns at night, and who dies. Keep your own role to yourself: nothing on your screen shows it unless you open your role card.",
	]},
	{"heading": "the factions", "text": [
		"Town: most of the table. Investigators, protectors and the odd vigilante. Town wins when every Mafia member and neutral killer is dead.",
		"Mafia: a few who know each other, talk in secret at night and kill one person a night. The Mafia wins once it's as big as everyone else.",
		"Neutral: their own goals. A Serial Killer or Arsonist wants to be the last one standing, a Jester wants to be executed, an Executioner wants their target executed, a Survivor just wants to live.",
	]},
	{"heading": "the game flow and minigames", "text": [
		"Day 0 is a short hello. Then nights and days take turns.",
		"Night: pick your action from the roster (Choose, or Use). Then every living player plays minigames. If you act, you play an evaluation, and your action only works if you play it well. An attack is a confrontation between attacker and victim. Everyone plays something every night, so nobody can tell who acted.",
		"Morning: the town gathers at each body, reads their role and their last will.",
		"Day: talk it over, then vote. Enough votes send someone to the guillotine to defend themselves; the town judges them guilty or innocent. Guilty means execution.",
	]},
]

## The icons explained in the last topic: icon name and what it means.
const ICON_MEANINGS: Array[Array] = [
	[&"briefing", "This briefing, and the box to say you're ready."],
	[&"role", "Your role card. Only you should look at it."],
	[&"will", "Your last will: notes the town reads when you die."],
	[&"vote", "Vote a player up for trial, while voting."],
	[&"whisper", "Whisper to a player, by day. Everyone sees that you whispered, only they see what."],
	[&"host", "The host, who starts the game."],
	[&"copy", "Copy the town's code to share it."],
	[&"leave", "Leave the town."],
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
	var topics := VBoxContainer.new()
	topics.add_theme_constant_override("separation", Tokens.SPACE_SM)
	topics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(topics)
	for topic: Dictionary in TOPICS:
		_add_label(topics, "> " + topic["heading"], "Heading")
		for paragraph: String in topic["text"]:
			_add_label(topics, paragraph, "Body")
	_add_label(topics, "> icon meanings", "Heading")
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
		topics.add_child(row)

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


func _add_label(parent: Control, text: String, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
