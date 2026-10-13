extends Wardrobe

## Edits the player's saved character. It is the wardrobe screen working on a
## copy of PlayerProfile.appearance: Save keeps the copy, Cancel throws it
## away, and both go back to the lobby.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"


func _ready() -> void:
	appearance = PlayerProfile.appearance.copy()
	# Godot 4 doesn't run the parent's _ready for you once you override it.
	super()


func _on_save_pressed() -> void:
	PlayerProfile.appearance = appearance
	PlayerProfile.save()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
