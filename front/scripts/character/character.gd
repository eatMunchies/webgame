class_name Character
extends Node2D

## Draws a player from their appearance, plus the pet standing beside them.
## The body and parts are combined into one sheet by CharacterBaker whenever
## the appearance changes, so each frame is a single sprite. The node's
## origin is the character's feet.

enum Facing { DOWN, LEFT, RIGHT, UP }

const FRAME_SIZE := 32
const HFRAMES := 4
const VFRAMES := 4
## Where the pet stands relative to the player's feet.
const PET_OFFSET := Vector2(-22, 0)
## The first row of each body type's frame below the head: where the
## guillotine parts them (see behead()).
const NECK := {"regular": 16, "chibi": 23, "lanky": 11}

@export var appearance: CharacterAppearance:
	set(value):
		appearance = value
		if is_node_ready():
			refresh()

var _pet: Sprite2D
var _sprite: Sprite2D
var _facing := Facing.DOWN
var _column := 0


func _ready() -> void:
	_pet = _make_sprite()
	_pet.position.x = PET_OFFSET.x
	_pet.position.y += PET_OFFSET.y
	_sprite = _make_sprite()
	if appearance == null:
		appearance = CharacterAppearance.new()
	refresh()


## Rebuilds the sheet from the appearance. Call after changing the
## appearance resource's fields in place.
func refresh() -> void:
	_sprite.texture = ImageTexture.create_from_image(CharacterBaker.bake(appearance))
	var pet := PartCatalog.resolve(PartCatalog.PET_FOLDER, appearance.item_for("pet"), appearance.body_type, appearance.gender)
	_pet.texture = pet.texture
	show_frame(_column, _facing)


## Shows one animation frame. column is the walk frame (0 is idle) and
## facing picks the sheet row.
func show_frame(column: int, facing: Facing) -> void:
	_column = column
	_facing = facing
	_sprite.frame_coords = Vector2i(column, facing)
	_pet.frame_coords = Vector2i(column, facing)


## Parts the drawing at the neck, as the guillotine does: this keeps the
## body (in the frame it shows now), and the head comes back as a new
## sprite, not yet in the tree, for the caller to place and move. Its
## position is where the head was, from the character's feet. mend() puts
## the drawing back together.
func behead() -> Sprite2D:
	var neck: int = NECK.get(appearance.body_type, NECK["regular"])
	var frame := Vector2(_column, _facing) * FRAME_SIZE
	var head := Sprite2D.new()
	head.texture = _sprite.texture
	head.region_enabled = true
	head.region_rect = Rect2(frame, Vector2(FRAME_SIZE, neck))
	head.position = Vector2(0, -FRAME_SIZE + neck / 2.0)
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(frame + Vector2(0, neck), Vector2(FRAME_SIZE, FRAME_SIZE - neck))
	_sprite.position.y = -(FRAME_SIZE - neck) / 2.0
	return head


## Undoes behead() on the body; the head sprite is the caller's to free.
func mend() -> void:
	_sprite.region_enabled = false
	_sprite.hframes = HFRAMES
	_sprite.vframes = VFRAMES
	_sprite.position.y = -FRAME_SIZE / 2.0
	show_frame(_column, _facing)


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.hframes = HFRAMES
	sprite.vframes = VFRAMES
	sprite.position.y = -FRAME_SIZE / 2.0
	add_child(sprite)
	return sprite
