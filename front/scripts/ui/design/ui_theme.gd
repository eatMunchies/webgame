class_name UiTheme
extends RefCounted

## Builds the two Themes everything is drawn with, from Tokens and Fonts:
## - paper(): the simulated Salem. Ink on parchment, stamped buttons, wax for
##   the one thing that matters most on a screen.
## - system(): the machine running it. Mono type on black glass, hairlines,
##   one cyan accent.
##
## Set one on the root Control of a screen or panel; everything under it
## follows. Sizes are in HUD units; `unit` scales them for screens laid out
## in other units (4 for the 1280x720 menus). Themes are cached per layer,
## unit and day or night, and rebuilt when Tokens.use_night() changes the
## paper.
##
## Variations (set `theme_type_variation`):
## - Labels: Title, Heading, Body, Caption, Dim, and in system Mono and
##   Accent.
## - Buttons: Button (stamped), WaxButton (the primary action), QuietButton
##   (a text link), IconButton (an icon, maybe a word), and in system
##   SysPrimary.

static var _cache := {}


static func paper(unit := 1.0) -> Theme:
	var key := "paper/%s/%s" % [unit, Tokens.candle]
	if not _cache.has(key):
		_cache[key] = _build_paper(unit)
	return _cache[key]


static func system(unit := 1.0) -> Theme:
	var key := "system/%s" % unit
	if not _cache.has(key):
		_cache[key] = _build_system(unit)
	return _cache[key]


static func _build_paper(u: float) -> Theme:
	var theme := Theme.new()
	theme.default_font = Fonts.BODY
	theme.default_font_size = _px(Tokens.TYPE_BODY, u)

	_label(theme, "Label", Fonts.BODY, Tokens.TYPE_BODY, Tokens.INK, u)
	_label(theme, "Title", Fonts.TITLE, Tokens.TYPE_TITLE, Tokens.INK, u)
	_label(theme, "Heading", Fonts.HEADING, Tokens.TYPE_HEADING, Tokens.INK_SECONDARY, u)
	_label(theme, "Body", Fonts.BODY, Tokens.TYPE_BODY, Tokens.INK, u)
	_label(theme, "Caption", Fonts.BODY, Tokens.TYPE_CAPTION, Tokens.INK_FAINT, u)
	_label(theme, "Dim", Fonts.BODY, Tokens.TYPE_BODY, Tokens.INK_FAINT, u)
	theme.set_color("default_color", "RichTextLabel", Tokens.INK)
	theme.set_font("normal_font", "RichTextLabel", Fonts.BODY)
	theme.set_font("bold_font", "RichTextLabel", Fonts.BODY_BOLD)
	theme.set_font("italics_font", "RichTextLabel", Fonts.BODY_ITALIC)
	theme.set_font("mono_font", "RichTextLabel", Fonts.MONO)
	theme.set_font_size("normal_font_size", "RichTextLabel", _px(Tokens.TYPE_BODY, u))
	theme.set_font_size("mono_font_size", "RichTextLabel", _px(Tokens.TYPE_MONO, u))

	theme.set_stylebox("panel", "PanelContainer",
			_box(Tokens.paper_surface, Tokens.paper_edge, 1, 0, Tokens.SPACE_SM, u))

	# Stamped: raised paper with an ink border; the choice made is filled ink.
	_button(theme, "Button", {
		"normal": [Tokens.paper_raised, Tokens.INK, Tokens.INK],
		"hover": [Tokens.paper_raised, Tokens.WAX, Tokens.WAX],
		"pressed": [Tokens.SELECTED, Tokens.SELECTED, Tokens.INK_ON_DARK],
		"hover_pressed": [Tokens.SELECTED, Tokens.WAX, Tokens.INK_ON_DARK],
		"disabled": [Tokens.paper_sunken, Tokens.INK_FAINT, Tokens.INK_FAINT],
	}, 1, 0, u, Fonts.BODY)
	# The primary action, sealed in wax.
	_button(theme, "WaxButton", {
		"normal": [Tokens.WAX, Tokens.WAX_PRESSED, Tokens.INK_ON_DARK],
		"hover": [Tokens.WAX_HOVER, Tokens.WAX_PRESSED, Tokens.INK_ON_DARK],
		"pressed": [Tokens.WAX_PRESSED, Tokens.WAX_PRESSED, Tokens.INK_ON_DARK],
		"hover_pressed": [Tokens.WAX_PRESSED, Tokens.WAX_PRESSED, Tokens.INK_ON_DARK],
		"disabled": [Tokens.paper_sunken, Tokens.INK_FAINT, Tokens.INK_FAINT],
	}, 1, Tokens.SPACE_LG, u, Fonts.BODY_BOLD)
	_quiet_button(theme, "QuietButton", Tokens.INK_SECONDARY, Tokens.WAX, Tokens.INK_FAINT, u)
	_quiet_button(theme, "IconButton", Tokens.INK, Tokens.WAX, Tokens.INK_FAINT, u)
	theme.set_stylebox("hover", "IconButton", _box(Tokens.paper_sunken, Tokens.paper_sunken, 0, 0, Tokens.SPACE_XS, u))

	for type in ["LineEdit", "TextEdit"]:
		# A ruled line to write on, on a lighter sheet.
		var well := _box(Tokens.paper_raised, Tokens.INK_RULE, 0, 0, Tokens.SPACE_SM, u)
		well.border_width_bottom = maxi(1, roundi(u))
		var focus := well.duplicate() as StyleBoxFlat
		focus.border_color = Tokens.WAX
		focus.border_width_bottom = maxi(2, roundi(2 * u))
		theme.set_stylebox("normal", type, well)
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("read_only", type, well)
		theme.set_color("font_color", type, Tokens.INK)
		theme.set_color("font_placeholder_color", type, Tokens.INK_FAINT)
		theme.set_color("caret_color", type, Tokens.WAX)
		theme.set_constant("caret_width", type, maxi(2, roundi(2 * u)))
		theme.set_color("selection_color", type, Color(Tokens.WAX, 0.25))
		theme.set_font("font", type, Fonts.BODY)
		theme.set_font_size("font_size", type, _px(Tokens.TYPE_BODY_LARGE, u))
	theme.set_color("current_line_color", "TextEdit", Color(Tokens.INK, 0.06))

	_scrollbars(theme, Color(Tokens.INK, 0.12), Tokens.INK_RULE, Tokens.INK, u)
	theme.set_stylebox("panel", "TooltipPanel", _box(Tokens.paper_raised, Tokens.INK, 1, 0, Tokens.SPACE_XS, u))
	theme.set_color("font_color", "TooltipLabel", Tokens.INK)
	theme.set_stylebox("separator", "HSeparator", _rule(Tokens.INK_RULE, u))
	return theme


