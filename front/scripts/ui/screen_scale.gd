class_name ScreenScale
extends RefCounted

## How each screen scales to fit the window, so the game looks the same at
## any window size (the window opens at 1920x1080; see project.godot).
##
## - Menus (the start screen and the customizer) are laid out for 1280x720
##   and scaled smoothly to the window. They use canvas_items scaling, which
##   draws text at the window's own resolution, so it stays sharp.
## - The town and its HUD are laid out in units where the window's short
##   side is WORLD_SHORT_SIDE (180) units, so a 16:9 landscape window is
##   320x180 units (6 pixels each at 1080p) and a portrait phone is 180
##   units wide and as tall as it is. canvas_items keeps the HUD text sharp
##   at any scale. The town's pixel art is drawn by its camera at a whole
##   number of screen pixels per art pixel (world_zoom), so it stays square.
##
## Each screen sets its own scale in _ready, since the window keeps whatever
## the last screen set.

const MENU_SIZE := Vector2i(1280, 720)
const WORLD_SHORT_SIDE := 180


static func for_menus(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = MENU_SIZE
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


static func for_world(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i(WORLD_SHORT_SIDE, WORLD_SHORT_SIDE)
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


## The Camera2D zoom that draws each art pixel as a whole number of screen
## pixels, as close as that gets to one art pixel per unit. The window's own
## scale (screen pixels per unit) is rarely whole, so the zoom makes up the
## difference: at 1080p it is exactly 1.
static func world_zoom(viewport: Viewport) -> float:
	var units := viewport.get_visible_rect().size
	var pixels := Vector2(viewport.get_window().size)
	if units.x <= 0.0 or pixels.x <= 0.0:
		return 1.0
	var pixels_per_unit := pixels.x / units.x
	return maxf(roundf(pixels_per_unit), 1.0) / pixels_per_unit
