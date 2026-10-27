class_name HouseAppearance
extends Resource

## The style of each layer of a player's house (see HouseCatalog). Players
## pick theirs on the customizer's House tab, and it's saved with their
## profile and sent with their look. A layer left empty hasn't been picked,
## and the lobby fills it from random(), so every client still agrees.

@export var yard := ""
@export var facade := ""
@export var roof := ""


## Returns the style for one of HouseCatalog.LAYERS.
func style_for(layer: String) -> String:
	return get(layer)


## Returns an independent copy, so edits to it don't change this one.
func copy() -> HouseAppearance:
	var other := HouseAppearance.new()
	for layer in HouseCatalog.LAYERS:
		other.set(layer, get(layer))
	return other


## The picked layers as layer name to style, leaving out empty ones. This is
## the form the server relays.
func to_dictionary() -> Dictionary:
	var picked := {}
	for layer in HouseCatalog.LAYERS:
		if style_for(layer) != "":
			picked[layer] = style_for(layer)
	return picked


## Sets the layers named in a to_dictionary() result, leaving the others.
func apply_dictionary(picked: Dictionary) -> void:
	for layer in HouseCatalog.LAYERS:
		if picked.has(layer):
			set(layer, str(picked[layer]))


## Picks each layer's style on its own, so any mix can come up, such as a
## church roof on a trailer. The same seed always builds the same house,
## which lets every player in a lobby agree on a house from just a number.
static func random(house_seed: int) -> HouseAppearance:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	var house := HouseAppearance.new()
	for layer in HouseCatalog.LAYERS:
		var styles := HouseCatalog.styles_for(layer)
		if not styles.is_empty():
			house.set(layer, styles[rng.randi_range(0, styles.size() - 1)])
	return house
