extends Node2D

## The start screen: a plaza where the player walks around their own house
## on an endless checkerboard floor (PlazaFloor) that fades into haze, with
## a panel to pick a name, host a new lobby or type a lobby code to join one.
## Minigames opens the minigame tester, to try every minigame without a game.
## Hosting or joining asks the game server, and goes to the town once it
## says yes.
##
## Clicking or tapping the house opens the customizer (so does E, the
## interact action, at its door); a hint says so while the player is near. The house brightens
## while the player is at its door. Walking is the
## town's: WASD or the arrow keys, or dragging on a touch screen. Clicking
## the plaza takes the focus off the text boxes, so the keys walk again.
##
## The panel sits beside the plaza on a wide screen and under it on a tall
## one (an AspectFlowContainer, like the town's HUD), and the camera keeps
## the player in the middle of the part the panel leaves, at the town's
## pixel-perfect zoom. An invisible ring keeps them near their house.
##
## The buttons' signals are connected in lobby.tscn (select a button and look
## at Node > Signals in the editor), and the nodes this script uses are marked
## as unique names, so they're reached with %Name wherever they sit.

const CUSTOMIZER_SCENE := "res://scenes/main/customizer.tscn"
const TOWN_SCENE := "res://scenes/main/town.tscn"
const MINIGAME_TESTER_SCENE := "res://scenes/main/minigame_tester.tscn"
## Where the player stands in front of the door, from the house's ground
## point. They start here, and E opens the wardrobe within DOOR_REACH of it.
const DOOR_SPOT := Vector2(0, 12)
const DOOR_REACH := 16.0
## How far from the house the player can walk, in world pixels.
const EDGE_RADIUS := 140.0
const EDGE_SIDES := 48
## The part of the house a tap or click opens the wardrobe from, from its
## ground point: the facade and roof, not the yard.
const HOUSE_RECT := Rect2(-32, -72, 64, 72)
## The house's tint while the player is at its door.
const DOOR_GLOW := Color(1.2, 1.2, 1.12)
## The hint over the house saying how to go in: a click on it, or on a touch
## screen a tap. It shows, pulsing gently, while the player is within
## HINT_REACH of the door.
const CLICK_HINT := "Click to Customize"
const TAP_HINT := "Tap to Customize"
const HINT_REACH := 48.0
## How far above the owner's name the hint sits, in world pixels.
const HINT_GAP := 2.0
const HINT_PULSE_SPEED := 4.0

@onready var name_input: LineEdit = %NameInput
@onready var create_button: Button = %CreateButton
@onready var code_input: LineEdit = %CodeInput
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var house: House = %House
@onready var player: CharacterBody2D = %Player
@onready var camera: Camera2D = $World/Player/Camera2D
@onready var floor_rect: PlazaFloor = $Floor
@onready var world_space: Control = %WorldSpace
@onready var panel: Control = %Panel

## The camera's place on the player, from the scene.
@onready var _camera_lift := camera.position
## True while waiting for the server to answer a create or join.
var _waiting := false
var _prompt: TextPrompt
## The hint over the house; see KEY_HINT.
var _hint := Label.new()
var _touch := DisplayServer.is_touchscreen_available()


func _ready() -> void:
	ScreenScale.for_world(get_window())
	# The panel's flow was picked when it entered the tree, before the
	# scaling above changed the screen's shape in units.
	$UI/Shell.refresh()
	$UI/Shell.theme = HudStyle.build()
	house.appearance = _shown_house()
	player.character.appearance = PlayerProfile.appearance
	player.position = house.position + DOOR_SPOT
	_build_edge()
	name_input.text = PlayerProfile.username
	house.owner_name = PlayerProfile.username
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.request_failed.connect(_on_session_request_failed)
	_update_buttons()
	_add_hint()
	# The name and code boxes type in a box in the middle of the screen,
	# clear of a phone's keyboard. The code's has Paste, for a code sent in a
	# message.
	_prompt = TextPrompt.create($UI)
	_prompt.attach(name_input, "Your name", false, {"always": true})
	_prompt.attach(code_input, "Lobby code", true, {"always": true, "paste": true, "confirm": "Join"})
	# Say why the player is back here, if they were dropped from a lobby.
	status_label.text = Session.last_error
	Session.last_error = ""
	_follow_launch_options()


func _process(_delta: float) -> void:
	_frame_camera()
	floor_rect.focus = player.position + PlazaFloor.FOCUS_LIFT
	house.modulate = DOOR_GLOW if near_door() else Color.WHITE
	_update_hint()


func _add_hint() -> void:
	_hint.text = TAP_HINT if _touch else CLICK_HINT
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.z_index = 2
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 2)
	house.get_parent().add_child(_hint)


## Shows the hint over the owner's name, pulsing gently, while the player is
## near the house.
func _update_hint() -> void:
	_hint.visible = player.position.distance_to(house.position + DOOR_SPOT) <= HINT_REACH
	if not _hint.visible:
		return
	_hint.reset_size()
	var name_label: Control = house.get_node("NameLabel")
	var top := house.position.y + name_label.position.y
	_hint.position = Vector2(house.position.x - _hint.size.x / 2.0, top - _hint.size.y - HINT_GAP)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * HINT_PULSE_SPEED)
	_hint.modulate.a = lerpf(0.55, 1.0, pulse)


