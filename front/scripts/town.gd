extends Node2D

## The town the player walks around after hosting or joining a lobby: a
## cul-de-sac with one lot per lobby player around a guillotine. Each player's
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
##
## Mornings and executions are ceremonies (Funerals): nobody walks, the
## phone's chat sheet steps aside, and the camera visits each body while
## the herald tells what happened. A dead player's body (a Corpse) lies in
## front of their house for the rest of the game, for everyone to see,
## while their ghost walks on unseen by the living. Whoever is on trial is
## walked to the front of the guillotine and held there until they're
## spared, or until the blade falls.

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
## Where the guillotine stands relative to the middle of the plaza.
const GUILLOTINE_OFFSET := Vector2(0, 8)
## How long the accused takes to be walked to the guillotine.
const TO_TRIAL_SECONDS := 1.2
## At an execution the head comes off as the blade lands and rolls to the
## ground in front (HEAD_ROLL, from the feet, in the character's pixels),
## then the body falls, and a moment later both fade.
const BLADE_LANDS_SECONDS := 0.2
const HEAD_ROLL := Vector2(13, 6)
const HEAD_ROLL_SECONDS := 0.6
const HEAD_HOP := 10.0
const FALL_SECONDS := 0.35
const FADE_AFTER_SECONDS := 1.0
const FADE_SECONDS := 0.8
## The day stages when someone stands at the guillotine.
const TRIAL_KINDS: Array[String] = ["defense", "judgement", "last_words", "execution"]
const CEREMONY_KINDS: Array[String] = ["morning", "execution"]
## At a ceremony the camera looks this far above a body or the guillotine,
## so it shows under the herald's banner at the top of the town.
const CEREMONY_VIEW_LIFT := Vector2(0, -30)
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
@onready var guillotine: Guillotine = $World/Guillotine

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
## What the camera looks at instead of the player during a ceremony, and how
## far it has gone there (0 the player, 1 the point).
var _focus_point := Vector2.ZERO
var _focus_weight := 0.0
var _focus_tween: Tween
## The dead's bodies, by lot.
var _corpses: Dictionary[int, Corpse] = {}
## Lots whose bodies wait for their funeral before showing.
var _unburied: Array[int] = []
## The lot of the player being executed, kept in view (not yet a ghost)
## until the blade falls, or -1.
var _condemned := -1
## Executed players, whose bodies lie with their heads beside them.
var _beheaded: Array[int] = []
## Whether this player is held at the guillotine.
var _on_trial := false
var _funerals: Funerals


func _ready() -> void:
	_ready_frame = Engine.get_process_frames()
	ScreenScale.for_world(get_window())
	player.character.appearance = PlayerProfile.appearance

	# The walls along the right and bottom edges, and the guillotine, follow
	# the map's size so resizing the cul-de-sac needs no scene edits.
	$Bounds/Right.position.x = CulDeSac.SIZE.x
	$Bounds/Bottom.position.y = CulDeSac.SIZE.y
	guillotine.position = CulDeSac.CENTER + GUILLOTINE_OFFSET

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
		_funerals = Funerals.new(self, _hud.herald)
		add_child(_funerals)
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.deaths_announced.connect(_on_session_deaths_announced)
	Session.phase_changed.connect(_update_trial)
	Session.phase_changed.connect(_update_sky)
	# The dead show again once the game is over.
	Session.phase_changed.connect(_sync_remote_players)
	Session.player_moved.connect(_on_session_player_moved)
	_update_sky()
	_sync_remote_players()
	_sync_corpses()
	_update_trial()
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
	var aim := _camera_lift.lerp(_focus_point + _camera_lift - player.position, _focus_weight)
	camera.position = aim + shift + _arrival_offset
	# At a ceremony the camera may look past the map's edge, into the grass
	# around it, to show a house near the edge under the herald.
	var slack := roundi(CulDeSac.OUTSKIRTS / 2.0 * _focus_weight)
	camera.limit_left = floori(-area.position.x / zoom) - slack
	camera.limit_top = floori(-area.position.y / zoom) - slack
	camera.limit_right = ceili(CulDeSac.SIZE.x + (view.x - area.end.x) / zoom) + slack
	camera.limit_bottom = ceili(CulDeSac.SIZE.y + (view.y - area.end.y) / zoom) + slack


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
	_sync_corpses()


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
	var me_condemned := Session.me != null and Session.me.lot == _condemned
	player.modulate.a = DEAD_ALPHA if me_dead and not me_condemned else 1.0
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
		# The condemned stays in view until the blade falls.
		remote.show_player(resident, sees_dead or resident.lot == _condemned)
		if resident.lot == _condemned:
			remote.modulate.a = 1.0
	for lot in _remote_players.keys():
		if lot not in present:
			_remote_players[lot].queue_free()
			_remote_players.erase(lot)


