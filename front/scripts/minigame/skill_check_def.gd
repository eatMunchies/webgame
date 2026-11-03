class_name SkillCheckDef
extends Resource

## A kind of skill check the MinigameOverlay can pick: the scene that plays
## it and the numbers it's tuned with. Each one is a .tres file in
## res://skill_checks/. The scene holds how it plays, the resource holds the
## numbers, so a harder variant is another .tres with nothing new to code.
##
## A kind with tuning of its own extends this with its own exports (see
## WheelCheckDef). Its scene reads them from SkillCheck.def.

## Names the kind, and stays the same once chosen, so the server could hand
## out checks by id one day.
@export var id: StringName
## The overlay's title while it's played for real.
@export var title := "Skill check"
## The scene that plays it. Its root extends SkillCheck.
@export var scene: PackedScene
## How often it's picked, against the others' weights.
@export_range(0.0, 10.0, 0.1, "or_greater") var weight := 1.0


## Makes a skill check of this kind, ready to add to the tree.
func instantiate() -> SkillCheck:
	var check: SkillCheck = scene.instantiate()
	check.def = self
	return check


## Picks one of `defs` at random, by weight, or null if none can be picked.
static func pick(defs: Array[SkillCheckDef], rng: RandomNumberGenerator) -> SkillCheckDef:
	if defs.is_empty():
		return null
	var weights := PackedFloat32Array()
	for def in defs:
		weights.append(def.weight)
	var index := rng.rand_weighted(weights)
	return defs[index] if index >= 0 else null
