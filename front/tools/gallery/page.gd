class_name GalleryPage
extends RefCounted

## One page of the style gallery (gallery.gd). A page builds its contents
## under `stage`, a full-screen Control, in HUD units (the window's short
## side is 180) unless `layer` is "menu" (1280x720 units). Pages are
## captured at a phone's and a wide window's size, so lay them out to fit
## both: 180x320 and 320x180 units.
##
## Helpers below build the gallery's own furniture (backgrounds, labels,
## swatches) from the design tokens, so the gallery itself shows the system.

## "world" for HUD units, "menu" for 1280x720.
var layer := "world"
## Rendered once per variant (like ["day", "night"]); empty for once. The
## variant "night" also turns on candlelight (Tokens.use_night).
var variants: Array[String] = []
## Frames to let the page lay itself out (and tweens run) before capture.
var settle_frames := 6


func id() -> String:
	return (get_script() as Script).resource_path.get_file().get_basename()


func build(_stage: Control, _variant: String) -> void:
	pass


## Runs once the page has settled, just before it's captured.
func after_settle(_stage: Control) -> void:
	pass


## Runs after the page's nodes are gone, to put anything shared back.
func teardown(_stage: Control) -> void:
	pass


## A backdrop for the whole page: the town's dusk behind everything, so
## parchment and glass both show against something like the game.
static func backdrop(stage: Control, color := Color("#3b3a2e")) -> void:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)


## A scrolling-free flow of `items` filling the page with a margin.
static func flow(stage: Control, gap := Tokens.SPACE_SM, vertical_gap := Tokens.SPACE_SM) -> HFlowContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_SM)
	stage.add_child(margin)
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", gap)
	box.add_theme_constant_override("v_separation", vertical_gap)
	margin.add_child(box)
	return box


## A label in the gallery's own caption style.
static func caption(text: String, color := Tokens.WORLD_LABEL, size := Tokens.TYPE_CAPTION) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Fonts.MONO)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func vbox(gap := Tokens.SPACE_XS) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	return box


static func hbox(gap := Tokens.SPACE_XS) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	return box


## WCAG contrast ratio between two colors, 1 to 21.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var channel := func(v: float) -> float:
		return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * channel.call(c.r) + 0.7152 * channel.call(c.g) + 0.0722 * channel.call(c.b)


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)
