class_name Wardrobe
extends Control

## Character creator, styled like an RPG character screen. The character
## stands on a pedestal on the left and can be turned around with the arrows.
## On the right, tabs group the choices (body, face, outfit, gear, pet,
## house), and each slot is a grid of picture tiles showing that item on the
## current body. While the House tab is open, the left side shows the house
## with the character in its yard instead of the pedestal.
## The pickers start on whatever `appearance` and `house` hold when the screen
## opens, so a subclass can set them first to edit an existing character (see
## customizer.gd) and add its own buttons to the bottom bar.
##
## The project renders at 320x180 for crisp pixel art, which is too small for
## a form, so this screen turns that scaling off and zooms the art itself.

const WALK_FPS := 6.0
const SKIN_PRESETS: Array[Color] = [
	Color(1.0, 0.87, 0.77), Color(0.96, 0.8, 0.69), Color(0.85, 0.65, 0.5),
	Color(0.68, 0.48, 0.34), Color(0.5, 0.33, 0.22), Color(0.33, 0.21, 0.14),
	Color(0.6, 0.85, 0.6), Color(0.65, 0.75, 1.0),
]
## Slots that start filled when the appearance has no choice for them yet,
## so a fresh character has a face.
const DEFAULT_FIRST_ITEM: Array[String] = ["eyes", "mouth"]
## The tabs and the pickers on each. "body", "gender" and "skin" pick the
## body, the House tab's pickers are HouseCatalog layers, and the rest are
## PartCatalog slots or the pet. A slot added to PartCatalog later shows up on
## the Outfit tab until it's given a place here.
const TABS := {
	"Body": ["body", "gender", "skin"],
	"Face": ["eyes", "mouth"],
	"Outfit": ["hat", "chest", "legs", "gauntlets", "accessory"],
	"Gear": ["main_hand", "off_hand"],
	"Pet": [PartCatalog.PET_FOLDER],
	"House": ["roof", "facade", "yard"],
}
const HOUSE_TAB := "House"
const HOUSE_SCENE := preload("res://scenes/main/house.tscn")
## The facings in the order the arrows turn the character through.
const TURN_ORDER: Array[Character.Facing] = [
	Character.Facing.DOWN, Character.Facing.LEFT, Character.Facing.UP, Character.Facing.RIGHT,
]
const FACING_NAMES := {
	Character.Facing.DOWN: "Front", Character.Facing.LEFT: "Left",
	Character.Facing.RIGHT: "Right", Character.Facing.UP: "Back",
}
const TILE_SIZE := Vector2(76, 76)
const BODY_TILE_SIZE := Vector2(96, 112)
const HOUSE_TILE_SIZE := Vector2(112, 136)
## The smallest square of the 32px frame an item picture shows, so tiny
## items like eyes come with enough of the face around them to make sense.
const MIN_CROP := 14
## How long the skin color has to stay put before the tile pictures are
## redrawn in it, so dragging the color picker stays smooth.
const THUMBNAIL_DELAY := 0.2

var appearance := CharacterAppearance.new()
var house := HouseAppearance.new()
var walking := false
var walk_time := 0.0
var facing := Character.Facing.DOWN

## The appearance and house as the screen opened, for the Undo button.
var _original: CharacterAppearance
var _original_house: HouseAppearance
var _stage: Stage
var _tabs: TabContainer
var _random_button: Button
var _preview: Character
var _facing_label: Label
var _tiles := {}  # picker ("body", "gender" or a slot) -> {value -> Button}; "" is None
var _value_labels := {}  # picker -> the Label naming its current choice
var _swatches: Array[Button] = []
var _custom_skin: ColorPickerButton
var _thumbnail_timer := Timer.new()


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = RpgTheme.build()
	for slot in DEFAULT_FIRST_ITEM:
		var items := PartCatalog.items_for(slot)
		if not appearance.items.has(slot) and not items.is_empty():
			appearance.items[slot] = items[0]
	# A house needs every layer, so fill any the player hasn't picked yet.
	var suggestion := HouseAppearance.random(randi())
	for layer in HouseCatalog.LAYERS:
		if house.style_for(layer) == "":
			house.set(layer, suggestion.style_for(layer))
	_original = appearance.copy()
	_original_house = house.copy()
	_thumbnail_timer.one_shot = true
	_thumbnail_timer.wait_time = THUMBNAIL_DELAY
	_thumbnail_timer.timeout.connect(_draw_thumbnails.bind(_character_pickers()))
	add_child(_thumbnail_timer)
	_build()
	_apply()
	_draw_thumbnails(_tiles.keys())


