extends Node2D

## The town the player walks around after hosting or joining a lobby: a
## cul-de-sac with one lot per lobby player around a podium. Each player's
## house is built on their lot and the player starts in front of their own.
## The HUD (scenes/main/hud.tscn) lays the players, clock, chat and actions
## out around a part of the screen it leaves for the town (its world_space),
## and the camera keeps the player in the middle of that part, at a zoom
## that keeps the pixel art square (ScreenScale.world_zoom). The town hands
## the HUD its lobby bar (code, Copy, Leave) and puts its touch joystick in
## that part, so dragging anywhere on the town walks.
##
## Houses are rebuilt whenever the lobby changes: when someone joins or
## leaves, and when someone dies, whose house goes grey. Each house is labeled
## with its owner's number, which is how commands like `/vote 3` name them.
## The town darkens at night.
##
## Everyone else in the lobby walks around here too. This player's position
## goes to the server a few times a second (only when it changes), and each
## other player is a RemotePlayer that follows what the server relays.
##
## At night the MinigameOverlay covers the town's part of the screen while
## the player has a minigame, and its moves go to the server.

const LOBBY_SCENE := "res://scenes/main/lobby.tscn"
const HOUSE_SCENE := preload("res://scenes/main/house.tscn")
const HUD_SCENE := preload("res://scenes/main/hud.tscn")
const REMOTE_PLAYER_SCENE := preload("res://scenes/main/remote_player.tscn")
const MINIGAME_SCENE := preload("res://scenes/main/minigame_overlay.tscn")
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
@onready var bar: Control = $HUD/Bar

@onready var copy_button: Button = %CopyButton

@onready var copy_reset_timer: Timer = %CopyResetTimer
@onready var camera: Camera2D = $World/Player/Camera2D
@onready var joystick: Control = $HUD/Joystick

## The camera's place on the player, from the scene: a little above their
## feet, so the player is centered rather than their feet.
@onready var _camera_lift := camera.position
## The HUD, while in a lobby.
var _hud: Control
var _sky := CanvasModulate.new()
var _minigame: MinigameOverlay
## The other players' characters, by lot.
var _remote_players: Dictionary[int, RemotePlayer] = {}
var _since_move_sent := 0.0


func _ready() -> void:
	ScreenScale.for_world(get_window())
	player.character.appearance = PlayerProfile.appearance

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
	# The lobby bar sits above the chat, so it shares the HUD's small look.
	bar.theme = HudStyle.build()
	_update_label()
	if Session.in_lobby():
		_hud = HUD_SCENE.instantiate()
		$HUD.add_child(_hud)
		_hud.add_lobby_bar(bar)
		joystick.reparent(_hud.world_space, false)
		_hud.world_space.move_child(joystick, 0)
		joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_add_minigame_overlay()
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.phase_changed.connect(_update_sky)
	Session.player_moved.connect(_on_session_player_moved)
	_update_sky()
	_sync_remote_players()
	for moved in Session.client.positions():
		_on_session_player_moved(moved["lot"], moved["position"], moved["facing"], moved["walking"])
	_send_movement()


func _add_minigame_overlay() -> void:
	_minigame = MINIGAME_SCENE.instantiate()
	_hud.world_space.add_child(_minigame)
	_minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_minigame.fight_source = Session.client.fight
	_minigame.check_reported.connect(Session.client.report_check)
	_minigame.fight_move.connect(Session.client.fight_move)
	_minigame.guard_changed.connect(Session.client.fight_guard)
	Session.minigame_changed.connect(_on_session_minigame_changed)
	_on_session_minigame_changed()


func _on_session_minigame_changed() -> void:
	_minigame.show_minigame(Session.client.minigame())


func _process(delta: float) -> void:
	_frame_camera()
	_since_move_sent += delta
	if _since_move_sent >= 1.0 / MOVES_PER_SECOND:
		_send_movement()


## Keeps the player in the middle of the town's part of the screen, and the
## map's edges at that part's edges, so nothing of the town hides under the
## HUD unless the player walks to the map's edge. Run every frame, since the
## part moves when the chat opens or the window turns.
func _frame_camera() -> void:
	var zoom := ScreenScale.world_zoom(get_viewport())
	camera.zoom = Vector2(zoom, zoom)
	var view := get_viewport().get_visible_rect().size
	var area := Rect2(Vector2.ZERO, view)
	if _hud != null:
		area = _hud.world_space.get_global_rect()
	# Seen through the camera, the middle of the screen is this far, in
	# world pixels, from the middle of the town's part.
	var shift := (view / 2.0 - area.get_center()) / zoom
	camera.position = _camera_lift + shift
	camera.limit_left = floori(-area.position.x / zoom)
	camera.limit_top = floori(-area.position.y / zoom)
	camera.limit_right = ceili(CulDeSac.SIZE.x + (view.x - area.end.x) / zoom)
	camera.limit_bottom = ceili(CulDeSac.SIZE.y + (view.y - area.end.y) / zoom)


func _send_movement() -> void:
	_since_move_sent = 0.0
	if Session.in_lobby():
		Session.client.send_movement(player.position, player.facing, player.velocity != Vector2.ZERO)


func _update_label() -> void:
	if not Session.in_lobby():
		lobby_label.text = "Not in a lobby"
	else:
		# The player list marks the host, so the narrow bar only needs the code.
		lobby_label.text = "Lobby %s" % Session.code


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
