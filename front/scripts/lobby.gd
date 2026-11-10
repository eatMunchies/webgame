extends Control

## The start screen. The player picks a name, can open the customizer, and
## can host a new lobby or type a lobby code to join one. Minigames opens the
## minigame tester, to try every minigame without a game. Hosting or joining
## asks the game server, and goes to the town once it says yes.
##
## It shares the customizer's look: RpgTheme's wood and gold, the same
## backdrop, and the same preview (Wardrobe.Stage), showing the player's
## house with their character in the yard.
##
## The buttons' signals are connected in lobby.tscn (select a button and look
## at Node > Signals in the editor), and the nodes this script uses are marked
## as unique names, so they're reached with %Name wherever they sit.

const CUSTOMIZER_SCENE := "res://scenes/main/customizer.tscn"
const TOWN_SCENE := "res://scenes/main/town.tscn"
const MINIGAME_TESTER_SCENE := "res://scenes/main/minigame_tester.tscn"
const HOUSE_SCENE := preload("res://scenes/main/house.tscn")

@onready var name_input: LineEdit = %NameInput
@onready var create_button: Button = %CreateButton
@onready var code_input: LineEdit = %CodeInput
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var preview_area: Control = %PreviewArea
@onready var preview: Character = %Preview

## True while waiting for the server to answer a create or join.
var _waiting := false


func _ready() -> void:
	ScreenScale.for_menus(get_window())
	theme = RpgTheme.build()
	add_child(RpgTheme.backdrop())
	move_child(get_child(-1), 0)
	_build_stage()
	preview.appearance = PlayerProfile.appearance
	name_input.text = PlayerProfile.username
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.request_failed.connect(_on_session_request_failed)
	_update_buttons()
	# Say why the player is back here, if they were dropped from a lobby.
	status_label.text = Session.last_error
	Session.last_error = ""
	_follow_launch_options()


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


## Shows the player's house with their character in its yard, the same way
## the customizer's House tab does. The stage sizes and places both to fit
## the preview area.
func _build_stage() -> void:
	var stage := Wardrobe.Stage.new()
	stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stage.texture_filter = TEXTURE_FILTER_NEAREST
	preview_area.add_child(stage)
	var house: House = HOUSE_SCENE.instantiate()
	house.appearance = _shown_house()
	# The yard sits at z_index -1, so lift the house and character above the
	# panel behind them.
	house.z_index = 1
	stage.add_child(house)
	stage.house = house
	preview.reparent(stage, false)
	preview.z_index = 1
	stage.character = preview
	stage.show_house = true


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


func _on_customize_button_pressed() -> void:
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


## The server put the player in a lobby: go to the town.
func _on_session_lobby_changed() -> void:
	if _waiting and Session.in_lobby():
		get_tree().change_scene_to_file(TOWN_SCENE)


func _on_session_request_failed(message: String) -> void:
	if not _waiting:
		return
	_waiting = false
	status_label.text = message
	_update_buttons()


func _on_name_input_text_changed(_new_text: String) -> void:
	status_label.text = ""
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
