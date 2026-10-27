class_name RpgTheme
extends RefCounted

## The look of the menu screens: dark wood panels with gold trim, like the
## character screen of an RPG. It is built in code so every color lives in
## one place. A screen uses it with `theme = RpgTheme.build()`, and its
## children pick it up.
##
## Variations to set with `theme_type_variation`:
## - "TitleLabel": the big gold title at the top of a screen.
## - "HeaderLabel": a section heading.
## - "ValueLabel": the gold name of the current choice beside a heading.
## - "ItemTile": a square picture button in a grid of choices.
## - "PrimaryButton": a screen's main action, like Save.
## - "InsetPanel": a darker well set into a panel.

const WOOD := Color(0.16, 0.12, 0.1)
const WOOD_LIGHT := Color(0.29, 0.21, 0.15)
const WOOD_DARK := Color(0.09, 0.07, 0.06)
const TRIM := Color(0.5, 0.38, 0.22)
const GOLD := Color(0.86, 0.68, 0.34)
const GOLD_BRIGHT := Color(1.0, 0.85, 0.46)
const TEXT := Color(0.93, 0.87, 0.74)
const TEXT_DIM := Color(0.62, 0.56, 0.46)
const INK := Color(0.12, 0.08, 0.05)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	# A book-style serif for titles and tabs where the system has one. Where
	# it doesn't (like the web build), Godot falls back to its default font.
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	serif.font_weight = 600

	var panel := _box(WOOD, GOLD, 3, 8, 16)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 10
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", _box(WOOD_DARK, Color(0, 0, 0, 0.6), 2, 6, 10))
	theme.set_stylebox("panel", "PopupPanel", _box(WOOD, GOLD, 2, 6, 8))
	theme.set_stylebox("panel", "TooltipPanel", _box(WOOD_DARK, GOLD, 1, 4, 6))
	theme.set_color("font_color", "TooltipLabel", TEXT)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", serif)
	theme.set_font_size("font_size", "TitleLabel", 38)
	theme.set_color("font_color", "TitleLabel", GOLD_BRIGHT)
	theme.set_color("font_outline_color", "TitleLabel", INK)
	theme.set_constant("outline_size", "TitleLabel", 10)
	theme.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_y", "TitleLabel", 3)
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", serif)
	theme.set_font_size("font_size", "HeaderLabel", 20)
	theme.set_color("font_color", "HeaderLabel", TEXT)
	theme.set_color("font_outline_color", "HeaderLabel", INK)
	theme.set_constant("outline_size", "HeaderLabel", 4)
	theme.set_type_variation("ValueLabel", "Label")
	theme.set_color("font_color", "ValueLabel", GOLD)

	_style_button(theme, "Button", WOOD_LIGHT, TRIM, TEXT)
	theme.set_type_variation("PrimaryButton", "Button")
	_style_button(theme, "PrimaryButton", GOLD, GOLD_BRIGHT, INK)
	theme.set_type_variation("ItemTile", "Button")
	_style_button(theme, "ItemTile", WOOD_DARK, Color(0.3, 0.23, 0.16), TEXT_DIM)
	var chosen := _box(Color(0.25, 0.19, 0.11), GOLD_BRIGHT, 3, 6, 10)
	chosen.shadow_color = Color(GOLD_BRIGHT, 0.35)
	chosen.shadow_size = 6
	theme.set_stylebox("pressed", "ItemTile", chosen)
	theme.set_stylebox("hover_pressed", "ItemTile", chosen)
	theme.set_stylebox("focus", "ItemTile", StyleBoxEmpty.new())
	theme.set_color("font_pressed_color", "ItemTile", GOLD_BRIGHT)
	theme.set_color("font_hover_pressed_color", "ItemTile", GOLD_BRIGHT)

	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", GOLD_BRIGHT)

	# Tabs look like folder tabs on top of the panel: the open one joins the
	# panel below it, the others sit back in darker wood.
	theme.set_font("font", "TabContainer", serif)
	# Tabs are padded wide and tall so they're easy to hit, mouse or finger.
	theme.set_font_size("font_size", "TabContainer", 22)
	var open_tab := _tab_box(WOOD_LIGHT, GOLD, 2)
	open_tab.border_width_bottom = 0
	open_tab.corner_radius_bottom_left = 0
	open_tab.corner_radius_bottom_right = 0
	var closed_tab := _tab_box(WOOD_DARK, TRIM, 1)
	closed_tab.corner_radius_bottom_left = 0
	closed_tab.corner_radius_bottom_right = 0
	var hover_tab := closed_tab.duplicate()
	hover_tab.border_color = GOLD
	theme.set_stylebox("tab_selected", "TabContainer", open_tab)
	theme.set_stylebox("tab_unselected", "TabContainer", closed_tab)
	theme.set_stylebox("tab_hovered", "TabContainer", hover_tab)
	theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	var tab_panel := _box(WOOD_LIGHT.darkened(0.25), GOLD, 2, 6, 12)
	tab_panel.corner_radius_top_left = 0
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_color("font_selected_color", "TabContainer", GOLD_BRIGHT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)
	theme.set_constant("side_margin", "TabContainer", 0)

	var track := _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 4, 0)
	track.content_margin_left = 6
	track.content_margin_right = 6
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", _box(TRIM, TRIM, 0, 4, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(GOLD, GOLD, 0, 4, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(GOLD_BRIGHT, GOLD_BRIGHT, 0, 4, 0))
	return theme


## A rounded box with a border all round and the same padding on every side.
static func _box(color: Color, border: Color, border_width: int, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(padding)
	return box


## A tab's box: wide, tall padding so it's a big target.
static func _tab_box(color: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _box(color, border, border_width, 6, 0)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


## Normal, hover, pressed and disabled looks for a button type, all from one
## fill, border and text color.
static func _style_button(theme: Theme, type: String, fill: Color, border: Color, text: Color) -> void:
	theme.set_stylebox("normal", type, _box(fill, border, 2, 6, 10))
	theme.set_stylebox("hover", type, _box(fill.lightened(0.12), GOLD_BRIGHT, 2, 6, 10))
	theme.set_stylebox("pressed", type, _box(fill.darkened(0.25), GOLD_BRIGHT, 2, 6, 10))
	theme.set_stylebox("hover_pressed", type, _box(fill.darkened(0.15), GOLD_BRIGHT, 2, 6, 10))
	theme.set_stylebox("disabled", type, _box(fill.darkened(0.4), border.darkened(0.4), 2, 6, 10))
	var focus := _box(Color(0, 0, 0, 0), Color(GOLD_BRIGHT, 0.6), 1, 6, 10)
	focus.draw_center = false
	theme.set_stylebox("focus", type, focus)
	for state in ["font_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(state, type, text)
	for state in ["font_hover_color", "font_hover_pressed_color"]:
		theme.set_color(state, type, text if type == "PrimaryButton" else GOLD_BRIGHT)
	theme.set_color("font_disabled_color", type, Color(text, 0.4))