## Lays a body in front of the house of everyone dead, and takes them away
## when there's no game (a new one starts with everyone alive).
func _sync_corpses() -> void:
	var dead: Array[int] = []
	if Session.in_game() or Session.client.phase_info()["title"] == "Game over":
		for resident in Session.players:
			if not resident.alive:
				dead.append(resident.lot)
	if dead.is_empty():
		_beheaded.clear()
	for lot in _corpses.keys():
		if lot not in dead:
			_corpses[lot].queue_free()
			_corpses.erase(lot)
	for resident in Session.players:
		if resident.lot not in dead:
			continue
		var corpse: Corpse = _corpses.get(resident.lot)
		if corpse == null:
			corpse = Corpse.new()
			corpse.name = "Body%d" % resident.number
			corpse.position = body_spot(resident.lot)
			world.add_child(corpse)
			_corpses[resident.lot] = corpse
		corpse.show_look(resident.appearance, resident.lot in _beheaded)
		corpse.visible = resident.lot not in _unburied


## Where a player's body lies: on the road in front of their house.
func body_spot(lot: int) -> Vector2:
	return CulDeSac.road_spot(lot, Session.MAX_PLAYERS)


## Where the accused stands, in front of the guillotine.
func guillotine_spot() -> Vector2:
	return guillotine.position + Guillotine.ACCUSED_SPOT


## Where the camera looks for a funeral, and for an execution.
func funeral_view(lot: int) -> Vector2:
	return body_spot(lot) + CEREMONY_VIEW_LIFT


func execution_view() -> Vector2:
	return guillotine_spot() + CEREMONY_VIEW_LIFT


## Keeps these bodies hidden until their funerals (reveal_body).
func hide_bodies(lots: Array) -> void:
	for lot: int in lots:
		if lot not in _unburied:
			_unburied.append(lot)
	_sync_corpses()


func reveal_body(lot: int) -> void:
	_unburied.erase(lot)
	_sync_corpses()


func reveal_all_bodies() -> void:
	_unburied.clear()
	_condemned = -1
	_sync_corpses()
	_sync_remote_players()


## Glides the camera to `point` in the world, from the player or from where
## it was looking.
func look_at_spot(point: Vector2, seconds: float) -> void:
	if _focus_tween != null:
		_focus_tween.kill()
	if _focus_weight <= 0.0:
		_focus_point = point
	_focus_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(self, "_focus_point", point, seconds)
	_focus_tween.tween_property(self, "_focus_weight", 1.0, seconds)


## Glides the camera back to the player.
func look_back(seconds: float) -> void:
	if _focus_tween != null:
		_focus_tween.kill()
	_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(self, "_focus_weight", 0.0, seconds)


## The blade falls on the condemned on `lot`: their head comes off and
## rolls to the ground, their body falls, both fade, and from then on they
## are a ghost like any other dead player.
func execute(lot: int) -> void:
	guillotine.drop()
	var character: Character = player.character
	if Session.me == null or Session.me.lot != lot:
		var remote: RemotePlayer = _remote_players.get(lot)
		if remote == null:
			return
		character = remote.character
	await get_tree().create_timer(BLADE_LANDS_SECONDS).timeout
	if not is_instance_valid(character):
		return
	# The head goes beside the character, not in it, so the body can fall
	# without taking it along.
	var head := character.behead()
	head.scale = character.scale
	head.position = character.position + head.position * character.scale
	character.get_parent().add_child(head)
	var start := head.position
	var land := character.position + HEAD_ROLL * character.scale
	var roll := create_tween().set_parallel()
	roll.tween_method(func(t: float) -> void:
		head.position = start.lerp(land, t) + Vector2(0, -HEAD_HOP * sin(t * PI) * (1.0 - t)),
		0.0, 1.0, HEAD_ROLL_SECONDS)
	roll.tween_property(head, "rotation", TAU, HEAD_ROLL_SECONDS)
	var tween := create_tween()
	tween.tween_property(character, "rotation", PI / 2, FALL_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(FADE_AFTER_SECONDS)
	tween.tween_property(character, "modulate:a", 0.0, FADE_SECONDS)
	tween.parallel().tween_property(head, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		head.queue_free()
		character.mend()
		character.rotation = 0.0
		character.modulate.a = 1.0
		_condemned = -1
		_sync_remote_players())


func _on_session_deaths_announced(deaths: Array) -> void:
	for death: Dictionary in deaths:
		if death["executed"]:
			_condemned = death["lot"]
			if death["lot"] not in _beheaded:
				_beheaded.append(death["lot"])
	_sync_remote_players()


## Holds whoever is on trial at the guillotine, and everyone still through a
## ceremony. The accused's own client walks them there; others pin them in
## place too, in case their client doesn't (a terminal player).
func _update_trial() -> void:
	var info: Dictionary = Session.client.phase_info()
	var kind: String = info["kind"]
	var accused: int = info["accused"] if kind in TRIAL_KINDS else -1
	var spot := guillotine_spot()
	for lot in _remote_players:
		var remote: RemotePlayer = _remote_players[lot]
		if lot == accused:
			if remote.pinned == null:
				remote.pinned = spot
				remote.move_to(spot, Character.Facing.DOWN, false)
		elif remote.pinned != null:
			remote.pinned = null
	var me_accused := Session.me != null and Session.me.lot == accused
	if me_accused and not _on_trial:
		player.facing = Character.Facing.DOWN
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
				.tween_property(player, "position", spot, TO_TRIAL_SECONDS)
	_on_trial = me_accused
	var ceremony := kind in CEREMONY_KINDS
	player.frozen = _on_trial or ceremony
	if _hud != null:
		_hud.set_ceremony(ceremony)
	if not ceremony and guillotine.fall > 0.0:
		guillotine.raise()


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