func _process(delta: float) -> void:
	if walking:
		walk_time += delta
	var column := int(walk_time * WALK_FPS) % Character.HFRAMES if walking else 0
	_preview.show_frame(column, facing)


## Buttons a subclass adds to the right end of the bottom bar.
func _footer_buttons() -> Array[Button]:
	return []


func _build() -> void:
	var background := TextureRect.new()
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.35, 0.4)
	glow.fill_to = Vector2(1.2, 1.3)
	glow.gradient = Gradient.new()
	glow.gradient.set_color(0, Color(0.24, 0.19, 0.24))
	glow.gradient.set_color(1, Color(0.05, 0.04, 0.06))
	background.texture = glow
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "Customize Character"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	rows.add_child(columns)
	columns.add_child(_build_stage())
	columns.add_child(_build_tabs())
	rows.add_child(_build_footer())


## The left panel: the player's name, the character on its pedestal, and the
## controls to turn it and make it walk.
func _build_stage() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 380
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var name_label := Label.new()
	name_label.text = PlayerProfile.username if PlayerProfile.username != "" else "Adventurer"
	name_label.theme_type_variation = "HeaderLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	_stage = Stage.new()
	_stage.size_flags_vertical = SIZE_EXPAND_FILL
	_stage.texture_filter = TEXTURE_FILTER_NEAREST
	# The house goes in first so the character draws in front of it.
	_stage.house = HOUSE_SCENE.instantiate()
	_stage.house.appearance = house
	_stage.house.visible = false
	# The yard sprite sits one z level down so players walk over it in town.
	# Lift the house and character a level so the yard still draws above
	# this panel.
	_stage.house.z_index = 1
	_stage.add_child(_stage.house)
	_preview = Character.new()
	_preview.appearance = appearance
	_preview.z_index = 1
	_stage.character = _preview
	_stage.add_child(_preview)
	column.add_child(_stage)

	var turn := HBoxContainer.new()
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	turn.add_theme_constant_override("separation", 12)
	column.add_child(turn)
	var left := Button.new()
	left.text = "<"
	left.tooltip_text = "Turn left"
	left.custom_minimum_size = Vector2(44, 0)
	left.pressed.connect(_turn.bind(-1))
	turn.add_child(left)
	_facing_label = Label.new()
	_facing_label.custom_minimum_size.x = 80
	_facing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn.add_child(_facing_label)
	var right := Button.new()
	right.text = ">"
	right.tooltip_text = "Turn right"
	right.custom_minimum_size = Vector2(44, 0)
	right.pressed.connect(_turn.bind(1))
	turn.add_child(right)

	var walk_toggle := CheckBox.new()
	walk_toggle.text = "Walk"
	walk_toggle.button_pressed = walking
	walk_toggle.size_flags_horizontal = SIZE_SHRINK_CENTER
	walk_toggle.toggled.connect(func(on): walking = on)
	column.add_child(walk_toggle)
	return panel


## The right panel: one tab per group of pickers.
func _build_tabs() -> Control:
	_tabs = TabContainer.new()
	var tabs := _tabs
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	tabs.tab_changed.connect(_on_tab_changed)
	var placed: Array = []
	for pickers: Array in TABS.values():
		placed.append_array(pickers)
	for tab_name: String in TABS:
		var pickers: Array = TABS[tab_name].duplicate()
		if tab_name == "Outfit":
			for slot in PartCatalog.SLOTS:
				if slot not in placed:
					pickers.append(slot)
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var sections := VBoxContainer.new()
		sections.size_flags_horizontal = SIZE_EXPAND_FILL
		sections.add_theme_constant_override("separation", 18)
		scroll.add_child(sections)
		for picker: String in pickers:
			match picker:
				"body":
					sections.add_child(_tile_section(picker, "Body", Array(PartCatalog.BODY_TYPES)))
				"gender":
					sections.add_child(_tile_section(picker, "Gender", Array(PartCatalog.GENDERS)))
				"skin":
					sections.add_child(_skin_section())
				_ when picker in HouseCatalog.LAYERS:
					sections.add_child(_tile_section(picker, picker.capitalize(), Array(HouseCatalog.styles_for(picker))))
				_:
					sections.add_child(_tile_section(picker, picker.capitalize(), [""] + Array(PartCatalog.items_for(picker))))
	return tabs


