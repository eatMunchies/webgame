class_name CharacterBaker
extends RefCounted

## Combines a body and its equipped parts into one spritesheet, the same
## 4x4 grid of 32x32 frames as the source art.
##
## Parts are layered back to front in PartCatalog.SLOTS order. Any pixel
## painted pure magenta (#ff00ff) in a part erases the body and the parts
## below it at that spot, so a stick-figure chest can hide the torso under
## it. A held item on the far side of the body goes behind everything and is
## never erased.

const ERASE_COLOR := Color(1, 0, 1, 1)

## A part's pixels ready to stamp, cached per texture and mirroring.
class Layer:
	## The art with erase pixels made transparent.
	var image: Image
	## White wherever the part erases; null when it erases nothing.
	var erase: Image

static var _layers := {}  # "<path>|<mirrored>" -> Layer
static var _clear: Image


## Returns the finished sheet for an appearance.
static func bake(appearance: CharacterAppearance) -> Image:
	var size := Vector2i(Character.FRAME_SIZE * Character.HFRAMES, Character.FRAME_SIZE * Character.VFRAMES)
	var front := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var back := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	var body_texture := PartCatalog.body_texture(appearance.body_type, appearance.gender)
	if body_texture != null:
		var body := _tinted(_layer(body_texture, false).image, appearance.skin_color)
		front.blend_rect(body, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)

	for slot in PartCatalog.SLOTS:
		var part := PartCatalog.resolve(slot, appearance.item_for(slot), appearance.body_type, appearance.gender)
		if part.texture == null:
			continue
		# The off hand reuses the main-hand drawing mirrored, so the left
		# and right facing rows trade places.
		var mirrored: bool = slot == "off_hand"
		var layer := _layer(part.texture, mirrored)
		var offset := Vector2i(part.offset)
		if mirrored:
			offset.x = -offset.x
		for row in Character.VFRAMES:
			var source_row := row
			if mirrored and row in [Character.Facing.LEFT, Character.Facing.RIGHT]:
				source_row = Character.Facing.RIGHT if row == Character.Facing.LEFT else Character.Facing.LEFT
			var target := back if _is_behind(slot, row) else front
			for column in Character.HFRAMES:
				var source_column := Character.HFRAMES - 1 - column if mirrored else column
				_stamp(target, layer, Vector2i(source_column, source_row), Vector2i(column, row), offset)

	back.blend_rect(front, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return back


## A hand on the far side of the body draws behind it. The main hand is the
## character's right, so it is hidden facing left or up.
static func _is_behind(slot: String, row: int) -> bool:
	match slot:
		"main_hand":
			return row in [Character.Facing.LEFT, Character.Facing.UP]
		"off_hand":
			return row in [Character.Facing.RIGHT, Character.Facing.UP]
	return false


## Copies one frame of a layer onto one frame of the target, shifted by
## offset and clipped to the target frame so it never bleeds into a
## neighboring frame. Erase pixels clear the target before the art lands.
static func _stamp(target: Image, layer: Layer, source_cell: Vector2i, target_cell: Vector2i, offset: Vector2i) -> void:
	var frame := Vector2i(Character.FRAME_SIZE, Character.FRAME_SIZE)
	var cell := Rect2i(target_cell * frame, frame)
	var placed := Rect2i(cell.position + offset, frame).intersection(cell)
	if not placed.has_area():
		return
	var source := Rect2i(source_cell * frame + (placed.position - cell.position - offset), placed.size)
	if layer.erase != null:
		target.blit_rect_mask(_clear, layer.erase, source, placed.position)
	target.blend_rect(layer.image, source, placed.position)


static func _layer(texture: Texture2D, mirrored: bool) -> Layer:
	var key := "%s|%s" % [texture.resource_path, mirrored]
	if _layers.has(key):
		return _layers[key]
	var image := texture.get_image().duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if mirrored:
		image.flip_x()
	var layer := Layer.new()
	layer.image = image
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).is_equal_approx(ERASE_COLOR):
				if layer.erase == null:
					layer.erase = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
				layer.erase.set_pixel(x, y, Color.WHITE)
				image.set_pixel(x, y, Color.TRANSPARENT)
	if _clear == null or _clear.get_size() != image.get_size():
		_clear = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	_layers[key] = layer
	return layer


## Multiplies the grayscale body by the skin color, keeping transparency.
static func _tinted(image: Image, skin: Color) -> Image:
	var tinted := image.duplicate() as Image
	for y in tinted.get_height():
		for x in tinted.get_width():
			var c := tinted.get_pixel(x, y)
			if c.a > 0.0:
				tinted.set_pixel(x, y, Color(c.r * skin.r, c.g * skin.g, c.b * skin.b, c.a))
	return tinted
