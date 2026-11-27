class_name Funerals
extends Node

## Plays a morning's funerals and an execution for everyone at once, while the
## server holds the town still (the Morning and Execution day stages).
##
## The server announces deaths just before the stage starts
## (Session.deaths_announced), and the stage's length allows a funeral for
## each one. At a funeral the camera glides to the dead player's house,
## their body appears lying on the road in front of it, and the herald says who died
## and how, what their role was, reads their last will and says "Rest in
## peace." A morning with nobody dead just says so. At an execution the
## camera first goes to the guillotine, the blade falls on the condemned,
## and then they get their funeral like anyone else.
##
## The pacing is fitted to the time the stage has left, so a funeral runs a
## little longer on a normal server than a fast one. Anything that cuts a
## ceremony short (the game ending) puts the herald away and lays out every
## body.

## How long the camera takes to reach a house or the guillotine.
const GLIDE_SECONDS := 1.0
## The shortest a funeral is paced to, if the stage is short.
const MIN_FUNERAL_SECONDS := 4.0
## How long the morning's opening line shows before the first funeral, and
## how long a morning with nobody dead says so.
const DAWN_SECONDS := 1.2
const QUIET_MORNING_SECONDS := 2.5
## At an execution: from reaching the guillotine to the blade, and from the
## blade to setting off for the house.
const BEFORE_BLADE_SECONDS := 0.8
const AFTER_BLADE_SECONDS := 1.6

## The town, for its camera, bodies and guillotine (see town.gd).
var town: Node
var herald: Herald
## Deaths announced and waiting for their stage.
var _news: Array = []
var _have_news := false
var _playing := false
## Bumped to stop a ceremony that's under way.
var _run := 0


func _init(for_town: Node, town_herald: Herald) -> void:
	town = for_town
	herald = town_herald


func _ready() -> void:
	Session.deaths_announced.connect(_on_deaths_announced)
	Session.phase_changed.connect(_on_phase_changed)


func playing() -> bool:
	return _playing


func _on_deaths_announced(deaths: Array) -> void:
	_news = deaths
	_have_news = true
	town.hide_bodies(deaths.map(func(death: Dictionary) -> int: return death["lot"]))


func _on_phase_changed() -> void:
	var info: Dictionary = Session.client.phase_info()
	var kind: String = info["kind"]
	if kind in ["morning", "execution"]:
		if _have_news:
			_have_news = false
			var deaths := _news
			_news = []
			_play(kind, deaths, maxf(float(info["seconds_left"]), 0.0))
		return
	if _playing or _have_news:
		# The stage ended first (the game ended at dawn, say).
		_have_news = false
		_news = []
		_finish()


func _play(kind: String, deaths: Array, seconds: float) -> void:
	_run += 1
	var run := _run
	_playing = true
	var budget := seconds
	if kind == "execution" and not deaths.is_empty():
		var condemned: Dictionary = deaths[0]
		town.look_at_spot(town.execution_view(), GLIDE_SECONDS)
		herald.announce("The town executes %s", condemned["lot"], condemned["name"])
		if not await _wait(GLIDE_SECONDS + BEFORE_BLADE_SECONDS, run):
			return
		town.execute(condemned["lot"])
		if not await _wait(AFTER_BLADE_SECONDS, run):
			return
		budget -= GLIDE_SECONDS + BEFORE_BLADE_SECONDS + AFTER_BLADE_SECONDS
	else:
		herald.announce("Morning in Salem")
		if deaths.is_empty():
			herald.add_line("Nobody died last night.")
			if not await _wait(minf(QUIET_MORNING_SECONDS, maxf(budget - 0.5, 0.5)), run):
				return
			_finish()
			return
		if not await _wait(DAWN_SECONDS, run):
			return
		budget -= DAWN_SECONDS
	var each := maxf((budget - 0.5) / deaths.size(), MIN_FUNERAL_SECONDS)
	for death: Dictionary in deaths:
		if not await _funeral(death, each, run):
			return
	_finish()


## One funeral, paced to `seconds`. Returns false if the ceremony was
## stopped meanwhile.
func _funeral(death: Dictionary, seconds: float, run: int) -> bool:
	var lot: int = death["lot"]
	town.look_at_spot(town.funeral_view(lot), GLIDE_SECONDS)
	if not await _wait(GLIDE_SECONDS, run):
		return false
	town.reveal_body(lot)
	var executed: bool = death["executed"]
	herald.announce("%s was executed" if executed else "%s was found dead", lot, death["name"])
	var rest := seconds - GLIDE_SECONDS
	if not executed:
		var causes := ", ".join(PackedStringArray(death["causes"]))
		if not await _wait(rest * 0.1, run):
			return false
		herald.add_line(causes.left(1).to_upper() + causes.substr(1) + ".")
	if not await _wait(rest * 0.1, run):
		return false
	herald.add_line("They were the %s." % death["role"], "Dim")
	if not await _wait(rest * 0.1, run):
		return false
	herald.show_will(death["will"])
	if not await _wait(rest * 0.5, run):
		return false
	herald.add_line("Rest in peace.", "Heading")
	return await _wait(rest * 0.2, run)


func _finish() -> void:
	_run += 1
	_playing = false
	herald.clear()
	town.look_back(GLIDE_SECONDS)
	town.reveal_all_bodies()


## Waits, and says whether the ceremony is still the one that's playing.
func _wait(seconds: float, run: int) -> bool:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
	return run == _run and is_inside_tree()
