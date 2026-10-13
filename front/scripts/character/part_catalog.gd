class_name PartCatalog
extends RefCounted

## Finds character art on disk. Drop a new folder into
## assets/sprites/characters/parts/<folder>/<item>/ and it shows up as an
## option with no code change.
##
## Every sheet is 128x128: 4 columns of walk frames (column 0 is idle) by
## 4 rows of facings (down, left, right, up), each frame 32x32.

const ROOT := "res://assets/sprites/characters"
const BODY_TYPES: Array[String] = ["regular", "chibi", "lanky"]
const GENDERS: Array[String] = ["male", "female"]

## Slots in back-to-front draw order over the body. "folder" is where the
## slot's items live (both hands share the "held" pool). "anchor" names the
## body point a shared drawing is shifted to; see BODY_ANCHORS.
const SLOTS := {
	"legs": {"folder": "legs", "anchor": ""},
	"chest": {"folder": "chest", "anchor": ""},
	"gauntlets": {"folder": "gauntlets", "anchor": "hand"},
	"eyes": {"folder": "eyes", "anchor": "head"},
	"mouth": {"folder": "mouth", "anchor": "head"},
	"accessory": {"folder": "accessory", "anchor": "head"},
	"hat": {"folder": "hat", "anchor": "head"},
	"main_hand": {"folder": "held", "anchor": "hand"},
	"off_hand": {"folder": "held", "anchor": "hand"},
}
const PET_FOLDER := "pet"

## How far each body type's head and hands sit from the regular body's, in
## pixels. Applied only when a part has no drawing made for that body type,
## so one hat drawn on the regular body still lands on a chibi or lanky head.
const BODY_ANCHORS := {
	"regular": {"head": Vector2.ZERO, "hand": Vector2.ZERO},
	"chibi": {"head": Vector2(0, 4), "hand": Vector2(0, 4)},
	"lanky": {"head": Vector2(0, -4), "hand": Vector2(0, -3)},
}


## A part texture plus the shift needed to fit it to the current body.
class ResolvedPart:
	var texture: Texture2D
	var offset := Vector2.ZERO


static func body_texture(body_type: String, gender: String) -> Texture2D:
	return _load_if_exists("%s/bodies/%s_%s.png" % [ROOT, body_type, gender])


## Lists the item names available for a slot, or for the pet when slot is
## PET_FOLDER. Item names are the folder names.
static func items_for(slot: String) -> PackedStringArray:
	var folder: String = SLOTS[slot].folder if SLOTS.has(slot) else slot
	var items := PackedStringArray()
	for entry in ResourceLoader.list_directory("%s/parts/%s" % [ROOT, folder]):
		if entry.ends_with("/"):
			items.append(entry.trim_suffix("/"))
	items.sort()
	return items


## Picks the most specific drawing of an item for a body. The lookup order is
## <type>_<gender>.png, <type>.png, <gender>.png, then all.png. Drawings not
## made for this body type get shifted by the slot's anchor. Returns a part
## with a null texture when the item has no usable file.
static func resolve(slot: String, item: String, body_type: String, gender: String) -> ResolvedPart:
	var part := ResolvedPart.new()
	if item.is_empty():
		return part
	var folder: String = SLOTS[slot].folder if SLOTS.has(slot) else slot
	var dir := "%s/parts/%s/%s" % [ROOT, folder, item]
	var candidates := ["%s_%s" % [body_type, gender], body_type, gender, "all"]
	for i in candidates.size():
		part.texture = _load_if_exists("%s/%s.png" % [dir, candidates[i]])
		if part.texture == null:
			continue
		var fitted_to_body := i < 2
		var anchor: String = SLOTS[slot].anchor if SLOTS.has(slot) else ""
		if not fitted_to_body and not anchor.is_empty():
			part.offset = BODY_ANCHORS[body_type][anchor]
		break
	return part


static func _load_if_exists(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
