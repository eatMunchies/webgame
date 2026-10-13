class_name CharacterAppearance
extends Resource

## Everything a player chooses about how their character looks. Saved as a
## resource so it can later be stored with the player's account or save file.

@export_enum("regular", "chibi", "lanky") var body_type := "regular"
@export_enum("male", "female") var gender := "male"
@export var skin_color := Color(0.96, 0.8, 0.69)
## Item folder name per slot (see PartCatalog.SLOTS). A missing or empty
## entry means the slot is empty.
@export var items: Dictionary[String, String] = {}


func item_for(slot: String) -> String:
	return items.get(slot, "")
