class_name FlappyCheckDef
extends SkillCheckDef

## How a FlappyCheck is tuned.

## How many pipes make a full pass. Each one flown through is an equal share
## of the chance.
@export_range(1, 20) var pipes := 5
## How tall the gap in each pipe is, in field units (the field is 100 tall).
@export_range(20.0, 70.0, 1.0) var gap := 38.0
