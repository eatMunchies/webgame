class_name HouseAppearance
extends Resource

## The style of each layer of a player's house (see HouseCatalog). Players
## can't pick these yet: everyone gets a random() house when they join a
## lobby. A house customizer would edit one of these, the same way the
## character customizer edits a CharacterAppearance.

@export var yard := ""
@export var facade := ""
@export var roof := ""


## Returns the style for one of HouseCatalog.LAYERS.
func style_for(layer: String) -> String:
	return get(layer)


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
