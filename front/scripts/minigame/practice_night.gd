class_name PracticeNight
extends Node

## A whole night played through a MinigameOverlay with no server, for the
## minigame tester. It steps through the night's stages at the server's fast
## timings and gives the overlay what GameClient would each stage, so the
## overlay can't tell it apart from a real night:
##
## - Choose your action, with no minigame, as players pick targets.
## - Roleblocks, Fights 1/3 to 3/3, Protection, Investigations: one minigame
##   each. Your action's skill check falls in one of the action stages, and
##   a fight in one of the rounds; every other stage is the passive practice
##   game, which carries on from stage to stage.
##
## A night either has you attacking someone in the first fight round (a
## killing role, so no skill check), or has you doing an action and being
## attacked in a random round. Skill checks are rolled as the server rolls
## them. Fights run the real fight rules through PracticeFight, against a
## bot that reacts after a human-ish delay, so it can be beaten. As on the
## server, a fight runs past its stage until someone is knocked out.
##
## `start(overlay, -1, true)` plays FIGHT_PRACTICE fights back to back
## instead, attacking then defending, for learning the fight.
##
## Once the last stage ends, `finished` gives the morning's summary.

## A stage starts: its title, like "Fights 2/3", and how long it lasts.
signal stage_started(title: String, seconds: float)
## Something worth showing in the tester's log happened.
signal logged(line: String)
## The controls for what's being played changed.
signal hint_changed(text: String)
## The night is over: what the morning would tell you about it.
signal finished(summary: String)

## How long the stages last, in seconds, as the server's fast timers.
const CHOOSING_SECONDS := 4.0
const STAGE_SECONDS := 8.0
## Fight rounds last longer, as on the server, to leave room for a few exchanges.
const FIGHT_SECONDS := 24.0
## How many fights a fights-only practice plays.
const FIGHT_PRACTICE := 3
const FIGHT_HINT := "Strike (J) to hit them. Guard (L) as soon as they start a strike: it takes a moment to come up, blocks, and leaves them dazed, then strike. A guard can't be raised again right away. Grab (K) when they guard. First to lose 3 hits loses."
## The bot's reaction time, in milliseconds, and how often it fails to
## react to a move at all, so it can be beaten while learning.
const BOT_REACTION_MS := Vector2i(350, 600)
const BOT_MISS_CHANCE := 0.25
## The first stage's title, as GameClient names it.
const CHOOSING := "Choose your action"
## The action stages a skill check can fall in.
const ACTION_STAGES := ["Roleblocks", "Protection", "Investigations"]

var overlay: MinigameOverlay
## Each stage as {title, seconds, kind}: kind is "", "skill_check", "fight"
## or "passive".
var stages: Array[Dictionary] = []
var you_attack := false
## The stage being played, as an index into `stages`.
var stage := -1
## How the night went, for the morning: "passed"/"failed" for the action and
## "won"/"lost" for the fight, "" if not had.
var check_result := ""
var fight_result := ""
## Fights-only practice: fights back to back, and how many were won.
var fights_only := false
var fights_won := 0

var _rng := RandomNumberGenerator.new()
var _fight: PracticeFight
var _stage_ends_msec := 0
var _chance := 0.0
var _bot_next_msec := 0


