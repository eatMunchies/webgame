class_name FruitCheckDef
extends SkillCheckDef

## How a FruitCheck is tuned.

## How many fruit are thrown. Each one sliced is an equal share of the chance.
@export_range(1, 20) var fruit := 8
## How many bombs are mixed in. Slicing one ends the check.
@export_range(0, 10) var bombs := 2
