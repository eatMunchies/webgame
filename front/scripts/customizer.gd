extends Wardrobe

## Edits the player's saved character and house. It is the wardrobe screen
## working on copies of PlayerProfile.appearance and PlayerProfile.house,
## with Cancel and Save added to its bottom bar: Save keeps the copies,
## Cancel throws them away, and both go back to the lobby.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"


func _ready() -> void:
	appearance = PlayerProfile.appearance.copy()
	house = PlayerProfile.house.copy()
	# Godot 4 doesn't run the parent's _ready for you once you override it.
	super()


func _footer_buttons() -> Array[Button]:
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_cancel_pressed)
	var save := Button.new()
	save.text = "Save"
	save.theme_type_variation = "PrimaryButton"
	save.pressed.connect(_on_save_pressed)
	return [cancel, save]


func _on_save_pressed() -> void:
	PlayerProfile.appearance = appearance
	PlayerProfile.house = house
	PlayerProfile.save()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
