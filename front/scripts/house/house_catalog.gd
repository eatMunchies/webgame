class_name HouseCatalog
extends RefCounted

## Finds house art on disk. A house is three layers drawn on top of each
## other, back to front: yard, facade, roof. A style is one PNG per layer at
## assets/sprites/houses/<layer>/<style>.png, so dropping in a new PNG adds a
## style for that layer with no code change.
##
## Every layer is 64x80 and shares one layout, which is why any roof fits any
## facade: the facade fills x 12..51, y 44..71, the roof's eaves end at y 48,
## and the house meets the ground at y 72, with the yard's front strip below.

const ROOT := "res://assets/sprites/houses"
const LAYERS: Array[String] = ["yard", "facade", "roof"]
## Shown on a lot nobody owns, in place of the yard.
const EMPTY_LOT := ROOT + "/empty_lot.png"
## Where the house meets the ground in every layer. Sprites are shifted by
## this so a house node's origin is that point.
const GROUND_POINT := Vector2(32, 72)


## Lists the style names available for a layer. Style names are the file
## names without ".png".
static func styles_for(layer: String) -> PackedStringArray:
	var styles := PackedStringArray()
	for entry in ResourceLoader.list_directory("%s/%s" % [ROOT, layer]):
		if entry.get_extension() == "png":
			styles.append(entry.get_basename())
	styles.sort()
	return styles


## Returns a layer's drawing in a style, or null when there isn't one.
static func texture(layer: String, style: String) -> Texture2D:
	var path := "%s/%s/%s.png" % [ROOT, layer, style]
	return load(path) if ResourceLoader.exists(path) else null