func _build_footer() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_random_button = Button.new()
	_random_button.text = "Randomize"
	_random_button.pressed.connect(_randomize)
	bar.add_child(_random_button)
	var undo_button := Button.new()
	undo_button.text = "Undo changes"
	undo_button.tooltip_text = "Go back to how the character looked when this screen opened"
	undo_button.pressed.connect(_undo)
	bar.add_child(undo_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)
	for button in _footer_buttons():
		button.custom_minimum_size.x = 120
		bar.add_child(button)
	return bar


## A heading with the current choice beside it, over a wrapping grid of
## tiles, one per value. Body and gender tiles are bigger and labeled; item
## tiles name their item in a tooltip.
func _tile_section(picker: String, heading: String, values: Array) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	section.add_child(header)
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.theme_type_variation = "HeaderLabel"
	header.add_child(heading_label)
	var value_label := Label.new()
	value_label.theme_type_variation = "ValueLabel"
	value_label.size_flags_horizontal = SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = SIZE_SHRINK_END
	header.add_child(value_label)
	_value_labels[picker] = value_label

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	section.add_child(grid)
	var labeled := picker in ["body", "gender"] or picker in HouseCatalog.LAYERS
	_tiles[picker] = {}
	for value: String in values:
		var tile := Button.new()
		tile.theme_type_variation = "ItemTile"
		tile.toggle_mode = true
		tile.texture_filter = TEXTURE_FILTER_NEAREST
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if picker in HouseCatalog.LAYERS:
			tile.custom_minimum_size = HOUSE_TILE_SIZE
		else:
			tile.custom_minimum_size = BODY_TILE_SIZE if labeled else TILE_SIZE
		tile.tooltip_text = _display_name(picker, value)
		if labeled:
			tile.text = _display_name(picker, value)
			tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		elif value == "":
			tile.text = "None"
		tile.pressed.connect(_choose.bind(picker, value))
		grid.add_child(tile)
		_tiles[picker][value] = tile
	return section


## Round swatches for the preset skin colors, then a button that opens a
## color picker for any other color.
func _skin_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = "Skin"
	heading.theme_type_variation = "HeaderLabel"
	section.add_child(heading)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	section.add_child(row)
	for color in SKIN_PRESETS:
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.tooltip_text = "Skin color"
		swatch.add_theme_stylebox_override("normal", _swatch_box(color, RpgTheme.INK, 2))
		swatch.add_theme_stylebox_override("hover", _swatch_box(color, RpgTheme.GOLD, 2))
		swatch.add_theme_stylebox_override("pressed", _swatch_box(color, RpgTheme.GOLD_BRIGHT, 4))
		swatch.add_theme_stylebox_override("hover_pressed", _swatch_box(color, RpgTheme.GOLD_BRIGHT, 4))
		swatch.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		swatch.pressed.connect(_set_skin.bind(color))
		row.add_child(swatch)
		_swatches.append(swatch)
	_custom_skin = ColorPickerButton.new()
	_custom_skin.text = "Custom"
	_custom_skin.edit_alpha = false
	_custom_skin.custom_minimum_size = Vector2(110, 40)
	for preset in SKIN_PRESETS:
		_custom_skin.get_picker().add_preset(preset)
	_custom_skin.color_changed.connect(_set_skin)
	row.add_child(_custom_skin)
	return section


