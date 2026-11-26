extends GdUnitTestSuite

## The herald's banner and the Funerals that drive it, against a stand-in
## for the town that records what it was asked to do.


class FakeTown extends Node:
	var calls: Array[String] = []

	func funeral_view(lot: int) -> Vector2:
		calls.append("look house %d" % lot)
		return Vector2.ZERO

	func execution_view() -> Vector2:
		calls.append("look guillotine")
		return Vector2.ZERO

	func look_at_spot(_point: Vector2, _seconds: float) -> void:
		pass

	func look_back(_seconds: float) -> void:
		calls.append("look back")

	func hide_bodies(lots: Array) -> void:
		calls.append("hide %s" % str(lots))

	func reveal_body(lot: int) -> void:
		calls.append("reveal %d" % lot)

	func reveal_all_bodies() -> void:
		calls.append("reveal all")

	func execute(lot: int) -> void:
		calls.append("execute %d" % lot)


func death(lot: int, executed := false) -> Dictionary:
	return {"lot": lot, "name": "Cleo", "role": "Doctor", "will": "N1: healed 4",
		"causes": PackedStringArray(["killed by the Mafia"]), "executed": executed}


func setup() -> Array:
	var town: FakeTown = auto_free(FakeTown.new())
	var herald: Herald = auto_free(Herald.new())
	add_child(town)
	add_child(herald)
	var funerals: Funerals = auto_free(Funerals.new(town, herald))
	add_child(funerals)
	return [town, herald, funerals]


func test_the_herald_says_a_line_at_a_time() -> void:
	var herald: Herald = auto_free(Herald.new())
	add_child(herald)
	herald.announce("2 Cleo was found dead")
	herald.add_line("Killed by the Mafia.")
	assert_bool(herald.visible).is_true()
	assert_array(Array(herald.said())).contains_exactly(["2 Cleo was found dead", "Killed by the Mafia."])
	herald.announce("Morning in Salem")
	await await_idle_frame()
	assert_array(Array(herald.said())).contains_exactly(["Morning in Salem"])


func test_a_funeral_visits_the_body_and_tells_the_death() -> void:
	var parts := setup()
	var town: FakeTown = parts[0]
	var herald: Herald = parts[1]
	var funerals: Funerals = parts[2]
	funerals._on_deaths_announced([death(1)])
	funerals._play("morning", [death(1)], 0.0)
	await await_millis(int((Funerals.DAWN_SECONDS + Funerals.MIN_FUNERAL_SECONDS * 0.85) * 1000))
	assert_array(town.calls).contains(["hide [1]", "look house 1", "reveal 1"])
	assert_array(Array(herald.said())).contains(
		["2 Cleo was found dead", "Killed by the Mafia.", "They were the Doctor."])
	await await_millis(int(Funerals.MIN_FUNERAL_SECONDS * 0.5 * 1000))
	assert_bool(funerals.playing()).is_false()
	assert_array(town.calls).contains(["look back", "reveal all"])


func test_an_execution_drops_the_blade_before_the_funeral() -> void:
	var parts := setup()
	var town: FakeTown = parts[0]
	var funerals: Funerals = parts[2]
	funerals._play("execution", [death(4, true)], 0.0)
	await await_millis(int((Funerals.GLIDE_SECONDS * 2 + Funerals.BEFORE_BLADE_SECONDS
			+ Funerals.AFTER_BLADE_SECONDS + 0.3) * 1000))
	var blade := town.calls.find("execute 4")
	assert_int(blade).is_greater(town.calls.find("look guillotine"))
	assert_int(town.calls.find("reveal 4")).is_greater(blade)
