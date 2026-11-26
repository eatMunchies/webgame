extends Node2D

## The town the player walks around after hosting or joining a lobby: a
## cul-de-sac with one lot per lobby player around a podium. Each player's
## house is built on their lot and the player starts by their own, in the
## spot they stood by it on the start screen (Session.arrival_spot), facing
## the same way. The start screen's checkerboard floor is laid over the town
## and dissolves from their house outward (_phase_in), so it feels like the
## house stayed put and the town formed around it. If that spot is inside a
## house's walls, the player can walk out through them (see
## _let_out_of_houses).
## The HUD (scenes/main/hud.tscn) lays the players, clock, chat and actions
## out around a part of the screen it leaves for the town (its world_space),
## and the camera keeps the player in the middle of that part, at a zoom
## that keeps the pixel art square (ScreenScale.world_zoom). The town hands
## puts its touch joystick in that part, so dragging anywhere on the town
## walks.
##
## Houses are rebuilt whenever the lobby changes: when someone joins or
## leaves, and when someone dies, whose house goes grey. Each house is labeled
## with its owner's number, which is how commands like `/vote 3` name them.
## At night the town is candlelit: a warm pool of light where it shows
## through the HUD, dark toward the edges (shaders/candle_vignette.gdshader),
## and the parchment turns candlelit with it (Tokens.use_night).
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
## Used when the lobby screen didn't say where they stood.
const SPAWN_OFFSET := Vector2(0, 14)
## Where the player starts without a house: the road in, near the bottom edge.
const ENTRANCE := Vector2(CulDeSac.CENTER.x, CulDeSac.SIZE.y - 20)
## Where the podium stands relative to the middle of the plaza.
const PODIUM_OFFSET := Vector2(0, 8)
const DEAD_HOUSE_COLOR := Color(0.55, 0.55, 0.6)
## How see-through a dead player's own character is, as RemotePlayer draws
## other dead players.
const DEAD_ALPHA := RemotePlayer.DEAD_ALPHA
const CANDLE_SHADER := preload("res://shaders/candle_vignette.gdshader")
## The candle layer sits over the town and under the HUD (layer 2).
const CANDLE_LAYER := 1
const DAY_FADE_SECONDS := 1.5
## How long the start screen's floor takes to dissolve into the town, after
## showing for PHASE_IN_DELAY.
const PHASE_IN_SECONDS := 1.6
const PHASE_IN_DELAY := 0.3
## The z_index of the player and their house while the floor dissolves, so
## they stay above it (the floor is two below, under the house's yard).
const PHASE_Z := 4
## How long another player stays hidden waiting for their first position
## before they're shown in front of their house. A Godot client sends one as
## soon as its town loads; a terminal client never does.
const UNPLACED_WAIT_SECONDS := 1.0
## How long the camera takes to glide from where the start screen had the
## player to the middle of the town's part of the screen.
const ARRIVAL_PAN_SECONDS := 0.9

@onready var player: CharacterBody2D = $World/Player
@onready var houses: Node2D = %Houses
@onready var world: Node2D = $World
@onready var camera: Camera2D = $World/Player/Camera2D
@onready var joystick: Control = $HUD/Joystick
## The player's footprint, what bumps into houses.
@onready var feet: CollisionShape2D = $World/Player/CollisionShape2D

## The camera's place on the player, from the scene: a little above their
## feet, so the player is centered rather than their feet.
@onready var _camera_lift := camera.position
## The HUD, while in a lobby.
var _hud: Control
## The candlelight over the town at night, on its own layer under the HUD.
var _candle_layer := CanvasLayer.new()
var _candle := ColorRect.new()
var _candle_material := ShaderMaterial.new()
var _minigame: MinigameOverlay
## The other players' characters, by lot.
var _remote_players: Dictionary[int, RemotePlayer] = {}
var _since_move_sent := 0.0
## Houses the player is standing in and can walk through until they're clear
## of them. See _let_out_of_houses.
var _passing_through: Array[House] = []
## The start screen's floor while it dissolves into the town, or null.
var _phase_floor: PlazaFloor
## Where the player's house stands while the floor dissolves.
var _phase_home := Vector2.ZERO
## Where on screen the start screen had the player, until the camera's glide
## from there starts. A Vector2, or null.
var _arrival_view_center: Variant = null
## Added to the camera while it glides in from the start screen's framing,
## in world pixels; tweened to zero.
var _arrival_offset := Vector2.ZERO
## The frame the town loaded in.
var _ready_frame := 0


