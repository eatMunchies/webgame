extends Node

## The local player's saved character, available everywhere as the
## PlayerProfile autoload. Scenes read `appearance` to draw the player and
## `house` for their house, and the customizer replaces them and calls save(). `username` is the name the player
## goes by on the game server, set on the lobby screen.
##
## It is stored in user://, which is a per-user app data folder on desktop and
## browser storage (IndexedDB) on the web, so it survives reloads.

const SAVE_PATH := "user://profile.cfg"
## Slots that start filled so a new character has a face.
const DEFAULT_FIRST_ITEM: Array[String] = ["eyes", "mouth"]

var appearance := CharacterAppearance.new()
## The house layers the player picked. Empty layers get a random style in
## each lobby.
var house := HouseAppearance.new()
var username := ""
## The name on disk. Differs from username when `--name=` was given, which
## lasts only for this run so test players don't overwrite the real name.
var _saved_username := ""


func _ready() -> void:
	if not load_profile():
		for slot in DEFAULT_FIRST_ITEM:
			var items := PartCatalog.items_for(slot)
			if not items.is_empty():
				appearance.items[slot] = items[0]
	_saved_username = username
	var launch_name := LaunchOptions.value("name")
	if launch_name != "":
		username = launch_name


## Writes the appearance, house and username to disk.
func save() -> void:
	var file := ConfigFile.new()
	file.set_value("appearance", "body_type", appearance.body_type)
	file.set_value("appearance", "gender", appearance.gender)
	file.set_value("appearance", "skin_color", appearance.skin_color)
	file.set_value("appearance", "items", appearance.items)
	file.set_value("house", "layers", house.to_dictionary())
	if LaunchOptions.value("name") == "":
		_saved_username = username
	file.set_value("profile", "username", _saved_username)
	var error := file.save(SAVE_PATH)
	if error != OK:
		push_error("Could not save the profile: %s" % error_string(error))


## Reads the saved appearance, house and username. Returns false when there is no save yet.
func load_profile() -> bool:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return false
	appearance.body_type = file.get_value("appearance", "body_type", appearance.body_type)
	appearance.gender = file.get_value("appearance", "gender", appearance.gender)
	appearance.skin_color = file.get_value("appearance", "skin_color", appearance.skin_color)
	username = file.get_value("profile", "username", username)
	house = HouseAppearance.new()
	house.apply_dictionary(file.get_value("house", "layers", {}))
	var items: Dictionary = file.get_value("appearance", "items", {})
	appearance.items.clear()
	for slot in items:
		appearance.items[str(slot)] = str(items[slot])
	return true
