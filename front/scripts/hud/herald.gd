class_name Herald
extends VBoxContainer

## The town's herald: a parchment banner at the top of the town that tells
## what a morning or an execution brought, a line at a time, while the camera
## visits each body. A Sheet holds the news, a title ("Ada was found dead")
## over its lines (the cause, the role, "Rest in peace."), and under it a
## torn Document holds the dead player's last will while it's read. It's
## Salem speaking, so it's parchment (DESIGN.md); it never takes input.
##
## announce() starts a new piece of news, add_line() adds to it, show_will()
## and hide_will() handle the will, and clear() puts it all away. A title
## about a player starts with their SeatBadge, as in the roster and chat.

## The banner's widest, in units.
const WIDTH := 170.0
## How long a line takes to come in.
const LINE_SECONDS := 0.25
## The seat badge before a title's name, in units.
const BADGE_HEIGHT := 9.0

var _news := ParchmentPanel.new()
var _lines := VBoxContainer.new()
var _will := ParchmentPanel.new()
var _will_text := Label.new()
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Tokens.Z_HERALD
	add_theme_constant_override("separation", Tokens.SPACE_SM)
	visible = false


func _ready() -> void:
	for panel: ParchmentPanel in [_news, _will]:
		panel.paper_theme = true
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news.seed = 3.0
	_will.tier = ParchmentPanel.Tier.DOCUMENT
	_will.seed = 7.0
	_lines.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news.add_child(_lines)
	add_child(_news)
	var will_box := VBoxContainer.new()
	will_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = "Last will"
	heading.theme_type_variation = "Heading"
	will_box.add_child(heading)
	_will_text.theme_type_variation = "Body"
	_will_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	will_box.add_child(_will_text)
	_will.add_child(will_box)
	add_child(_will)
	_will.visible = false
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_fit)
	_fit()


## As wide as WIDTH, or the town's part of the screen less a margin when
## that's narrower (the middle column of a wide screen).
func _fit() -> void:
	var room := WIDTH
	var parent := get_parent_control()
	if parent != null and parent.size.x > 0.0:
		room = minf(WIDTH, parent.size.x - 2 * Tokens.SPACE_MD)
	for panel: ParchmentPanel in [_news, _will]:
		panel.custom_minimum_size.x = room
	_will_text.custom_minimum_size.x = room - 2 * Tokens.SPACE_MD
	for line: Control in _lines.get_children():
		line.custom_minimum_size.x = room - 2 * Tokens.SPACE_SM
	size.x = room


## Starts a new piece of news under `title`, replacing what was said. With
## `lot`, the title is about that player and starts with their seat badge.
func announce(title: String, lot := -1) -> void:
	for child in _lines.get_children():
		child.queue_free()
	_will.visible = false
	if lot < 0:
		add_line(title, "Title")
	else:
		_add_badged_title(title, lot)
	if not visible:
		visible = true
		modulate.a = 0.0
		_fade(1.0)


## Adds a line to the news: "Body" by default, or another of the paper
## theme's text styles ("Title", "Dim", "Heading").
func add_line(text: String, style := "Body") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = style
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _news.custom_minimum_size.x - 2 * Tokens.SPACE_SM
	label.modulate.a = 0.0
	_lines.add_child(label)
	create_tween().tween_property(label, "modulate:a", 1.0, LINE_SECONDS)


## A Title line with a seat badge before it: rich text, so the badge sits
## in the line and a long name still wraps and stays centered.
func _add_badged_title(title: String, lot: int) -> void:
	var line := RichTextLabel.new()
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size.x = _news.custom_minimum_size.x - 2 * Tokens.SPACE_SM
	line.add_theme_font_override("normal_font", _news.get_theme_font("font", "Title"))
	line.add_theme_font_size_override("normal_font_size", _news.get_theme_font_size("font_size", "Title"))
	line.add_theme_color_override("default_color", _news.get_theme_color("font_color", "Title"))
	line.set_meta("said", "%d %s" % [lot + 1, title])
	line.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var badge := SeatBadge.texture(lot + 1, BADGE_HEIGHT)
	line.add_image(badge, badge.get_width(), badge.get_height(), Color.WHITE, INLINE_ALIGNMENT_CENTER)
	line.add_text(" " + title)
	line.pop()
	line.modulate.a = 0.0
	_lines.add_child(line)
	create_tween().tween_property(line, "modulate:a", 1.0, LINE_SECONDS)


## Shows a will under the news; an empty one says none was found.
func show_will(text: String) -> void:
	_will_text.text = text if text.strip_edges() != "" else "No last will was found."
	_will.visible = true
	_will.modulate.a = 0.0
	create_tween().tween_property(_will, "modulate:a", 1.0, LINE_SECONDS)


func hide_will() -> void:
	_will.visible = false


## Fades the banner away.
func clear() -> void:
	if visible:
		_fade(0.0)


## The lines said so far, for tests.
func said() -> PackedStringArray:
	var out := PackedStringArray()
	for line: Control in _lines.get_children():
		if not line.is_queued_for_deletion():
			out.append(line.get_meta("said") if line.has_meta("said") else (line as Label).text)
	return out


func _fade(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", to, Tokens.DUR_BASE)
	if to == 0.0:
		_tween.tween_callback(func() -> void: visible = false)