## Keeps the player in the middle of the part of the screen the panel leaves.
func _frame_camera() -> void:
	var zoom := ScreenScale.world_zoom(get_viewport())
	camera.zoom = Vector2(zoom, zoom)
	var view := get_viewport().get_visible_rect().size
	var area := world_space.get_global_rect()
	camera.position = _camera_lift + (view / 2.0 - area.get_center()) / zoom


## Whether the player is close enough to the door to go in.
func near_door() -> bool:
	return player.position.distance_to(house.position + DOOR_SPOT) <= DOOR_REACH


## Whether a point in the world is on the house, where a tap opens the
## wardrobe.
func on_house(point: Vector2) -> bool:
	return Rect2(house.position + HOUSE_RECT.position, HOUSE_RECT.size).has_point(point)


func _input(event: InputEvent) -> void:
	# A tap or click on the house goes in. This runs before the joystick,
	# which would otherwise take the touch.
	var tap := event as InputEventMouseButton
	if tap == null or not tap.pressed or tap.button_index != MOUSE_BUTTON_LEFT:
		return
	if _prompt != null and _prompt.visible:
		return
	if panel.get_global_rect().has_point(tap.position):
		return
	# Clicking the plaza leaves the text boxes, so the keys walk again.
	get_viewport().gui_release_focus()
	if on_house(get_global_mouse_position()):
		get_viewport().set_input_as_handled()
		_open_wardrobe()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and near_door():
		get_viewport().set_input_as_handled()
		_open_wardrobe()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().gui_release_focus()


## A ring of walls around the house, so the player can't wander off into the
## haze and lose it.
func _build_edge() -> void:
	var ring := PackedVector2Array()
	for i in EDGE_SIDES:
		var from := Vector2.from_angle(TAU * i / EDGE_SIDES) * EDGE_RADIUS
		var to := Vector2.from_angle(TAU * (i + 1) / EDGE_SIDES) * EDGE_RADIUS
		ring.append_array([house.position + from, house.position + to])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = ring
	var collision := CollisionShape2D.new()
	collision.shape = shape
	%Edge.add_child(collision)


## Hosts or joins straight away when the game was started with `--create`
## or `--join=CODE` (after `--`), once per run.
func _follow_launch_options() -> void:
	if Session.launch_request_done or name_input.text.strip_edges() == "":
		return
	Session.launch_request_done = true
	var code := LaunchOptions.value("join")
	if LaunchOptions.value("create") != "":
		_on_create_button_pressed()
	elif code != "":
		code_input.text = Session.normalize_code(code)
		_on_join_button_pressed()


## The player's house with any unpicked layers filled in, so it can be drawn.
## An unpicked layer means a random style in each lobby, so the fill goes on
## a copy and the profile keeps it unpicked.
func _shown_house() -> HouseAppearance:
	var shown := PlayerProfile.house.copy()
	var suggestion := HouseAppearance.random(randi())
	for layer in HouseCatalog.LAYERS:
		if shown.style_for(layer) == "":
			shown.set(layer, suggestion.style_for(layer))
	return shown


func _update_buttons() -> void:
	var named := name_input.text.strip_edges() != ""
	create_button.disabled = _waiting or not named
	join_button.disabled = _waiting or not named \
			or Session.normalize_code(code_input.text).length() != Session.CODE_LENGTH


## Remembers the name, then shows that a request is on its way.
func _begin_request() -> void:
	PlayerProfile.username = name_input.text.strip_edges()
	PlayerProfile.save()
	_waiting = true
	status_label.text = "Connecting..."
	_update_buttons()


func _open_wardrobe() -> void:
	if _waiting:
		return
	get_tree().change_scene_to_file(CUSTOMIZER_SCENE)


func _on_minigames_button_pressed() -> void:
	get_tree().change_scene_to_file(MINIGAME_TESTER_SCENE)


func _on_create_button_pressed() -> void:
	_begin_request()
	Session.create_lobby()


func _on_join_button_pressed() -> void:
	_begin_request()
	var error := Session.join_lobby(code_input.text)
	if error != "":
		_on_session_request_failed(error)


## Where the player stands, from their house's ground point.
func arrival_spot() -> Vector2:
	return player.position - house.position


## The server put the player in a lobby: go to the town, where they appear
## in the same spot by their house, facing the same way, and the plaza's
## floor dissolves into the town around them.
func _on_session_lobby_changed() -> void:
	# This screen lingers for a moment after the change to the town, out of
	# the tree; a second lobby update then must not change scenes again.
	if not is_inside_tree():
		return
	if _waiting and Session.in_lobby():
		Session.arrival_spot = arrival_spot()
		Session.arrival_facing = player.facing
		Session.arrival_view_center = world_space.get_global_rect().get_center()
		get_tree().change_scene_to_file(TOWN_SCENE)


func _on_session_request_failed(message: String) -> void:
	if not _waiting:
		return
	_waiting = false
	status_label.text = message
	_update_buttons()


func _on_name_input_text_changed(new_text: String) -> void:
	status_label.text = ""
	house.owner_name = new_text.strip_edges()
	_update_buttons()


## Keeps the code uppercase as the player types, and only enables Join once
## the code is long enough.
func _on_code_input_text_changed(new_text: String) -> void:
	var clean := Session.normalize_code(new_text)
	if clean != new_text:
		var caret := code_input.caret_column
		code_input.text = clean
		code_input.caret_column = mini(caret, clean.length())
	status_label.text = ""
	_update_buttons()


## Pressing Enter in the code box joins, the same as clicking Join.
func _on_code_input_text_submitted(_text: String) -> void:
	if not join_button.disabled:
		_on_join_button_pressed()