## The stages of a night, as {title, seconds, kind}. An attacker fights in
## the first round; anyone else gets a skill check in one action stage and
## is attacked in one random round.
static func plan(attacking: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var check_stage: String = "" if attacking else ACTION_STAGES[rng.randi_range(0, ACTION_STAGES.size() - 1)]
	var fight_round := 1 if attacking else rng.randi_range(1, 3)
	var night: Array[Dictionary] = [{"title": CHOOSING, "seconds": CHOOSING_SECONDS, "kind": ""}]
	var titles := ["Roleblocks", "Fights 1/3", "Fights 2/3", "Fights 3/3", "Protection", "Investigations"]
	for title: String in titles:
		var kind := "passive"
		if title == check_stage:
			kind = "skill_check"
		elif title == "Fights %d/3" % fight_round:
			kind = "fight"
		var seconds := FIGHT_SECONDS if title.begins_with("Fights") else STAGE_SECONDS
		night.append({"title": title, "seconds": seconds, "kind": kind})
	return night


## Starts a night on `with_overlay`. `attacking` picks whether you attack
## or are attacked; -1 picks at random. `only_fights` plays fights back to
## back instead.
func start(with_overlay: MinigameOverlay, attacking := -1, only_fights := false) -> void:
	_rng.randomize()
	overlay = with_overlay
	fights_only = only_fights
	fights_won = 0
	you_attack = _rng.randf() < 0.5 if attacking < 0 else attacking == 1
	if fights_only:
		stages = []
		for i in FIGHT_PRACTICE:
			stages.append({"title": "Fight %d/%d" % [i + 1, FIGHT_PRACTICE], "seconds": FIGHT_SECONDS, "kind": "fight"})
	else:
		stages = plan(you_attack, _rng)
	# As on the server, every minigame stage gets the countdown on top.
	for stage_info in stages.slice(0 if fights_only else 1):
		stage_info["seconds"] += overlay.intro_seconds
	check_result = ""
	fight_result = ""
	stage = -1
	overlay.check_reported.connect(_on_check_reported)
	overlay.fight_move.connect(func(move: String) -> void: _play_you(move))
	overlay.guard_changed.connect(func(up: bool) -> void: _play_you("guard" if up else "unguard"))
	if not fights_only:
		logged.emit("Night 1: you %s." % ("attack someone" if you_attack else "do an action"))
	_next_stage()


func _process(_delta: float) -> void:
	if stage < 0 or stage >= stages.size():
		return
	if _fight != null and fight_result == "":
		_fight.advance()
		_bot_think()
		_fight.advance()
		var winner := _fight.winner()
		if winner != "":
			_end_fight(winner == "you")
	# As on the server, a fight runs past its stage until a knockout.
	if Time.get_ticks_msec() >= _stage_ends_msec and not _fight_running():
		_end_stage()
		_next_stage()


func _fight_running() -> bool:
	return _fight != null and fight_result == ""


func _next_stage() -> void:
	stage += 1
	# GameClient clears the minigame between stages, then sends the next.
	overlay.show_minigame({})
	if stage >= stages.size():
		_morning()
		return
	var info: Dictionary = stages[stage]
	var ms := int(info["seconds"] * 1000)
	_stage_ends_msec = Time.get_ticks_msec() + ms
	stage_started.emit(info["title"], info["seconds"])
	match info["kind"]:
		"":
			hint_changed.emit("Pick your target. Nothing to play yet.")
			return
		"fight":
			_start_fight(ms)
			return
		"skill_check":
			_chance = 0.0
			logged.emit("Your action's skill check")
	overlay.show_minigame({"kind": info["kind"], "ends_in_ms": ms})
	hint_changed.emit(overlay.check.hint() if overlay.check != null else "")


## Decides anything still undecided when a stage runs out, as the server does.
func _end_stage() -> void:
	var kind: String = stages[stage]["kind"]
	if kind == "skill_check" and check_result == "":
		logged.emit("Out of time")
		_decide_check()
	elif kind == "fight" and fight_result == "":
		_fight.time_up()
		_end_fight(_fight.winner() == "you")
	_fight = null
	overlay.fight_source = Callable()


func _on_check_reported(chance: float, done: bool) -> void:
	if stage < 0 or stages[stage]["kind"] != "skill_check" or check_result != "":
		return
	_chance = chance
	if done:
		_decide_check()


func _decide_check() -> void:
	check_result = "passed" if _rng.randf() < _chance else "failed"
	logged.emit("Rolled %d%%: %s" % [roundi(_chance * 100), check_result])
	overlay.show_minigame({
		"kind": "skill_check",
		"ends_in_ms": maxi(_stage_ends_msec - Time.get_ticks_msec(), 0),
		"result": check_result,
	})


func _start_fight(ms: int) -> void:
	fight_result = ""
	if fights_only:
		# Take turns: attack one fight, defend the next.
		you_attack = stage % 2 == 0
	_fight = PracticeFight.new()
	_fight.start(you_attack)
	# The bot waits out the countdown too, then takes a moment to react.
	_bot_next_msec = Time.get_ticks_msec() + int(overlay.intro_seconds * 1000) + BOT_REACTION_MS.y
	overlay.fight_source = _fight.view
	overlay.show_minigame({"kind": "fight", "ends_in_ms": ms, "attacking": you_attack})
	logged.emit("You attack!" if you_attack else "You're attacked!")
	hint_changed.emit(FIGHT_HINT)


func _end_fight(you_won: bool) -> void:
	fight_result = "won" if you_won else "lost"
	if you_won:
		fights_won += 1
	logged.emit("Fight %s" % fight_result)
	overlay.show_minigame({
		"kind": "fight",
		"ends_in_ms": maxi(_stage_ends_msec - Time.get_ticks_msec(), 0),
		"attacking": you_attack,
		"result": fight_result,
	})
	# A decided fight gives way to the practice game, as the overlay does
	# in a real night.
	hint_changed.emit(overlay.check.hint() if overlay.check != null else "")


func _play_you(action: String) -> void:
	if _fight != null and fight_result == "":
		_fight.play(true, action)


## The opponent: guard a strike, step out of a grab and punish it, grab a
## guard, otherwise press the attack (or turtle up as the victim). It only
## looks at the fight every reaction time, so quick play beats it.
func _bot_think() -> void:
	var now := Time.get_ticks_msec()
	if now < _bot_next_msec:
		return
	_bot_next_msec = now + _rng.randi_range(BOT_REACTION_MS.x, BOT_REACTION_MS.y)
	# Sometimes it just doesn't see it coming.
	if _rng.randf() < BOT_MISS_CHANCE:
		return
	var view := _fight.view()
	var me: Dictionary = view["opponent"]
	var them: Dictionary = view["you"]
	if me["move"] != "" or me["staggered_ms"] > 0:
		return
	match them["move"]:
		"strike":
			# A guard only helps if it's up before the strike lands.
			if not me["guard_raised"] and them["lands_in_ms"] > GameClient.GUARD_RAISE_MS:
				_fight.play(false, "guard")
			return
		"grab":
			# A strike only wins if it lands first; otherwise drop the guard
			# so the grab misses, then punish the stagger.
			if them["lands_in_ms"] > GameClient.STRIKE_WINDUP_MS:
				_fight.play(false, "strike")
			elif me["guard_raised"]:
				_fight.play(false, "unguard")
			return
	# A grab only lands if their guard is still up when it does.
	if them["guard_raised"] and them["guard_ms"] > GameClient.GRAB_WINDUP_MS:
		_fight.play(false, "grab")
	elif them["staggered_ms"] > 0:
		_fight.play(false, "strike")
	elif not you_attack:
		_fight.play(false, "strike" if _rng.randf() < 0.6 else "guard")
	else:
		_fight.play(false, "strike" if _rng.randf() < 0.3 else "guard")


func _morning() -> void:
	stage_started.emit("Morning", 0.0)
	hint_changed.emit("")
	if fights_only:
		finished.emit("You won %d of %d fights." % [fights_won, FIGHT_PRACTICE])
		return
	var lines: Array[String] = []
	if check_result != "":
		lines.append("Your action %s." % ("worked" if check_result == "passed" else "failed"))
	if you_attack:
		lines.append("Your target %s." % ("died" if fight_result == "won" else "survived"))
	else:
		lines.append("You %s." % ("survived the attack" if fight_result == "won" else "were killed"))
	finished.emit(" ".join(lines))
