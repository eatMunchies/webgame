extends GdUnitTestSuite

## The minigame tester's night: which stages get which minigame, and the
## PracticeFight that runs the server's fight rules without a server.


func kinds(night: Array[Dictionary]) -> Array:
	return night.map(func(stage: Dictionary) -> String: return stage["kind"])


func test_an_attacker_fights_in_the_first_round_with_no_skill_check() -> void:
	var night := PracticeNight.plan(true, RandomNumberGenerator.new())
	assert_array(kinds(night)).is_equal(
			["", "passive", "fight", "passive", "passive", "passive", "passive"])
	assert_str(night[2]["title"]).is_equal("Fights 1/3")


func test_anyone_else_gets_one_skill_check_and_one_fight() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 30:
		rng.seed = seed_value
		var night := PracticeNight.plan(false, rng)
		var found := kinds(night)
		assert_int(found.count("skill_check")).is_equal(1)
		assert_int(found.count("fight")).is_equal(1)
		var check: String = night[found.find("skill_check")]["title"]
		assert_array(PracticeNight.ACTION_STAGES).contains([check])
		var fight: String = night[found.find("fight")]["title"]
		assert_str(fight).starts_with("Fights")


func test_a_practice_fight_lands_a_strike_after_its_windup() -> void:
	var fight := PracticeFight.new()
	fight.start(true)
	assert_bool(fight.play(true, "strike")).is_true()
	assert_str(fight.view()["you"]["move"]).is_equal("strike")
	fight.skip(fight.view()["you"]["windup_ms"] + 50)
	fight.advance()
	assert_int(fight.view()["opponent"]["hp"]).is_equal(2)
	assert_str(fight.winner()).is_equal("")


func test_a_practice_fight_that_times_out_goes_to_the_victim() -> void:
	var attacking := PracticeFight.new()
	attacking.start(true)
	attacking.time_up()
	assert_str(attacking.winner()).is_equal("opponent")
	var attacked := PracticeFight.new()
	attacked.start(false)
	attacked.time_up()
	assert_str(attacked.winner()).is_equal("you")
