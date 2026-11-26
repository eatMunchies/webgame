class_name Corpse
extends Node2D

## A dead player's body, lying on its side in front of their house for the
## rest of the game. Unlike their ghost (a RemotePlayer the living can't
## see), everyone sees it. It's their character in its standing frame,
## turned on its side and greyed.

## Where a body lies, from its house's ground point: on the path in front.
const OFFSET := Vector2(0, 18)
const TINT := Color(0.72, 0.72, 0.78)

var character := Character.new()


func _init() -> void:
	# Turned a quarter, head to the right, centered on this node.
	character.rotation = PI / 2
	character.position = Vector2(-Character.FRAME_SIZE / 2.0 + 4, -3)
	character.modulate = TINT
	add_child(character)


func show_look(look: CharacterAppearance) -> void:
	if look != null:
		character.appearance = look
	character.show_frame(0, Character.Facing.DOWN)
