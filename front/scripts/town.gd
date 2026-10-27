extends Node2D

## The town the player walks around after hosting or joining a lobby: a
## cul-de-sac with one lot per lobby player around a podium. Each player's
## house is built on their lot and the player starts in front of their own.
## The HUD shows the lobby code with a button back to the lobby screen, and
## the game panel (chat, phase, actions) on the right.
##
## Houses are rebuilt whenever the lobby changes: when someone joins or
## leaves, and when someone dies, whose house goes grey. Each house is labeled
## with its owner's number, which is how commands like `/vote 3` name them.
## The town darkens at night.
##
## Everyone else in the lobby walks around here too. This player's position
## goes to the server a few times a second (only when it changes), and each
## other player is a RemotePlayer that follows what the server relays.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"
const HOUSE_SCENE := preload("res://scenes/main/house.tscn")
const GAME_PANEL_SCENE := preload("res://scenes/main/game_panel.tscn")
const REMOTE_PLAYER_SCENE := preload("res://scenes/main/remote_player.tscn")
## How often this player's position is sent while it changes. Others see
## the steps in between smoothed out.
const MOVES_PER_SECOND := 15.0
## Where the player starts relative to their house's ground point: on the
## path just in front of it.
const SPAWN_OFFSET := Vector2(0, 14)
## Where the player starts without a house: the road in, near the bottom edge.
const ENTRANCE := Vector2(CulDeSac.CENTER.x, CulDeSac.SIZE.y - 20)
## Where the podium stands relative to the middle of the plaza.
const PODIUM_OFFSET := Vector2(0, 8)
const DEAD_HOUSE_COLOR := Color(0.55, 0.55, 0.6)
const NIGHT_COLOR := Color(0.42, 0.45, 0.7)
const DAY_FADE_SECONDS := 1.5

@onready var player: CharacterBody2D = $World/Player
@onready var houses: Node2D = %Houses
@onready var world: Node2D = $World
@onready var lobby_label: Label = %LobbyLabel

@onready var copy_button: Button = %CopyButton

@onready var copy_reset_timer: Timer = %CopyResetTimer

var _sky := CanvasModulate.new()
## The other players' characters, by lot.
var _remote_players: Dictionary[int, RemotePlayer] = {}
var _since_move_sent := 0.0


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
	# The walls along the right and bottom edges, and the podium, follow the
	# map's size so resizing the cul-de-sac needs no scene edits.
	$Bounds/Right.position.x = CulDeSac.SIZE.x
	$Bounds/Bottom.position.y = CulDeSac.SIZE.y
	$World/Podium.position = CulDeSac.CENTER + PODIUM_OFFSET

	add_child(_sky)
	_build_houses()
	if Session.me == null:
		player.position = ENTRANCE
	else:
		player.position = CulDeSac.lot_position(Session.me.lot, Session.MAX_PLAYERS) + SPAWN_OFFSET

	copy_button.visible = Session.in_lobby()
	_update_label()
	if Session.in_lobby():
		$HUD.add_child(GAME_PANEL_SCENE.instantiate())
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.phase_changed.connect(_update_sky)
	Session.player_moved.connect(_on_session_player_moved)
	_update_sky()
	_sync_remote_players()
	for moved in Session.client.positions():
		_on_session_player_moved(moved["lot"], moved["position"], moved["facing"], moved["walking"])
	_send_movement()


func _process(delta: float) -> void:
	_since_move_sent += delta
	if _since_move_sent >= 1.0 / MOVES_PER_SECOND:
		_send_movement()


func _send_movement() -> void:
	_since_move_sent = 0.0
	if Session.in_lobby():
		Session.client.send_movement(player.position, player.facing, player.velocity != Vector2.ZERO)


func _update_label() -> void:
	if not Session.in_lobby():
		lobby_label.text = "Not in a lobby"
	else:
		lobby_label.text = "Lobby %s%s" % [Session.code, " (host)" if Session.is_host else ""]


## Puts a house on every lot: the owner's house where someone lives, and a
## For Sale sign everywhere else.
func _build_houses() -> void:
	for child in houses.get_children():
		child.queue_free()
	for lot in Session.MAX_PLAYERS:
		var house: House = HOUSE_SCENE.instantiate()
		house.name = "Lot%d" % (lot + 1)
		house.position = CulDeSac.lot_position(lot, Session.MAX_PLAYERS)
		var resident := Session.player_on_lot(lot)
		if resident != null:
			house.appearance = resident.house
			house.owner_name = "%d %s" % [resident.number, resident.display_name]
			if not resident.alive:
				house.modulate = DEAD_HOUSE_COLOR
		houses.add_child(house)


func _on_session_lobby_changed() -> void:
	# The town lingers for a moment after a scene change; ignore it then.
	if not is_inside_tree():
		return
	if not Session.in_lobby():
		# Dropped by the server; the lobby screen says why.
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
	_build_houses()
	_update_label()
	_sync_remote_players()


## Adds a character for everyone else in the lobby and removes those who
## left. Someone who hasn't moved yet stands in front of their house.
func _sync_remote_players() -> void:
	var present: Array[int] = []
	for resident in Session.players:
		if resident == Session.me:
			continue
		present.append(resident.lot)
		var remote: RemotePlayer = _remote_players.get(resident.lot)
		if remote == null:
			remote = REMOTE_PLAYER_SCENE.instantiate()
			remote.name = "Player%d" % resident.number
			world.add_child(remote)
			_remote_players[resident.lot] = remote
			var home := CulDeSac.lot_position(resident.lot, Session.MAX_PLAYERS) + SPAWN_OFFSET
			remote.move_to(home, Character.Facing.DOWN, false)
		remote.show_player(resident)
	for lot in _remote_players.keys():
		if lot not in present:
			_remote_players[lot].queue_free()
			_remote_players.erase(lot)


func _on_session_player_moved(lot: int, to: Vector2, facing: int, walking: bool) -> void:
	var remote: RemotePlayer = _remote_players.get(lot)
	if remote != null:
		remote.move_to(to, facing as Character.Facing, walking)


func _update_sky() -> void:
	var color := NIGHT_COLOR if Session.client.is_night() else Color.WHITE
	create_tween().tween_property(_sky, "color", color, DAY_FADE_SECONDS)


func _on_leave_button_pressed() -> void:
	Session.leave_lobby()


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(Session.code)
	copy_button.text = "Copied!"
	copy_reset_timer.start()

func _on_copy_reset_timer_timeout() -> void:
	copy_button.text = "Copy"
