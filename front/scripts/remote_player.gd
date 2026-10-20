class_name RemotePlayer
extends Node2D

## Someone else's character in the town. Their client sends where they are a
## few times a second and the server passes it on; this glides toward the
## latest position so the steps in between look like walking. Others walk
## through them: only the local player has collisions.

## How quickly the character closes the gap to where it should be. Higher
## follows more tightly; lower looks smoother but lags further behind.
const CATCH_UP := 14.0
## A jump longer than this is a teleport (like spawning), not a walk.
const TELEPORT_DISTANCE := 96.0
const WALK_FPS := 8.0
const DEAD_ALPHA := 0.45

@onready var character: Character = $Character
@onready var name_label: Label = $NameLabel

var target_position := Vector2.ZERO
var facing := Character.Facing.DOWN
var walking := false
var _walk_time := 0.0
var _placed := false


## Shows a player's name, look, and whether they are alive. Call whenever
## the lobby changes.
func show_player(player: LobbyPlayer) -> void:
	name_label.text = "%d %s" % [player.number, player.display_name]
	modulate.a = 1.0 if player.alive else DEAD_ALPHA
	if player.appearance != null and not _same_look(player.appearance):
		character.appearance = player.appearance


## Moves toward a reported position. The first report places the character
## there directly.
func move_to(new_position: Vector2, new_facing: Character.Facing, is_walking: bool) -> void:
	target_position = new_position
	facing = new_facing
	walking = is_walking
	if not _placed or position.distance_to(new_position) > TELEPORT_DISTANCE:
		position = new_position
		_placed = true


func _process(delta: float) -> void:
	position = position.lerp(target_position, 1.0 - exp(-CATCH_UP * delta))
	# Still catching up counts as walking, so a stop doesn't freeze mid-step.
	var moving := walking or position.distance_to(target_position) > 0.5
	if moving:
		_walk_time += delta
	else:
		_walk_time = 0.0
	character.show_frame(int(_walk_time * WALK_FPS) % Character.HFRAMES, facing)


func _same_look(look: CharacterAppearance) -> bool:
	var current := character.appearance
	return current != null and current.body_type == look.body_type \
			and current.gender == look.gender \
			and current.skin_color == look.skin_color and current.items == look.items