func _swatch_box(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(20)
	return box


func _choose(picker: String, value: String) -> void:
	if picker in HouseCatalog.LAYERS:
		house.set(picker, value)
		_apply()
		# Each house picture shows the other layers as they are now.
		_draw_thumbnails(Array(HouseCatalog.LAYERS))
		return
	match picker:
		"body":
			appearance.body_type = value
		"gender":
			appearance.gender = value
		_:
			appearance.items[picker] = value
	_apply()
	# Every item picture shows the item on the current body, so a new body
	# redraws them all.
	if picker in ["body", "gender"]:
		_draw_thumbnails(_character_pickers())


func _set_skin(color: Color) -> void:
	appearance.skin_color = color
	_apply()
	_thumbnail_timer.start()


func _turn(step: int) -> void:
	var index := TURN_ORDER.find(facing)
	facing = TURN_ORDER[posmod(index + step, TURN_ORDER.size())]
	_facing_label.text = FACING_NAMES[facing]


## On the House tab, rolls a random house. Anywhere else, picks a random
## item (or nothing) for every character slot, keeping the body.
func _randomize() -> void:
	if _on_house_tab():
		for layer in HouseCatalog.LAYERS:
			house.set(layer, Array(HouseCatalog.styles_for(layer)).pick_random())
		_apply()
		_draw_thumbnails(Array(HouseCatalog.LAYERS))
		return
	for picker in _character_pickers():
		if picker in ["body", "gender"]:
			continue
		var values: Array = _tiles[picker].keys()
		appearance.items[picker] = values.pick_random()
	_apply()


func _undo() -> void:
	appearance.body_type = _original.body_type
	appearance.gender = _original.gender
	appearance.skin_color = _original.skin_color
	appearance.items.assign(_original.items)
	for layer in HouseCatalog.LAYERS:
		house.set(layer, _original_house.style_for(layer))
	_apply()
	_draw_thumbnails(_tiles.keys())


func _on_tab_changed(_index: int) -> void:
	_stage.show_house = _on_house_tab()
	_random_button.tooltip_text = "Roll a random house" if _on_house_tab() else "Pick a random item for every slot"


func _on_house_tab() -> bool:
	return _tabs.get_current_tab_control().name == HOUSE_TAB


## Every picker except the house layers.
func _character_pickers() -> Array:
	return _tiles.keys().filter(func(picker): return picker not in HouseCatalog.LAYERS)


## Redraws the preview and house and shows the current choices as picked.
func _apply() -> void:
	_preview.refresh()
	_stage.house.refresh()
	_facing_label.text = FACING_NAMES[facing]
	for picker in _tiles:
		var current := _current(picker)
		for value in _tiles[picker]:
			_tiles[picker][value].set_pressed_no_signal(value == current)
		_value_labels[picker].text = _display_name(picker, current)
	for i in _swatches.size():
		_swatches[i].set_pressed_no_signal(SKIN_PRESETS[i].is_equal_approx(appearance.skin_color))
	_custom_skin.color = appearance.skin_color


func _current(picker: String) -> String:
	match picker:
		"body":
			return appearance.body_type
		"gender":
			return appearance.gender
	if picker in HouseCatalog.LAYERS:
		return house.style_for(picker)
	return appearance.item_for(picker)


## The name a tile or heading shows for a value. The starter items are
## named template_*, which players don't need to see.
func _display_name(picker: String, value: String) -> String:
	if value == "":
		return "None"
	return value.trim_prefix("template_").capitalize()


func _draw_thumbnails(pickers: Array) -> void:
	for picker in pickers:
		for value in _tiles[picker]:
			if value != "":
				_tiles[picker][value].icon = _thumbnail(picker, value)


## A picture for one tile: the bare body for body and gender tiles, the pet
## by itself, the whole house with that style for house layers, and otherwise
## the item worn on the current body, zoomed in on the part of the
## front-facing frame the item changes.
func _thumbnail(picker: String, value: String) -> Texture2D:
	if picker in HouseCatalog.LAYERS:
		var with_style := house.copy()
		with_style.set(picker, value)
		var drawing := _house_image(with_style)
		return ImageTexture.create_from_image(drawing.get_region(drawing.get_used_rect()))
	var look := CharacterAppearance.new()
	look.body_type = appearance.body_type
	look.gender = appearance.gender
	look.skin_color = appearance.skin_color
	var frame: Image
	var focus: Rect2i
	match picker:
		"body", "gender":
			if picker == "body":
				look.body_type = value
			else:
				look.gender = value
			frame = _front_frame(look)
			focus = frame.get_used_rect()
		PartCatalog.PET_FOLDER:
			var pet := PartCatalog.resolve(picker, value, look.body_type, look.gender)
			if pet.texture == null:
				return null
			frame = pet.texture.get_image().get_region(Rect2i(0, 0, Character.FRAME_SIZE, Character.FRAME_SIZE))
			focus = frame.get_used_rect()
		_:
			var bare := _front_frame(look)
			look.items[picker] = value
			frame = _front_frame(look)
			focus = _changed_area(bare, frame)
	return ImageTexture.create_from_image(_square_crop(frame, focus))


## The house's layers drawn on top of each other in one image.
func _house_image(look: HouseAppearance) -> Image:
	var drawing: Image
	for layer in HouseCatalog.LAYERS:
		var texture := HouseCatalog.texture(layer, look.style_for(layer))
		if texture == null:
			continue
		var image := texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		if drawing == null:
			drawing = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
		drawing.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return drawing if drawing != null else Image.create(1, 1, false, Image.FORMAT_RGBA8)


## The idle front-facing frame of a baked character.
func _front_frame(look: CharacterAppearance) -> Image:
	var size := Character.FRAME_SIZE
	return CharacterBaker.bake(look).get_region(Rect2i(0, 0, size, size))


## The smallest rectangle holding every pixel that differs between two
## frames, or the whole frame when none do.
func _changed_area(before: Image, after: Image) -> Rect2i:
	var low := Vector2i(Character.FRAME_SIZE, Character.FRAME_SIZE)
	var high := Vector2i(-1, -1)
	for y in Character.FRAME_SIZE:
		for x in Character.FRAME_SIZE:
			if before.get_pixel(x, y) != after.get_pixel(x, y):
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	if high.x < 0:
		return Rect2i(0, 0, Character.FRAME_SIZE, Character.FRAME_SIZE)
	return Rect2i(low, high - low + Vector2i.ONE)


## Cuts a square around focus out of a frame, with a little room around it
## and never smaller than MIN_CROP, kept inside the frame.
func _square_crop(frame: Image, focus: Rect2i) -> Image:
	var limit := frame.get_size()
	var side := mini(maxi(maxi(focus.size.x, focus.size.y) + 4, MIN_CROP), mini(limit.x, limit.y))
	var corner := focus.get_center() - Vector2i(side, side) / 2
	corner = corner.clamp(Vector2i.ZERO, limit - Vector2i(side, side))
	return frame.get_region(Rect2i(corner, Vector2i(side, side)))


## Where the preview stands, scaled to fit the space: the character and pet
## on a stone pedestal under a soft light, or, with show_house on, the house
## on a patch of grass with the character in its yard.
class Stage:
	extends Control

	## Where the character stands in house view, in house pixels from the
	## house's ground point: in the yard, to the right of the door.
	const YARD_SPOT := Vector2(16, 6)

	var character: Character
	var house: House
	var show_house := false:
		set(value):
			show_house = value
			_layout()

	func _init() -> void:
		resized.connect(_layout)

	func _layout() -> void:
		if character == null:
			return
		house.visible = show_house
		if show_house:
			var image_size := Vector2(64, 80)
			var house_zoom := clampf(floorf(minf(size.y * 0.85 / image_size.y, size.x * 0.9 / image_size.x)), 2.0, 8.0)
			house.scale = Vector2.ONE * house_zoom
			# The ground point is 72 of the drawing's 80 rows down, so this
			# centers the drawing vertically.
			house.position = Vector2(size.x / 2, size.y / 2 + (HouseCatalog.GROUND_POINT.y - image_size.y / 2) * house_zoom)
			character.scale = house.scale
			character.position = house.position + YARD_SPOT * house_zoom
		else:
			var zoom := clampf(floorf(size.y * 0.55 / Character.FRAME_SIZE), 3.0, 10.0)
			character.scale = Vector2.ONE * zoom
			# The pet stands to the left, so shift right to center the pair.
			character.position = Vector2(size.x / 2 - Character.PET_OFFSET.x * zoom / 2, size.y * 0.8)
		queue_redraw()

	func _draw() -> void:
		if character == null:
			return
		if show_house:
			var house_zoom := house.scale.x
			for i in 8:
				draw_circle(house.position - Vector2(0, 36 * house_zoom), (44 - i * 4) * house_zoom, Color(1.0, 0.85, 0.5, 0.025))
			_ellipse(house.position + Vector2(0, 6 * house_zoom), Vector2(42, 12) * house_zoom, Color(0.27, 0.36, 0.15))
			_ellipse(house.position + Vector2(0, 5 * house_zoom), Vector2(40, 10.5) * house_zoom, Color(0.38, 0.5, 0.2))
			return
		var zoom := character.scale.x
		var middle := Vector2(size.x / 2, character.position.y)
		for i in 8:
			draw_circle(middle - Vector2(0, 18 * zoom), (30 - i * 3) * zoom, Color(1.0, 0.85, 0.5, 0.025))
		var radius := 26.0 * zoom
		_ellipse(middle + Vector2(0, 4 * zoom), Vector2(radius, radius * 0.32), Color(0.2, 0.17, 0.15))
		_ellipse(middle, Vector2(radius, radius * 0.32), Color(0.45, 0.4, 0.35))
		_ellipse(middle, Vector2(radius - 2 * zoom, (radius - 2 * zoom) * 0.3), Color(0.37, 0.33, 0.29))
		_ellipse(middle, Vector2(radius * 0.8, radius * 0.18), Color(0, 0, 0, 0.18))

	func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
		draw_set_transform(center, 0.0, Vector2(1.0, radii.y / radii.x))
		draw_circle(Vector2.ZERO, radii.x, color)
		draw_set_transform(Vector2.ZERO)
