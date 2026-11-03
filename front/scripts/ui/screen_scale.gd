class_name ScreenScale
extends RefCounted

## How each screen scales to fit the window, so the game looks the same at
## any window size (the window opens at 1920x1080; see project.godot).
##
## - Menus (the start screen and the customizer) are laid out for 1280x720
##   and scaled smoothly to the window. They use canvas_items scaling, which
##   draws text at the window's own resolution, so it stays sharp.
## - The town is 320x180 pixel art, scaled up by whole steps (6x at 1080p) so
##   every art pixel stays square. canvas_items keeps the HUD text sharp
##   there too.
##
## Each screen sets its own scale in _ready, since the window keeps whatever
## the last screen set.

const MENU_SIZE := Vector2i(1280, 720)
const WORLD_SIZE := Vector2i(320, 180)


static func for_menus(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = MENU_SIZE
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


static func for_world(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = WORLD_SIZE
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
