class_name GolfCheckDef
extends SkillCheckDef

## How a GolfCheck is tuned.

## The flaps a hole should take. Holing out in par or fewer is a sure pass.
@export_range(1, 10) var par := 3
## The chance lost for each flap over par, down to `min_chance`.
@export_range(0.0, 1.0, 0.05) var chance_per_extra_flap := 0.2
## The least a holed ball is worth, however many flaps it took.
@export_range(0.0, 1.0, 0.05) var min_chance := 0.2
