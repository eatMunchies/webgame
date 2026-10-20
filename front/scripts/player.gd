extends CharacterBody2D

## Top-down player movement. Drawing is handled by the Character child,
## which layers the body and equipped parts.

const SPEED := 80.0
const WALK_FPS := 8.0

@onready var character: Character = $Character

var facing := Character.Facing.DOWN
var walk_time := 0.0


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Typing in a text box (like the game chat) shouldn't also walk.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		input = Vector2.ZERO
	# Nor should playing a night minigame.
	if Session.in_minigame():
		input = Vector2.ZERO
	velocity = input * SPEED
	move_and_slide()

	if input == Vector2.ZERO:
		walk_time = 0.0
	else:
		facing = _facing_for(input)
		walk_time += delta

	var column := int(walk_time * WALK_FPS) % Character.HFRAMES
	character.show_frame(column, facing)


## Picks the sprite row for a movement direction. Diagonals resolve to
## whichever axis is stronger, with ties going to the vertical row.
func _facing_for(direction: Vector2) -> Character.Facing:
	if absf(direction.x) > absf(direction.y):
		return Character.Facing.RIGHT if direction.x > 0 else Character.Facing.LEFT
	return Character.Facing.DOWN if direction.y > 0 else Character.Facing.UP
