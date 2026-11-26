class_name RoleCard
extends Modal

## Your role, on a parchment card in the middle of the screen: a wax seal in
## the faction's color with its initial, the role's name and category, what
## it does at night and how it wins, and for an Executioner their target or
## for the Mafia their team. It opens on its own when a game starts, and
## from the role button beside the Last will button any time after. The
## close icon, Escape or a tap outside closes it.
##
## Anything that tells your role or faction lives only here (DESIGN.md).
## A spectator, who joined after the game started, gets a card saying so.

## The card's width in units.
const WIDTH := 200.0
const FACTION_COLORS := {
	"Town": Tokens.FACTION_TOWN,
	"Mafia": Tokens.FACTION_MAFIA,
	"Neutral": Tokens.FACTION_NEUTRAL,
}
## The close icon, in units.
const CLOSE_ICON := 9


## Makes a hidden card that fills `parent`.
static func create(parent: Control) -> RoleCard:
	var card := RoleCard.new()
	card.fill(parent)
	return card


func _init() -> void:
	super()
	z_index = Tokens.Z_CARD
	width = WIDTH
	place = Place.CENTER


## Shows the card for this player's role, as the client knows it now.
func open() -> void:
	var info: Dictionary = Session.client.role_info()
	if not info.is_empty():
		open_with(info)


## Shows the card for `info`, as GameClient.role_info gives it: spectator,
## name, faction, category, ability, goal, target, team.
func open_with(info: Dictionary) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Tokens.SPACE_SM)
	rows.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if info["spectator"]:
		_add_label(names, "Spectator", "Title", false)
		_add_label(names, "Among the dead", "Dim", false)
	else:
		var seal := WaxSeal.new()
		seal.color = FACTION_COLORS.get(info["faction"], Tokens.WAX)
		seal.letter = str(info["faction"]).left(1)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(seal)
		_add_label(names, info["name"], "Title", false)
		_add_label(names, info["category"], "Dim", false)
	head.add_child(names)
	var close_button := Button.new()
	close_button.theme_type_variation = "IconButton"
	close_button.icon = Icons.get_icon("close")
	close_button.tooltip_text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.add_theme_constant_override("icon_max_width", CLOSE_ICON)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	rows.add_child(HSeparator.new())

	if info["spectator"]:
		_add_text("You joined after the game started, so you're dead from the start, with no role. Watch, and talk with the dead.")
	else:
		_add_section("Ability", info["ability"])
		_add_section("Goal", info["goal"])
		if info["target"] != "":
			_add_section("Your target", info["target"])
		var team: Array = info["team"]
		if not team.is_empty():
			_add_section("Your team", "\n".join(team))
	show_modal()


func _add_label(parent: Control, text: String, variation: String, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_text(text: String) -> Label:
	return _add_label(rows, text, "Body")


func _add_section(heading: String, text: String) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 0)
	rows.add_child(section)
	_add_label(section, heading, "Heading")
	_add_label(section, text, "Body")
