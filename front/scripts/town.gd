extends Node2D

## The town the player walks around after hosting or joining a lobby: a
## cul-de-sac with one lot per lobby player around a podium. Each player's
## house is built on their lot and the player starts in front of their own.
## The HUD shows the lobby code with a button back to the lobby screen.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"
const HOUSE_SCENE := preload("res://scenes/main/house.tscn")
## Where the player starts relative to their house's ground point: on the
## path just in front of it.
const SPAWN_OFFSET := Vector2(0, 14)
## Where the player starts without a house: the road in.
const ENTRANCE := Vector2(320, 460)

@onready var player: CharacterBody2D = $World/Player
@onready var houses: Node2D = %Houses
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
	camera.limit_right = CulDeSac.SIZE.x
	camera.limit_bottom = CulDeSac.SIZE.y

	_build_houses()
	if Session.me == null:
		player.position = ENTRANCE
	else:
		player.position = CulDeSac.lot_position(Session.me.lot, Session.MAX_PLAYERS) + SPAWN_OFFSET
	
	copy_button.visible = Session.in_lobby()

	if not Session.in_lobby():
		lobby_label.text = "Not in a lobby"
	else:
		lobby_label.text = "Lobby %s%s" % [Session.code, " (host)" if Session.is_host else ""]
		


## Puts a house on every lot: the owner's house where someone lives, and a
## For Sale sign everywhere else.
func _build_houses() -> void:
	for lot in Session.MAX_PLAYERS:
		var house: House = HOUSE_SCENE.instantiate()
		house.name = "Lot%d" % (lot + 1)
		house.position = CulDeSac.lot_position(lot, Session.MAX_PLAYERS)
		var resident := Session.player_on_lot(lot)
		if resident != null:
			house.appearance = resident.house
			house.owner_name = resident.display_name
		houses.add_child(house)


func _on_leave_button_pressed() -> void:
	Session.leave_lobby()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(Session.code)
	copy_button.text = "Copied!"
	copy_reset_timer.start()

func _on_copy_reset_timer_timeout() -> void:
	copy_button.text = "Copy"
