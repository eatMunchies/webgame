class_name WheelCheckDef
extends SkillCheckDef

## How a WheelCheck is tuned.

## How many presses the check takes. Each hit is an equal share of the chance.
@export_range(1, 20) var presses := 5
## How wide the gold zone is.
@export_range(10.0, 180.0, 1.0, "suffix:°") var zone_degrees := 60.0
## How fast the needle goes around.
@export_range(0.1, 3.0, 0.05, "suffix:turns/s") var turns_per_second := 0.75
