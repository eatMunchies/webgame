extends GalleryPage

## The night's minigame panel: the countdown that opens a skill check, each
## skill check a moment into play, and a fight with both fighters mid-move.
## Filling the page, as it fills the town's part of the screen in a game.

const OVERLAY := preload("res://scenes/main/minigame_overlay.tscn")
const CHECKS := ["wheel", "typing", "memory", "flappy", "golf", "fruit", "blackjack"]
## A fight a moment in: you winding up a strike, the opponent guarding.
const FIGHT := {
	"max_hp": 3,
	"you": {"hp": 3, "staggered_ms": 0, "move": "strike", "windup_ms": 600, "lands_in_ms": 250,
		"guarding": false, "guard_raised": false, "guard_cooldown_ms": 0},
	"opponent": {"hp": 2, "staggered_ms": 0, "move": "", "windup_ms": 0, "lands_in_ms": 0,
		"guarding": true, "guard_ms": 300, "guard_raised": true, "guard_cooldown_ms": 0},
}


func _init() -> void:
	variants.append("countdown")
	variants.append_array(CHECKS)
	variants.append("fight")
	settle_frames = 40


func build(stage: Control, variant: String) -> void:
	backdrop(stage, Color("#2f3a2a"))
	var overlay: MinigameOverlay = OVERLAY.instantiate()
	overlay.intro_seconds = 3.0 if variant == "countdown" else 0.0
	var def_name: String = "wheel" if variant in ["countdown", "fight"] else variant
	var defs: Array[SkillCheckDef] = [load("res://skill_checks/%s.tres" % def_name)]
	overlay.skill_checks = defs
	stage.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			Tokens.SPACE_MD)
	if variant == "fight":
		overlay.fight_source = func() -> Dictionary: return FIGHT
		overlay.show_minigame({"kind": "fight", "attacking": true})
	else:
		overlay.show_minigame({"kind": "skill_check", "ends_in_ms": 9000})
