class_name RoleCard
extends Control

## Your role, on a card in the middle of the screen: its name, its faction
## and category, what it does at night and how it wins, and for an
## Executioner their target or for the Mafia their team. It opens on its own
## when a game starts, and from the ID card button beside the Last will
## button any time after. Close, Escape or a tap outside closes it.
##
## A spectator, who joined after the game started, gets a card saying so.

## The panel's width in units, and its share of the screen at most.
const WIDTH := 200.0
const WIDTH_SHARE := 0.92
const BACKDROP := Color(0, 0, 0, 0.55)
const FACTION_COLORS := {
	"Town": Color(0.55, 0.9, 0.55),
	"Mafia": Color(1, 0.45, 0.4),
	"Neutral": Color(0.78, 0.62, 1),
}

var _panel := PanelContainer.new()
var _rows := VBoxContainer.new()


## Makes a hidden card that fills `parent`.
static func create(parent: Control) -> RoleCard:
	var card := RoleCard.new()
	parent.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return card


func _init() -> void:
	visible = false
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	theme = HudStyle.build()
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			close())
	add_child(backdrop)
	add_child(_panel)
	_rows.add_theme_constant_override("separation", 3)
	_panel.add_child(_rows)
	resized.connect(_place)


## Shows the card for this player's role, as the client knows it now.
func open() -> void:
	var info: Dictionary = Session.client.role_info()
	if info.is_empty():
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if info["spectator"]:
		_add_label("Spectator", "HudTitle")
		_add_text("You joined after the game started, so you're dead from the start, with no role. Watch, and talk with the dead.")
	else:
		var title := _add_label(info["name"], "HudTitle")
		title.add_theme_color_override("font_color", FACTION_COLORS.get(info["faction"], RpgTheme.GOLD_BRIGHT))
		_add_label(info["category"], "HudDim")
		_add_section("Ability", info["ability"])
		_add_section("Goal", info["goal"])
		if info["target"] != "":
			_add_section("Your target", info["target"])
		var team: Array = info["team"]
		if not team.is_empty():
			_add_section("Your team", "\n".join(team))
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	_rows.add_child(close_button)
	visible = true
	_place()


func close() -> void:
	visible = false


func _add_label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)
	return label


func _add_text(text: String) -> Label:
	return _add_label(text, "")


func _add_section(heading: String, text: String) -> void:
	_add_label(heading, "HudHeading")
	_add_text(text)


func _place() -> void:
	if not visible:
		return
	var width := minf(WIDTH, size.x * WIDTH_SHARE)
	# Wrapping labels measure their height at the width they have, so each
	# gets the panel's inner width up front.
	var inner := width - _panel.get_theme_stylebox("panel").get_minimum_size().x
	for label in _rows.get_children():
		if label is Label:
			label.custom_minimum_size.x = inner
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width, 0)
	_center.call_deferred()


## Centers the card once its wrapped text has a height.
func _center() -> void:
	_panel.size = Vector2(_panel.size.x, 0)
	_panel.position = ((size - _panel.size) / 2.0).round()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
