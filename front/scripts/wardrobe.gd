class_name Wardrobe
extends Control

## Character creator preview. Pick a body, skin and parts on the left and see
## the combined sprite walking in all four directions on the right. The
## pickers start on whatever `appearance` holds when the screen opens, so a
## subclass can set it first to edit an existing character (see customizer.gd).
##
## The project renders at 320x180 for crisp pixel art, which is too small for
## a form, so this screen turns that scaling off and zooms the characters
## itself instead.

const PREVIEW_SCALE := 5.0
const PREVIEW_SPACING := 240.0
const WALK_FPS := 6.0
const SKIN_PRESETS: Array[Color] = [
	Color(1.0, 0.87, 0.77), Color(0.96, 0.8, 0.69), Color(0.85, 0.65, 0.5),
	Color(0.68, 0.48, 0.34), Color(0.5, 0.33, 0.22), Color(0.33, 0.21, 0.14),
	Color(0.6, 0.85, 0.6), Color(0.65, 0.75, 1.0),
]
## Slots that start filled when the appearance has no choice for them yet,
## so a fresh character has a face.
const DEFAULT_FIRST_ITEM: Array[String] = ["eyes", "mouth"]

var appearance := CharacterAppearance.new()
var previews: Array[Character] = []
var walk_time := 0.0
var walking := true
var _pickers := {}  # slot name -> OptionButton


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_previews()
	_build_controls()
	_apply()


func _process(delta: float) -> void:
	if walking:
		walk_time += delta
	var column := int(walk_time * WALK_FPS) % Character.HFRAMES if walking else 0
	for facing in previews.size():
		previews[facing].show_frame(column, facing)


func _build_previews() -> void:
	var names := ["Down", "Left", "Right", "Up"]
	for facing in names.size():
		var character := Character.new()
		character.appearance = appearance
		character.scale = Vector2.ONE * PREVIEW_SCALE
		character.position = Vector2(440 + facing * PREVIEW_SPACING, 480)
		add_child(character)
		previews.append(character)
		var label := Label.new()
		label.text = names[facing]
		label.position = character.position + Vector2(-20, 20)
		add_child(label)


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = 300
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)

	_add_row(grid, "Body", _choice(PartCatalog.BODY_TYPES, appearance.body_type, func(v): appearance.body_type = v))
	_add_row(grid, "Gender", _choice(PartCatalog.GENDERS, appearance.gender, func(v): appearance.gender = v))

	var skin := ColorPickerButton.new()
	skin.color = appearance.skin_color
	skin.custom_minimum_size = Vector2(140, 28)
	for preset in SKIN_PRESETS:
		skin.get_picker().add_preset(preset)
	skin.color_changed.connect(func(c): appearance.skin_color = c; _apply())
	_add_row(grid, "Skin", skin)

	for slot in PartCatalog.SLOTS.keys() + [PartCatalog.PET_FOLDER]:
		var picker := _item_picker(slot)
		_pickers[slot] = picker
		_add_row(grid, slot.capitalize(), picker)

	var random_button := Button.new()
	random_button.text = "Randomize"
	random_button.pressed.connect(_randomize)
	var walk_toggle := CheckBox.new()
	walk_toggle.text = "Walk"
	walk_toggle.button_pressed = walking
	walk_toggle.toggled.connect(func(on): walking = on)
	grid.add_child(random_button)
	grid.add_child(walk_toggle)


func _add_row(grid: GridContainer, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(control)


## A dropdown over fixed values, starting on current, that calls on_pick
## with the chosen value.
func _choice(values: Array[String], current: String, on_pick: Callable) -> OptionButton:
	var button := OptionButton.new()
	for value in values:
		button.add_item(value.capitalize())
	button.select(maxi(0, values.find(current)))
	button.item_selected.connect(func(i): on_pick.call(values[i]); _apply())
	return button


## A dropdown of the items on disk for a slot, with "None" first.
func _item_picker(slot: String) -> OptionButton:
	var items := PartCatalog.items_for(slot)
	var button := OptionButton.new()
	button.add_item("None")
	for item in items:
		button.add_item(item.capitalize())
	button.set_meta("items", items)
	if appearance.items.has(slot):
		# Index 0 is "None", so an item's index is its position plus one.
		button.select(items.find(appearance.items[slot]) + 1)
	elif slot in DEFAULT_FIRST_ITEM and not items.is_empty():
		button.select(1)
		appearance.items[slot] = items[0]
	button.item_selected.connect(func(i): _set_item(slot, i))
	return button


func _set_item(slot: String, index: int) -> void:
	var items: PackedStringArray = _pickers[slot].get_meta("items")
	appearance.items[slot] = "" if index == 0 else items[index - 1]
	_apply()


func _randomize() -> void:
	for slot in _pickers:
		var picker: OptionButton = _pickers[slot]
		var index := randi_range(0, picker.item_count - 1)
		picker.select(index)
		_set_item(slot, index)


func _apply() -> void:
	for character in previews:
		character.refresh()