static func _build_system(u: float) -> Theme:
	var theme := Theme.new()
	theme.default_font = Fonts.MONO
	theme.default_font_size = _px(Tokens.TYPE_MONO, u)

	_label(theme, "Label", Fonts.MONO, Tokens.TYPE_MONO, Tokens.SYS_TEXT, u)
	_label(theme, "Title", Fonts.MONO_BOLD, Tokens.TYPE_TITLE, Tokens.SYS_TEXT, u)
	_label(theme, "Heading", Fonts.MONO_BOLD, Tokens.TYPE_MONO, Tokens.SYS_ACCENT, u)
	_label(theme, "Body", Fonts.MONO, Tokens.TYPE_MONO, Tokens.SYS_TEXT, u)
	_label(theme, "Mono", Fonts.MONO, Tokens.TYPE_MONO, Tokens.SYS_TEXT, u)
	_label(theme, "Caption", Fonts.MONO, Tokens.TYPE_MONO_SMALL, Tokens.SYS_DIM, u)
	_label(theme, "Dim", Fonts.MONO, Tokens.TYPE_MONO, Tokens.SYS_DIM, u)
	_label(theme, "Accent", Fonts.MONO, Tokens.TYPE_MONO, Tokens.SYS_ACCENT, u)
	theme.set_color("default_color", "RichTextLabel", Tokens.SYS_TEXT)
	theme.set_font("normal_font", "RichTextLabel", Fonts.MONO)
	theme.set_font("bold_font", "RichTextLabel", Fonts.MONO_BOLD)
	theme.set_font_size("normal_font_size", "RichTextLabel", _px(Tokens.TYPE_MONO, u))

	theme.set_stylebox("panel", "PanelContainer",
			_box(Color(Tokens.SYS_BG, 0.92), Tokens.SYS_LINE, 1, 0, Tokens.SPACE_SM, u))

	_button(theme, "Button", {
		"normal": [Color(Tokens.SYS_SURFACE, 0.9), Tokens.SYS_LINE, Tokens.SYS_TEXT],
		"hover": [Color(Tokens.SYS_SURFACE, 0.9), Tokens.SYS_ACCENT, Tokens.SYS_ACCENT],
		"pressed": [Tokens.SYS_ACCENT_DIM, Tokens.SYS_ACCENT, Tokens.SYS_TEXT],
		"hover_pressed": [Tokens.SYS_ACCENT_DIM, Tokens.SYS_ACCENT, Tokens.SYS_TEXT],
		"disabled": [Color(Tokens.SYS_SURFACE, 0.5), Tokens.SYS_LINE, Tokens.SYS_DIM],
	}, 1, 0, u, Fonts.MONO)
	_button(theme, "SysPrimary", {
		"normal": [Tokens.SYS_ACCENT, Tokens.SYS_ACCENT, Tokens.SYS_BG],
		"hover": [Tokens.SYS_TEXT, Tokens.SYS_TEXT, Tokens.SYS_BG],
		"pressed": [Tokens.SYS_ACCENT_DIM, Tokens.SYS_ACCENT, Tokens.SYS_TEXT],
		"hover_pressed": [Tokens.SYS_ACCENT_DIM, Tokens.SYS_ACCENT, Tokens.SYS_TEXT],
		"disabled": [Color(Tokens.SYS_SURFACE, 0.5), Tokens.SYS_LINE, Tokens.SYS_DIM],
	}, 1, 0, u, Fonts.MONO_BOLD)
	_quiet_button(theme, "QuietButton", Tokens.SYS_DIM, Tokens.SYS_ACCENT, Color(Tokens.SYS_DIM, 0.5), u)
	_quiet_button(theme, "IconButton", Tokens.SYS_TEXT, Tokens.SYS_ACCENT, Color(Tokens.SYS_DIM, 0.5), u)

	for type in ["LineEdit", "TextEdit"]:
		var well := _box(Tokens.SYS_SURFACE, Tokens.SYS_LINE, 1, 0, Tokens.SPACE_SM, u)
		var focus := well.duplicate() as StyleBoxFlat
		focus.border_color = Tokens.SYS_ACCENT
		theme.set_stylebox("normal", type, well)
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("read_only", type, well)
		theme.set_color("font_color", type, Tokens.SYS_TEXT)
		theme.set_color("font_placeholder_color", type, Tokens.SYS_DIM)
		theme.set_color("caret_color", type, Tokens.SYS_ACCENT)
		theme.set_constant("caret_width", type, maxi(2, roundi(2 * u)))
		theme.set_color("selection_color", type, Color(Tokens.SYS_ACCENT, 0.3))
		theme.set_font("font", type, Fonts.MONO)
		theme.set_font_size("font_size", type, _px(Tokens.TYPE_BODY_LARGE, u))

	_scrollbars(theme, Color(Tokens.SYS_LINE, 0.6), Tokens.SYS_DIM, Tokens.SYS_ACCENT, u)
	theme.set_stylebox("separator", "HSeparator", _rule(Tokens.SYS_LINE, u))
	return theme


