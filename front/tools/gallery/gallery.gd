extends Control

## The style gallery: renders every page in tools/gallery/pages to a PNG, at
## whatever window size it's run at, then quits. `just gallery` runs it at a
## phone's 405x720 and a wide 960x540 and writes an index.html beside them.
##
## Run as a scene, not with --script, so autoloads (Session) exist:
##
##     godot --path front res://tools/gallery/gallery.tscn -- --out=DIR [--pages=a,b]
##
## Each page script extends GalleryPage (page.gd). A page that sets
## `variants` (like ["day", "night"]) is rendered once per variant, saved as
## <id>_<variant>.png. Everything here is dev only: tools/ is left out of
## the web export.

const PAGES := [
	preload("res://tools/gallery/pages/palette_paper.gd"),
	preload("res://tools/gallery/pages/palette_system.gd"),
	preload("res://tools/gallery/pages/type.gd"),
	preload("res://tools/gallery/pages/spacing.gd"),
	preload("res://tools/gallery/pages/surfaces.gd"),
	preload("res://tools/gallery/pages/icons.gd"),
	preload("res://tools/gallery/pages/buttons.gd"),
	preload("res://tools/gallery/pages/wax.gd"),
	preload("res://tools/gallery/pages/fields.gd"),
	preload("res://tools/gallery/pages/roster.gd"),
	preload("res://tools/gallery/pages/clock.gd"),
	preload("res://tools/gallery/pages/chat.gd"),
	preload("res://tools/gallery/pages/dialogs.gd"),
	preload("res://tools/gallery/pages/minigames.gd"),
	preload("res://tools/gallery/pages/start.gd"),
	preload("res://tools/gallery/pages/customizer.gd"),
	preload("res://tools/gallery/pages/tester.gd"),
	preload("res://tools/gallery/pages/in_game.gd"),
]

var _out := ""
var _only: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--pages="):
			_only = arg.trim_prefix("--pages=").split(",", false)
	if _out == "":
		_out = ProjectSettings.globalize_path("res://reports/gallery/%dx%d" % [get_window().size.x, get_window().size.y])
	DirAccess.make_dir_recursive_absolute(_out)
	_render_all.call_deferred()


func _render_all() -> void:
	var saved := 0
	for script: GDScript in PAGES:
		var page: GalleryPage = script.new()
		if not _only.is_empty() and page.id() not in _only:
			continue
		for variant: String in (page.variants if not page.variants.is_empty() else [""]):
			await _render(page, variant)
			saved += 1
	print("Gallery: saved %d pages in %s" % [saved, _out])
	get_tree().quit()


func _render(page: GalleryPage, variant: String) -> void:
	Tokens.use_night(variant == "night")
	if page.layer == "menu":
		ScreenScale.for_menus(get_window())
	else:
		ScreenScale.for_world(get_window())
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	page.build(stage, variant)
	for i in page.settle_frames:
		await get_tree().process_frame
	page.after_settle(stage)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var name := page.id() if variant == "" else "%s_%s" % [page.id(), variant]
	var image := get_viewport().get_texture().get_image()
	# Opaque, as on a screen: blending a see-through dark (a card's backdrop,
	# the night) also lowers the frame's alpha, and a viewer shows those
	# pixels washed out over its own background.
	image.convert(Image.FORMAT_RGB8)
	image.save_png("%s/%s.png" % [_out, name])
	# The page's nodes go first: a town still listening would leave for the
	# start screen when the page puts the session back.
	stage.queue_free()
	await get_tree().process_frame
	page.teardown(self)
	await get_tree().process_frame
	Tokens.use_night(false)