func _ready() -> void:
	_ready_frame = Engine.get_process_frames()
	ScreenScale.for_world(get_window())
	player.character.appearance = PlayerProfile.appearance

	# The walls along the right and bottom edges, and the podium, follow the
	# map's size so resizing the cul-de-sac needs no scene edits.
	$Bounds/Right.position.x = CulDeSac.SIZE.x
	$Bounds/Bottom.position.y = CulDeSac.SIZE.y
	$World/Podium.position = CulDeSac.CENTER + PODIUM_OFFSET

	_add_candle()
	_build_houses()
	if Session.me == null:
		player.position = ENTRANCE
	else:
		var home := CulDeSac.lot_position(Session.me.lot, Session.MAX_PLAYERS)
		if Session.arrival_spot == null:
			player.position = home + SPAWN_OFFSET
		else:
			player.position = home + Session.arrival_spot
			player.facing = Session.arrival_facing
			_phase_in(home)
	Session.arrival_spot = null
	_arrival_view_center = Session.arrival_view_center
	Session.arrival_view_center = null
	_let_out_of_houses()

	if Session.in_lobby():
		_hud = HUD_SCENE.instantiate()
		$HUD.add_child(_hud)
		joystick.reparent(_hud.world_space, false)
		_hud.world_space.move_child(joystick, 0)
		joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_add_minigame_overlay()
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.phase_changed.connect(_update_sky)
	# The dead show again once the game is over.
	Session.phase_changed.connect(_sync_remote_players)
	Session.player_moved.connect(_on_session_player_moved)
	_update_sky()
	_sync_remote_players()
	for moved in Session.client.positions():
		_on_session_player_moved(moved["lot"], moved["position"], moved["facing"], moved["walking"])
	_send_movement()


func _add_minigame_overlay() -> void:
	_minigame = MINIGAME_SCENE.instantiate()
	# The HUD's minigame space: all of the town's part of the screen, or on a
	# tall screen its bottom half, under the chat.
	_hud.minigame_space.add_child(_minigame)
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
	_aim_candle()
	_frame_camera()
	if _phase_floor != null:
		_phase_floor.focus = player.position + PlazaFloor.FOCUS_LIFT
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
	_start_arrival_pan(area, zoom)
	camera.position = _camera_lift + shift + _arrival_offset
	camera.limit_left = floori(-area.position.x / zoom)
	camera.limit_top = floori(-area.position.y / zoom)
	camera.limit_right = ceili(CulDeSac.SIZE.x + (view.x - area.end.x) / zoom)
	camera.limit_bottom = ceili(CulDeSac.SIZE.y + (view.y - area.end.y) / zoom)


## Starts the camera where the start screen had the player, and glides it
## to the middle of the town's part of the screen, so joining doesn't jump.
## Waits for the HUD's first layout, so the part is where it will stay.
func _start_arrival_pan(area: Rect2, zoom: float) -> void:
	if _arrival_view_center == null or (_hud != null and Engine.get_process_frames() == _ready_frame):
		return
	_arrival_offset = (area.get_center() - (_arrival_view_center as Vector2)) / zoom
	_arrival_view_center = null
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
			.tween_property(self, "_arrival_offset", Vector2.ZERO, ARRIVAL_PAN_SECONDS)


func _physics_process(_delta: float) -> void:
	# Houses block the player again once they're out of them.
	for house in _passing_through.duplicate():
		if not is_instance_valid(house) or not _overlaps(house):
			if is_instance_valid(house):
				player.remove_collision_exception_with(house)
			_passing_through.erase(house)


## Lays the start screen's floor over the town and dissolves it from the
## house at `home` outward, so the town forms around the player. They and
## their house stay above it; everything else, other players included,
## appears as the floor goes.
func _phase_in(home: Vector2) -> void:
	_phase_home = home
	_phase_floor = PlazaFloor.new()
	_phase_floor.z_index = PHASE_Z - 2
	_phase_floor.reveal_origin = home
	_phase_floor.focus = player.position + PlazaFloor.FOCUS_LIFT
	add_child(_phase_floor)
	_phase_floor.cover_view()
	player.z_index = PHASE_Z
	_lift_own_house()
	var tween := create_tween()
	tween.tween_interval(PHASE_IN_DELAY)
	tween.tween_property(_phase_floor, "reveal", 1.01, PHASE_IN_SECONDS)
	tween.tween_callback(_end_phase_in)


