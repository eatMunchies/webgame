class_name Corpse
extends Node2D

## A dead player's body, lying on its side on the road in front of their
## house (CulDeSac.road_spot) for the rest of the game. Unlike their ghost
## (a RemotePlayer the living can't see), everyone sees it. It's their character in its standing frame,
## turned on its side and greyed; someone executed lies with their head
## beside them.

const TINT := Color(0.72, 0.72, 0.78)
## Where an executed player's head lies from their neck, along the body,
## and how it's turned.
const HEAD_GAP := Vector2(0, -4)
const HEAD_TILT := 0.5

var character := Character.new()
var _head: Sprite2D


func _init() -> void:
	# Turned a quarter, head to the right, centered on this node.
	character.rotation = PI / 2
	character.position = Vector2(-Character.FRAME_SIZE / 2.0 + 4, -3)
	character.modulate = TINT
	add_child(character)


func show_look(look: CharacterAppearance, beheaded := false) -> void:
	if _head != null:
		_head.queue_free()
		_head = null
		character.mend()
	if look != null and look != character.appearance:
		character.appearance = look
	character.show_frame(0, Character.Facing.DOWN)
	if beheaded:
		_head = character.behead()
		_head.position += HEAD_GAP
		_head.rotation = HEAD_TILT
		character.add_child(_head)
