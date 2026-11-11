class_name HudStyle
extends RefCounted

## The look of the in-game HUD: small, translucent panels in the menu
## screens' dark wood and gold, so the game reads as one piece. The colors
## come from RpgTheme; the sizes are for the town's 320x180 viewport, where
## text is 6 to 8 pixels tall and every pixel of padding shows. Panels are
## see-through so the town stays visible behind them.
##
## The HUD root sets `theme = HudStyle.build()` and every panel, label and
## button under it picks it up. Variations to set with
## `theme_type_variation`:
## - "HudTitle": the big gold heading, like "Day 2".
## - "HudHeading": a small gold heading over a group, like "Vote".
## - "HudDim": quieter text, like a hint or a dead player's role.

const FONT_SIZE := 6
const PANEL_ALPHA := 0.8
## The player's own name, wherever the HUD lists players.
const YOU_COLOR := Color(0.55, 0.78, 1)
const DEAD_COLOR := Color(0.55, 0.52, 0.48)
const DANGER_COLOR := Color(1, 0.45, 0.4)
const SAFE_COLOR := Color(0.55, 0.9, 0.55)
const NIGHT_TITLE_COLOR := Color(0.72, 0.78, 1)

## The theme, built once and shared by everything that uses it.
static var _theme: Theme


static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	_theme = theme
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", panel_box())

	theme.set_color("font_color", "Label", RpgTheme.TEXT)
	theme.set_type_variation("HudTitle", "Label")
	theme.set_font_size("font_size", "HudTitle", 8)
	theme.set_color("font_color", "HudTitle", RpgTheme.GOLD_BRIGHT)
	theme.set_color("font_outline_color", "HudTitle", RpgTheme.INK)
	theme.set_constant("outline_size", "HudTitle", 2)
	theme.set_type_variation("HudHeading", "Label")
	theme.set_color("font_color", "HudHeading", RpgTheme.GOLD)
	theme.set_type_variation("HudDim", "Label")
	theme.set_color("font_color", "HudDim", RpgTheme.TEXT_DIM)

	theme.set_color("default_color", "RichTextLabel", RpgTheme.TEXT)

	var fill := Color(RpgTheme.WOOD_LIGHT, 0.92)
	theme.set_stylebox("normal", "Button", _box(fill, RpgTheme.TRIM, 1, 2))
	theme.set_stylebox("hover", "Button", _box(fill.lightened(0.12), RpgTheme.GOLD_BRIGHT, 1, 2))
	# The current choice is filled gold, so it stands out at a glance.
	theme.set_stylebox("pressed", "Button", _box(RpgTheme.GOLD, RpgTheme.GOLD_BRIGHT, 1, 2))
	theme.set_stylebox("hover_pressed", "Button", _box(RpgTheme.GOLD_BRIGHT, RpgTheme.GOLD_BRIGHT, 1, 2))
	theme.set_stylebox("disabled", "Button", _box(fill.darkened(0.4), RpgTheme.TRIM.darkened(0.4), 1, 2))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", RpgTheme.TEXT)
	theme.set_color("font_focus_color", "Button", RpgTheme.TEXT)
	theme.set_color("font_hover_color", "Button", RpgTheme.GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "Button", RpgTheme.INK)
	theme.set_color("font_hover_pressed_color", "Button", RpgTheme.INK)
	theme.set_color("font_disabled_color", "Button", Color(RpgTheme.TEXT, 0.4))

	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, _box(Color(RpgTheme.INK, 0.9), RpgTheme.TRIM, 1, 2))
		theme.set_stylebox("focus", type, _box(Color(RpgTheme.INK, 0.9), RpgTheme.GOLD_BRIGHT, 1, 2))
		theme.set_color("font_color", type, RpgTheme.TEXT)
		theme.set_color("font_placeholder_color", type, Color(RpgTheme.TEXT_DIM, 0.8))
		theme.set_color("caret_color", type, RpgTheme.GOLD_BRIGHT)

	# Thin scroll bars: the default ones would take a tenth of a panel.
	for type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 1)
		track.set_content_margin_all(1)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, _box(RpgTheme.TRIM, RpgTheme.TRIM, 0, 1))
		theme.set_stylebox("grabber_highlight", type, _box(RpgTheme.GOLD, RpgTheme.GOLD, 0, 1))
		theme.set_stylebox("grabber_pressed", type, _box(RpgTheme.GOLD_BRIGHT, RpgTheme.GOLD_BRIGHT, 0, 1))
	return theme


## The HUD's panel: dark wood with a thin trim, see-through enough to show
## the town.
static func panel_box() -> StyleBoxFlat:
	var box := _box(Color(RpgTheme.WOOD_DARK, PANEL_ALPHA), Color(RpgTheme.TRIM, 0.9), 1, 3)
	box.set_corner_radius_all(2)
	return box


## A box with a border all round and the same padding on every side, a
## little less above and below so rows of buttons stay compact.
static func _box(color: Color, border: Color, border_width: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(1)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = maxf(padding - 1, 0)
	box.content_margin_bottom = maxf(padding - 1, 0)
	return box