func _end_phase_in() -> void:
	_phase_floor.queue_free()
	_phase_floor = null
	player.z_index = 0
	for house in houses.get_children():
		house.z_index = 0


## Keeps the player's house above the dissolving floor. Run again whenever
## the houses are rebuilt.
func _lift_own_house() -> void:
	if _phase_floor == null:
		return
	for house: House in houses.get_children():
		if not house.is_queued_for_deletion() and house.position == _phase_home:
			house.z_index = PHASE_Z


## Lets the player walk through any house they're standing in, so they don't
## get stuck. That happens when they arrive in a spot by their house that's
## inside walls here, or when a house appears where they stand (someone joins
## and takes that lot). Each house blocks them again once they're out of it.
func _let_out_of_houses() -> void:
	for house: House in houses.get_children():
		if house.is_queued_for_deletion() or house.appearance == null:
			continue
		if house not in _passing_through and _overlaps(house):
			player.add_collision_exception_with(house)
			_passing_through.append(house)


## Whether the player's feet overlap a house's walls.
func _overlaps(house: House) -> bool:
	return feet.shape.collide(feet.global_transform,
			house.walls.shape, house.walls.global_transform)


func _send_movement() -> void:
	_since_move_sent = 0.0
	if Session.in_lobby():
		Session.client.send_movement(player.position, player.facing, player.velocity != Vector2.ZERO)



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
	_lift_own_house()
	_let_out_of_houses()
	_sync_remote_players()


## Adds a character for everyone else in the lobby and removes those who
## left. Each stays hidden until their first position arrives, so nobody
## shows somewhere they aren't; anyone who sends none (a terminal player)
## shows in front of their house after UNPLACED_WAIT_SECONDS.
##
## The dead are ghosts: see-through, and while a game runs only the dead see
## them, the player's own character included.
func _sync_remote_players() -> void:
	var me_dead := Session.me != null and not Session.me.alive
	var sees_dead := me_dead or not Session.in_game()
	player.modulate.a = DEAD_ALPHA if me_dead else 1.0
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
			get_tree().create_timer(UNPLACED_WAIT_SECONDS).timeout.connect(func() -> void:
				if is_instance_valid(remote) and not remote.placed:
					remote.move_to(home, Character.Facing.DOWN, false))
		remote.show_player(resident, sees_dead)
	for lot in _remote_players.keys():
		if lot not in present:
			_remote_players[lot].queue_free()
			_remote_players.erase(lot)


func _on_session_player_moved(lot: int, to: Vector2, facing: int, walking: bool) -> void:
	var remote: RemotePlayer = _remote_players.get(lot)
	if remote != null:
		remote.move_to(to, facing as Character.Facing, walking)


func _add_candle() -> void:
	_candle_layer.layer = CANDLE_LAYER
	add_child(_candle_layer)
	_candle_material.shader = CANDLE_SHADER
	_candle_material.set_shader_parameter("night", Vector4.ZERO)
	_candle_material.set_shader_parameter("glow", Tokens.NIGHT_CANDLE)
	_candle_material.set_shader_parameter("dark", Tokens.NIGHT_DARK)
	_candle.material = _candle_material
	_candle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_candle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_candle_layer.add_child(_candle)


## Centers the candle's light on the part of the screen the town shows
## through, reaching to its edges.
func _aim_candle() -> void:
	var screen := _candle.size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var area := Rect2(Vector2.ZERO, screen)
	if _hud != null:
		area = _hud.world_space.get_global_rect()
	var center := area.get_center() / screen
	var reach := area.size / screen * 0.8
	_candle_material.set_shader_parameter("pool", Vector4(center.x, center.y, reach.x, reach.y))


func _update_sky() -> void:
	var night: bool = Session.client.is_night()
	Tokens.use_night(night)
	var from: float = (_candle_material.get_shader_parameter("night") as Vector4).x
	create_tween().tween_method(func(value: float) -> void:
		_candle_material.set_shader_parameter("night", Vector4(value, 0, 0, 0)), from, 1.0 if night else 0.0,
		DAY_FADE_SECONDS)


func _exit_tree() -> void:
	# The parchment of the screens after the town is daylit.
	Tokens.use_night(false)

