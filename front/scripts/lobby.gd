extends Control

## The start screen. The player can open the customizer, host a new lobby, or
## type a lobby code to join one. Hosting or joining goes to the town.
##
## The buttons' signals are connected in lobby.tscn (select a button and look
## at Node > Signals in the editor), and the nodes this script uses are marked
## as unique names, so they're reached with %Name wherever they sit.

const CUSTOMIZER_SCENE := "res://scenes/main/customizer.tscn"
const TOWN_SCENE := "res://scenes/main/town.tscn"
const PREVIEW_SCALE := 4.0

@onready var code_input: LineEdit = %CodeInput
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var preview_area: Control = %PreviewArea
@onready var preview: Character = %Preview


func _ready() -> void:
	# The project renders at 320x180 for pixel art; menus turn that off so
	# text and buttons draw at full resolution.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	preview.appearance = PlayerProfile.appearance
	preview.scale = Vector2.ONE * PREVIEW_SCALE
	preview_area.resized.connect(_center_preview)
	_center_preview()
	_on_code_input_text_changed(code_input.text)


## The preview is a Node2D, which containers don't lay out, so it's placed by
## hand at the bottom center of its area. Its origin is the character's feet.
func _center_preview() -> void:
	preview.position = Vector2(preview_area.size.x / 2.0, preview_area.size.y - 8.0)


func _on_customize_button_pressed() -> void:
	get_tree().change_scene_to_file(CUSTOMIZER_SCENE)


func _on_create_button_pressed() -> void:
	Session.create_lobby()
	get_tree().change_scene_to_file(TOWN_SCENE)


func _on_join_button_pressed() -> void:
	var error := Session.join_lobby(code_input.text)
	if error != "":
		status_label.text = error
		return
	get_tree().change_scene_to_file(TOWN_SCENE)


## Keeps the code uppercase as the player types, and only enables Join once
## the code is long enough.
func _on_code_input_text_changed(new_text: String) -> void:
	var clean := Session.normalize_code(new_text)
	if clean != new_text:
		var caret := code_input.caret_column
		code_input.text = clean
		code_input.caret_column = mini(caret, clean.length())
	join_button.disabled = clean.length() != Session.CODE_LENGTH
	status_label.text = ""


## Pressing Enter in the code box joins, the same as clicking Join.
func _on_code_input_text_submitted(_text: String) -> void:
	if not join_button.disabled:
		_on_join_button_pressed()
