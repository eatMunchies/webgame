class_name SkillCheck
extends Control

## One kind of skill check: a small game a player plays for their night
## action. Each kind is a scene whose root extends this, listed by a
## SkillCheckDef resource that also holds its tuning. The MinigameOverlay
## picks one of its `skill_checks`, fills its game area with it, and sends
## what it reports to the server.
##
## A skill check works out its own chance of passing, from 0 to 1, and calls
## report() as that changes, then once more with `finished` when the player
## is done. The server rolls with the chance once it's done, or with the last
## one reported when the stage ends first.
##
## With `practice` on, nothing rides on it and report() sends nothing.
## Passive games are practice from the start, and a skill check turns into
## practice once the server decides it, so a finished player looks as busy as
## anyone.
##
## A kind draws itself and takes its own input (it gets keys and taps before
## the overlay does), calls report(), fills in hint(), status() and
## practice_status(), and emits `changed` when what those return changes. It
## reads its numbers from `def`, which is set before it enters the tree.

## How the check is going: the chance it should pass, from 0 to 1, and
## whether the player is done.
signal reported(chance: float, done: bool)
## Something title(), hint(), status() or practice_status() returns changed.
signal changed

const GOLD := Color(1, 0.8, 0.3)
const MISS_COLOR := Color(0.92, 0.38, 0.38)

## What kind of check this is and how it's tuned. Null when the scene is run
## by itself, so a kind falls back on its own defaults.
var def: SkillCheckDef
## Nothing rides on it, so reports go nowhere.
var practice := false:
	set(value):
		practice = value
		changed.emit()
## Whether the player has finished, so only the server's roll is left.
var done := false
## The chance last reported.
var chance := 0.0


## The overlay's title while it's played for real.
func title() -> String:
	return def.title if def != null else "Skill check"


## How to play, shown above the game.
func hint() -> String:
	return ""


## How it has gone, like "3/5 hits", shown under the game and next to the
## result. "" for nothing yet.
func status() -> String:
	return ""


## The practice score, like "Streak 3", shown while practicing.
func practice_status() -> String:
	return ""


## Whether the player is done and waiting for the server to decide.
func waiting() -> bool:
	return done and not practice


## Reports the chance the check should pass, and whether the player is done.
## Does nothing in practice or once done.
func report(new_chance: float, finished := false) -> void:
	if practice or done:
		return
	chance = clampf(new_chance, 0.0, 1.0)
	done = finished
	reported.emit(chance, done)


## Whether `event` is a tap or left click.
static func is_tap(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
