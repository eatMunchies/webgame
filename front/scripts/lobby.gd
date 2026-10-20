extends Control

## The start screen. The player picks a name, can open the customizer, and
## can host a new lobby or type a lobby code to join one. Hosting or joining
## asks the game server, and goes to the town once it says yes.
##
## The buttons' signals are connected in lobby.tscn (select a button and look
## at Node > Signals in the editor), and the nodes this script uses are marked
## as unique names, so they're reached with %Name wherever they sit.

const CUSTOMIZER_SCENE := "res://scenes/main/customizer.tscn"
const TOWN_SCENE := "res://scenes/main/town.tscn"
const PREVIEW_SCALE := 4.0

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
	# The project renders at 320x180 for pixel art; menus turn that off so
	# text and buttons draw at full resolution.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	preview.appearance = PlayerProfile.appearance
	preview.scale = Vector2.ONE * PREVIEW_SCALE
	preview_area.resized.connect(_center_preview)
	_center_preview()
	name_input.text = PlayerProfile.username
	Session.lobby_changed.connect(_on_session_lobby_changed)
	Session.request_failed.connect(_on_session_request_failed)
	_update_buttons()
	# Say why the player is back here, if they were dropped from a lobby.
	status_label.text = Session.last_error
	Session.last_error = ""


## The preview is a Node2D, which containers don't lay out, so it's placed by
## hand at the bottom center of its area. Its origin is the character's feet.
func _center_preview() -> void:
	preview.position = Vector2(preview_area.size.x / 2.0, preview_area.size.y - 8.0)


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