## A size in units, in this theme's pixels.
static func _px(units: float, u: float) -> int:
	return maxi(1, roundi(units * u))


static func _label(theme: Theme, type: String, font: Font, size: int, color: Color, u: float) -> void:
	if type != "Label":
		theme.set_type_variation(type, "Label")
	# Labels set no extra room between lines; the faces' own leading is enough.
	theme.set_constant("line_spacing", type, 0)
	theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, _px(size, u))
	theme.set_color("font_color", type, color)


static func _box(fill: Color, border: Color, border_units: int, radius_units: float,
		padding_units: float, u: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(_px(border_units, u) if border_units > 0 else 0)
	box.set_corner_radius_all(roundi(radius_units * u))
	box.content_margin_left = padding_units * u
	box.content_margin_right = padding_units * u
	box.content_margin_top = maxf(padding_units - 1, 0) * u
	box.content_margin_bottom = maxf(padding_units - 1, 0) * u
	return box


## Sets a button type's states, each [fill, border, text].
static func _button(theme: Theme, type: String, states: Dictionary, border_units: int,
		radius_units: float, u: float, font: Font) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	for state: String in states:
		var colors: Array = states[state]
		theme.set_stylebox(state, type, _box(colors[0], colors[1], border_units, radius_units, Tokens.SPACE_SM, u))
		var font_key := "font_color" if state == "normal" else "font_%s_color" % state
		theme.set_color(font_key, type, colors[2])
	theme.set_color("font_focus_color", type, states["normal"][2])
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, _px(Tokens.TYPE_BODY, u))


## A text-only button: no box, colored text.
static func _quiet_button(theme: Theme, type: String, text: Color, hover: Color, disabled: Color, u: float) -> void:
	theme.set_type_variation(type, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = Tokens.SPACE_XS * u
		empty.content_margin_right = Tokens.SPACE_XS * u
		empty.content_margin_top = Tokens.SPACE_HAIR * u
		empty.content_margin_bottom = Tokens.SPACE_HAIR * u
		theme.set_stylebox(state, type, empty)
	theme.set_color("font_color", type, text)
	theme.set_color("font_hover_color", type, hover)
	theme.set_color("font_pressed_color", type, hover)
	theme.set_color("font_hover_pressed_color", type, hover)
	theme.set_color("font_focus_color", type, text)
	theme.set_color("font_disabled_color", type, disabled)
	theme.set_color("icon_normal_color", type, text)
	theme.set_color("icon_hover_color", type, hover)
	theme.set_color("icon_pressed_color", type, hover)


static func _scrollbars(theme: Theme, track: Color, grabber: Color, active: Color, u: float) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var lane := _box(track, track, 0, 0, 0, u)
		theme.set_stylebox("scroll", type, lane)
		theme.set_stylebox("grabber", type, _box(grabber, grabber, 0, 0, 1, u))
		theme.set_stylebox("grabber_highlight", type, _box(active, active, 0, 0, 1, u))
		theme.set_stylebox("grabber_pressed", type, _box(active, active, 0, 0, 1, u))


static func _rule(color: Color, u: float) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = color
	line.thickness = maxi(1, roundi(u))
	return line
