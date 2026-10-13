extends Node2D

## The town the player walks around after hosting or joining a lobby. The
## player looks like their saved character, the camera stays inside the town,
## and the HUD shows the lobby code with a button back to the lobby screen.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"
## The playable area in pixels, from (0, 0). The ground, the invisible walls
## in Bounds, and the camera limits all match it.
const TOWN_SIZE := Vector2i(480, 320)

@onready var player: CharacterBody2D = $World/Player
@onready var lobby_label: Label = %LobbyLabel

@onready var copy_button: Button = %CopyButton

@onready var copy_reset_timer: Timer = %CopyResetTimer


func _ready() -> void:
	# The world draws at 320x180 scaled up. canvas_items scaling (rather than
	# the project's default viewport scaling) keeps the HUD text sharp.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	player.character.appearance = PlayerProfile.appearance

	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = TOWN_SIZE.x
	camera.limit_bottom = TOWN_SIZE.y
	
	copy_button.visible = Session.in_lobby()

	if not Session.in_lobby():
		lobby_label.text = "Not in a lobby"
	else:
		lobby_label.text = "Lobby %s%s" % [Session.code, " (host)" if Session.is_host else ""]
		


func _on_leave_button_pressed() -> void:
	Session.leave_lobby()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(Session.code)
	copy_button.text = "Copied!"
	copy_reset_timer.start()

func _on_copy_reset_timer_timeout() -> void:
	copy_button.text = "Copy"
