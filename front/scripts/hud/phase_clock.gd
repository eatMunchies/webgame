extends ParchmentPanel

## The clock at the top of the HUD, on a Sheet of parchment: a sun or moon,
## which day or night it is, the time left in this stage counting down, and
## the stage under it (Discussion, Voting, Defense: Bram ...). Before a game
## the stage says how many are in the town, since that is what the host
## waits on.
##
## Under a rule, the town's row: its code, a copy icon (the code reads
## "Copied" for a moment) and a leave icon (a door).
##
## Past choosing, a night shows only its title: the stages it plays through
## (roleblocks, fight rounds, protection, investigations) and their timers
## are hidden, so nobody can tell from the clock what is happening tonight.
## The minigame overlay shows what the player is doing.
##
## While the connection is down Salem doesn't know: the clock just fades and
## stops, and the machine says it's resyncing (the HUD's Notice).
##
## The clock draws whatever model it's given (show_model); in a game it
## builds one every frame from the Session (collect), and the style gallery
## hands it made-up ones.

## The night stage whose name and timer still show, since players need to
## know how long they have to pick.
const CHOOSING_STAGE := "Choose your action"
## The countdown turns wax red with this many seconds or fewer left, so a
## closing vote or judgement is hard to miss.
const HURRY_SECONDS := 5
## How long the code reads "Copied" after Copy.
const COPIED_SECONDS := 1.5
## The sun or moon before the title, in units.
const SKY_ICON := 9.0
## How faint the clock goes while the connection is down.
const STALE_ALPHA := 0.45

## Set by the style gallery, so the clock shows only the models it's given.
var preview := false

var _icon := TextureRect.new()
var _title := Label.new()
var _time := Label.new()
var _stage := Label.new()
var _rule := HSeparator.new()
var _town_row := HBoxContainer.new()
var _code := Label.new()
var _copy := Button.new()
var _leave := Button.new()
var _copied_until := 0


func _ready() -> void:
	paper_theme = true
	super()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(title_row)
	_icon.custom_minimum_size = Vector2(SKY_ICON, SKY_ICON)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.self_modulate = Tokens.INK_SECONDARY
	title_row.add_child(_icon)
	_title.theme_type_variation = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_title)
	_time.add_theme_font_override("font", Fonts.BODY_BOLD)
	_time.add_theme_font_size_override("font_size", Tokens.TYPE_TITLE - 1)
	title_row.add_child(_time)

	_stage.theme_type_variation = "Body"
	_stage.add_theme_color_override("font_color", Tokens.INK_SECONDARY)
	_stage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(_stage)

	_rule.add_theme_constant_override("separation", Tokens.SPACE_SM)
	rows.add_child(_rule)

	_town_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	rows.add_child(_town_row)
	var town := Label.new()
	town.theme_type_variation = "Heading"
	town.text = "Town"
	_town_row.add_child(town)
	_code.add_theme_font_override("font", Fonts.BODY_BOLD)
	_code.add_theme_font_size_override("font_size", Tokens.TYPE_NAME)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_town_row.add_child(_code)
	_copy.theme_type_variation = "IconButton"
	_copy.icon = Icons.get_icon("copy")
	_copy.tooltip_text = "Copy the town's code"
	_copy.focus_mode = Control.FOCUS_NONE
	_copy.add_theme_constant_override("icon_max_width", int(SKY_ICON))
	_copy.pressed.connect(_on_copy_pressed)
	_town_row.add_child(_copy)
	_leave.theme_type_variation = "IconButton"
	_leave.icon = Icons.get_icon("leave")
	_leave.tooltip_text = "Leave the town"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.add_theme_constant_override("icon_max_width", int(SKY_ICON))
	_leave.pressed.connect(_on_leave_pressed)
	_town_row.add_child(_leave)
	for button in [_copy, _leave]:
		for state in ["icon_normal_color", "font_color"]:
			button.add_theme_color_override(state, Tokens.INK_SECONDARY)
		for state in ["icon_hover_color", "icon_pressed_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, Tokens.WAX)


func _process(delta: float) -> void:
	super(delta)
	if preview:
		return
	# The countdown ticks, so this reads the phase every frame. It is one
	# small Dictionary from the client, cheap next to drawing the town.
	show_model(collect())


## What the clock shows now, from the Session. The keys are show_model's.
static func collect() -> Dictionary:
	var session := Session
	var info: Dictionary = session.client.phase_info()
	var model := {
		"reconnecting": session.reconnecting,
		"night": info["night"],
		"title": info["title"],
		"stage": info["stage"],
		"seconds": info["seconds_left"],
		"code": session.code if session.in_lobby() else "",
	}
	if not session.in_game() and session.in_lobby():
		model["stage"] = _lobby_stage(session.players.size()) if info["title"] == "Lobby" \
				else "The host can start a new game"
	return model


## Draws `model`: reconnecting, night (bools); title and stage (Strings);
## seconds left (-1 for none); the town's code ("" hides the town row).
func show_model(model: Dictionary) -> void:
	if _title == null or not is_node_ready():
		return
	var night: bool = model["night"]
	var stage: String = model["stage"]
	var seconds: int = model["seconds"]
	if night and stage != CHOOSING_STAGE:
		stage = ""
		seconds = -1
	_icon.texture = Icons.get_icon("night" if night else "day")
	_title.text = model["title"]
	_stage.text = stage
	_stage.visible = stage != ""
	_time.visible = seconds >= 0
	if seconds >= 0:
		_time.text = "%d:%02d" % [seconds / 60, seconds % 60]
		_time.add_theme_color_override("font_color",
				Tokens.WAX if seconds <= HURRY_SECONDS else Tokens.INK)
	var code: String = model["code"]
	_rule.visible = code != ""
	_town_row.visible = code != ""
	_code.text = "Copied" if Time.get_ticks_msec() < _copied_until else code
	# Salem doesn't notice a desync; the clock just goes still.
	var stale: bool = model["reconnecting"]
	modulate.a = STALE_ALPHA if stale else 1.0
	_time.visible = _time.visible and not stale


## What the lobby is waiting for: more players, or the host to start.
static func _lobby_stage(count: int) -> String:
	if count < 4:
		return "%d joined, 4 to start" % count
	return "%d joined, host starts" % count


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(Session.code)
	_copied_until = Time.get_ticks_msec() + int(COPIED_SECONDS * 1000)


func _on_leave_pressed() -> void:
	Session.leave_lobby()
