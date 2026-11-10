extends GdUnitTestSuite

## The arcade minigames' rules: Flappy Bird, Flappy Golf, Fruit Ninja and
## Blackjack, played through their models, and what each is worth as a
## skill check.


## Steps a model's advance() in frames, `seconds` long in all.
func run(game: RefCounted, seconds: float) -> void:
	for i in roundi(seconds * 60):
		game.advance(1.0 / 60)


# ----- Flappy Bird -----


func test_the_bird_waits_for_its_first_flap() -> void:
	var game := FlappyGame.new(1)
	var start := game.bird_y
	run(game, 2.0)
	assert_float(game.bird_y).is_equal(start)
	assert_float(game.pipes[0].x).is_equal(FlappyGame.FIRST_PIPE_X)


func test_each_pipe_flown_through_counts_once() -> void:
	# A gap the size of the field can't be hit, so only the passes count.
	var game := FlappyGame.new(1, 1000.0)
	for i in 10:
		game.flap()
		run(game, 0.25)
	assert_bool(game.crashed).is_false()
	assert_int(game.passed).is_equal(2)


func test_falling_to_the_ground_crashes() -> void:
	var game := FlappyGame.new(1, 1000.0)
	game.flap()
	run(game, 3.0)
	assert_bool(game.crashed).is_true()
	game.flap()
	assert_float(game.velocity).override_failure_message("a crashed bird can't flap").is_not_equal(FlappyGame.FLAP_SPEED)


func test_a_pipe_crashes_the_bird() -> void:
	var game := FlappyGame.new(1)
	# A pipe whose gap is far below the bird, just ahead of it.
	game.pipes[0] = Vector2(FlappyGame.BIRD_X + 1, FlappyGame.GROUND - 20)
	game.flap()
	run(game, 0.1)
	assert_bool(game.crashed).is_true()


func test_a_flappy_check_reports_pipes_and_finishes_on_a_crash() -> void:
	var check: FlappyCheck = auto_free(load("res://skill_checks/flappy.tres").instantiate())
	add_child(check)
	var reports: Array = []
	check.reported.connect(func(chance: float, done: bool) -> void: reports.append([chance, done]))
	check.game.passed = 2
	check.game.started = true
	check.game.bird_y = FlappyGame.GROUND
	check._process(1.0 / 60)
	assert_array(reports).is_equal([[0.4, true]])
	assert_bool(check.waiting()).is_true()


# ----- Flappy Golf -----


func test_a_ball_dropped_over_the_cup_is_holed() -> void:
	var game := GolfGame.new(4)
	game.ball = Vector2(game.cup_x + GolfGame.CUP_WIDTH / 2.0, 10)
	run(game, 2.0)
	assert_bool(game.holed).is_true()


func test_the_cup_walls_keep_the_ball_in() -> void:
	var game := GolfGame.new(4)
	var bottom := game.ground_at(game.cup_x)
	game.ball = Vector2(game.cup_x + 1.0, bottom - GolfGame.BALL_RADIUS - 3)
	game.velocity = Vector2(90, 0)
	run(game, 1.0)
	assert_bool(game.over_cup(game.ball.x)).is_true()


func test_a_ball_set_down_on_a_hillside_rolls_downhill() -> void:
	var game := GolfGame.new(3)
	# The steepest point of the hill, between the tee and the cup.
	var steepest := 30
	for x in range(30, game.cup_x - 20):
		if absf(game.slope_at(x)) > absf(game.slope_at(steepest)):
			steepest = x
	var downhill := signf(game.slope_at(steepest))
	game.ball = Vector2(steepest, game.ground_at(steepest) - GolfGame.BALL_RADIUS)
	var airborne := 0
	for i in 60:
		game.advance(1.0 / 60)
		if game.ground_at(game.ball.x) - (game.ball.y + GolfGame.BALL_RADIUS) > 0.05:
			airborne += 1
	assert_float((game.ball.x - steepest) * downhill).is_greater(5.0)
	assert_int(airborne).override_failure_message("it rolls along the ground, not in hops").is_zero()


func test_a_ball_coming_down_on_an_uphill_does_not_climb_it() -> void:
	var game := GolfGame.new(3)
	# The steepest uphill (ground rising to the right) between the tee and the cup.
	var uphill := 30
	for x in range(30, game.cup_x - 20):
		if game.slope_at(x) < game.slope_at(uphill):
			uphill = x
	# Coming down onto it as a flap does, moving right.
	game.ball = Vector2(uphill, game.ground_at(uphill) - GolfGame.BALL_RADIUS - 1)
	game.velocity = Vector2(GolfGame.FLAP_SIDE, 60)
	game.on_ground = false
	var highest := game.ball.y
	for i in 120:
		game.advance(1.0 / 60)
		highest = minf(highest, game.ball.y)
	assert_float(highest).override_failure_message("it gains no height up the slope").is_greater_equal(game.ground_at(uphill) - GolfGame.BALL_RADIUS - 2)
	assert_float(game.ball.x).override_failure_message("gravity rolls it back down").is_less(uphill)


func test_courses_vary_and_always_leave_a_way_through() -> void:
	var mirrored := 0
	var with_blocks := 0
	var cups := {}
	for seed_value in 100:
		var game := GolfGame.new(seed_value)
		cups[game.cup_x] = true
		# The tee and the cup are at opposite ends.
		var tee_left := game.tee_x < GolfGame.FIELD.x / 2
		assert_bool(game.cup_x > GolfGame.FIELD.x / 2).is_equal(tee_left)
		if not tee_left:
			mirrored += 1
		assert_float(game.ball.y + GolfGame.BALL_RADIUS).is_equal_approx(game.ground_at(game.tee_x), 0.01)
		# All the ground, the cup's floor too, is on the field, so it draws.
		assert_float(Array(game.ground).max()).is_less(GolfGame.FIELD.y)
		if not game.blocks.is_empty():
			with_blocks += 1
		for block in game.blocks:
			# Room to roll under, and the cup's mouth left open.
			for x in range(ceili(block.position.x), floori(block.end.x) + 1):
				assert_float(game.ground[x] - block.end.y).is_greater_equal(GolfGame.BLOCK_CLEARANCE - 0.01)
			assert_bool(block.end.x < game.cup_x - 3 or block.position.x > game.cup_x + GolfGame.CUP_WIDTH + 3).is_true()
	assert_int(mirrored).is_between(15, 55)
	assert_int(with_blocks).is_between(25, 75)
	assert_int(cups.size()).is_greater(15)


func test_a_ball_lands_on_a_block_and_rolls_off_its_edge() -> void:
	var game := GolfGame.new(1)
	game.blocks = [Rect2(60, 40, 16, 4)]
	game.ball = Vector2(66, 20)
	game.velocity = Vector2.ZERO
	game.on_ground = false
	run(game, 1.0)
	assert_bool(game.on_ground).is_true()
	assert_float(game.ball.y).is_equal_approx(40 - GolfGame.BALL_RADIUS, 0.01)
	# Set rolling right, it runs off the end and drops to the ground.
	game.velocity = Vector2(60, 0)
	run(game, 1.5)
	assert_float(game.ball.x).is_greater(76.0)
	assert_float(game.ball.y + GolfGame.BALL_RADIUS).is_equal_approx(game.ground_at(game.ball.x), 0.05)


func test_a_ball_rolls_round_a_block_corner_without_jumping_or_stalling() -> void:
	var game := GolfGame.new(1)
	game.blocks = [Rect2(60, 40, 16, 4)]
	game.ball = Vector2(73, 40 - GolfGame.BALL_RADIUS)
	game.velocity = Vector2(25, 0)
	game.on_ground = true
	var slowest := INF
	for i in 30:
		var before := game.ball
		var speed := game.velocity.length()
		game.advance(1.0 / 60)
		# No further in a frame than its speed (and a frame of gravity) takes it.
		var reach := (maxf(speed, game.velocity.length()) + GolfGame.GRAVITY / 60) / 60 + 0.1
		assert_float(game.ball.distance_to(before)).override_failure_message("no jumps").is_less(reach)
		if game.ball.x > 76:
			slowest = minf(slowest, game.velocity.x)
	assert_float(game.ball.y).override_failure_message("it falls off past the edge").is_greater(42.0)
	assert_float(slowest).override_failure_message("the corner doesn't eat its speed").is_greater(10.0)


func test_a_ball_clipping_a_block_corner_glances_off_it() -> void:
	var game := GolfGame.new(1)
	game.blocks = [Rect2(60, 40, 16, 4)]
	# Coming down just outside the left edge, it catches the corner.
	game.ball = Vector2(57, 25)
	game.velocity = Vector2(10, 40)
	game.on_ground = false
	run(game, 0.5)
	assert_float(game.ball.x).override_failure_message("pushed off to the left, not onto the top").is_less(57.0)
	assert_bool(game.on_ground and game.block_under(game.ball.x, game.ball.y + GolfGame.BALL_RADIUS) >= 0).is_false()


func test_a_block_stops_a_ball_from_below_and_from_the_side() -> void:
	var game := GolfGame.new(1)
	game.blocks = [Rect2(60, 40, 16, 4)]
	game.ball = Vector2(68, 60)
	game.velocity = Vector2(0, GolfGame.FLAP_UP)
	game.on_ground = false
	var highest := game.ball.y
	for i in 30:
		game.advance(1.0 / 60)
		highest = minf(highest, game.ball.y)
	assert_float(highest).override_failure_message("it bonks off the bottom").is_greater_equal(44 + GolfGame.BALL_RADIUS - 0.01)
	game.ball = Vector2(50, 42)
	game.velocity = Vector2(GolfGame.FLAP_SIDE, -20)
	game.on_ground = false
	run(game, 0.5)
	assert_float(game.ball.x).override_failure_message("it bounces back off the side").is_less(60 - GolfGame.BALL_RADIUS)
	assert_float(game.velocity.x).is_less(0.0)


func test_a_flap_throws_the_ball_up_and_sideways_and_counts() -> void:
	var game := GolfGame.new(4)
	var start := game.ball
	game.flap(1)
	run(game, 0.2)
	assert_int(game.flaps).is_equal(1)
	assert_float(game.ball.x).is_greater(start.x)
	assert_float(game.ball.y).is_less(start.y)
	game.flap(-1)
	assert_float(game.velocity.x).is_less(0.0)


func test_holing_out_is_worth_less_for_each_flap_over_par() -> void:
	var check: GolfCheck = auto_free(load("res://skill_checks/golf.tres").instantiate())
	add_child(check)
	check.tuning.par = 3
	assert_float(check.chance_for(1)).is_equal(1.0)
	assert_float(check.chance_for(3)).is_equal(1.0)
	assert_float(check.chance_for(4)).is_equal_approx(0.8, 0.001)
	assert_float(check.chance_for(20)).is_equal(check.tuning.min_chance)


# ----- Fruit Ninja -----


## A thing to slice, put where a test wants it.
func place(game: FruitGame, at: Vector2, bomb := false) -> FruitGame.Thrown:
	var item := FruitGame.Thrown.new()
	item.position = at
	item.bomb = bomb
	game.thrown.append(item)
	return item


func test_a_swipe_slices_what_it_crosses() -> void:
	var game := FruitGame.new(1, 3, 0)
	var hit := place(game, Vector2(40, 40))
	var missed := place(game, Vector2(40, 80))
	assert_int(game.swipe(Vector2(20, 42), Vector2(60, 38))).is_equal(1)
	assert_bool(hit.sliced).is_true()
	assert_bool(missed.sliced).is_false()
	assert_int(game.swipe(Vector2(20, 42), Vector2(60, 38))).override_failure_message("a fruit slices once").is_equal(0)


func test_a_bomb_ends_the_wave() -> void:
	var game := FruitGame.new(1, 3, 0)
	place(game, Vector2(30, 40))
	place(game, Vector2(50, 40), true)
	place(game, Vector2(70, 40))
	game.swipe(Vector2(20, 40), Vector2(80, 40))
	assert_bool(game.bombed).is_true()
	assert_bool(game.over()).is_true()
	assert_int(game.sliced).is_equal(1)


func test_every_fruit_is_thrown_and_dropped_fruit_counts() -> void:
	var game := FruitGame.new(1, 4, 2)
	assert_bool(game._to_throw[0]).override_failure_message("a bomb is never thrown first").is_false()
	run(game, 10.0)
	assert_int(game.thrown.size()).is_equal(6)
	assert_int(game.dropped).is_equal(4)
	assert_bool(game.over()).is_true()


func test_a_fruit_check_reports_the_share_sliced() -> void:
	var check: FruitCheck = auto_free(load("res://skill_checks/fruit.tres").instantiate())
	add_child(check)
	var reports: Array = []
	check.reported.connect(func(chance: float, done: bool) -> void: reports.append([chance, done]))
	var at := check.field_corner() + Vector2(40, 40) * check.field_scale()
	place(check.game, Vector2(40, 40))
	check.swipe(at - Vector2(10, 0), at + Vector2(10, 0))
	assert_array(reports).is_equal([[1.0 / check.game.fruit_per_wave, false]])


# ----- Blackjack -----


## A card of a rank (1 an ace, 11 to 13 the face cards) in spades.
func card(rank: int) -> int:
	return rank - 1


func test_aces_count_eleven_unless_that_busts() -> void:
	assert_int(BlackjackGame.total([card(1), card(13)])).is_equal(21)
	assert_int(BlackjackGame.total([card(1), card(1), card(9)])).is_equal(21)
	assert_int(BlackjackGame.total([card(1), card(5), card(12)])).is_equal(16)
	assert_int(BlackjackGame.total([card(10), card(11), card(2)])).is_equal(22)


func test_a_two_deck_shoe_holds_104_cards() -> void:
	var game := BlackjackGame.new(1)
	assert_int(game.shoe.size()).is_equal(104)
	game.deal()
	assert_int(game.shoe.size()).is_equal(100)


func test_the_bust_chance_counts_the_unseen_cards() -> void:
	var game := BlackjackGame.new(1)
	game.player = [card(10), card(12)]
	game.dealer = [card(9), card(5)]
	game.turn = "player"
	# On 20 only an ace keeps the player in. The dealer's hidden 5 is unseen
	# too, so it counts.
	game.shoe = [card(1), card(13)]
	game.hole_hidden = true
	assert_float(game.bust_chance()).is_equal_approx(2.0 / 3, 0.001)
	game.hole_hidden = false
	assert_float(game.bust_chance()).is_equal_approx(0.5, 0.001)


func test_the_dealer_draws_to_17_and_stands_on_soft_17() -> void:
	var game := BlackjackGame.new(1)
	game.player = [card(10), card(8)]
	game.dealer = [card(1), card(6)]
	game.turn = "player"
	game.stand()
	run(game, 2.0)
	assert_int(game.dealer.size()).is_equal(2)
	assert_str(game.outcome).is_equal("win")
	# The shoe deals from the back: the dealer draws the 5, to 19.
	game.dealer = [card(10), card(4)]
	game.shoe = [card(13), card(5)]
	game.turn = "player"
	game.stand()
	run(game, 2.0)
	assert_int(game.dealer.size()).is_equal(3)
	assert_str(game.outcome).is_equal("lose")


func test_busting_loses_even_if_the_dealer_would_bust() -> void:
	var game := BlackjackGame.new(1)
	game.player = [card(10), card(6)]
	game.dealer = [card(10), card(6)]
	game.shoe = [card(10), card(13)]
	game.turn = "player"
	game.hit()
	assert_str(game.turn).is_equal("over")
	assert_str(game.outcome).is_equal("bust")


func test_a_blackjack_check_reports_what_the_hand_is_worth() -> void:
	var check: BlackjackCheck = auto_free(load("res://skill_checks/blackjack.tres").instantiate())
	add_child(check)
	var reports: Array = []
	check.reported.connect(func(chance: float, done: bool) -> void: reports.append([chance, done]))
	check.game.player = [card(10), card(9)]
	check.game.dealer = [card(10), card(9)]
	check.game.turn = "player"
	check._was_over = false
	check.stand()
	check._process(1.0)
	assert_str(check.game.outcome).is_equal("push")
	assert_array(reports).is_equal([[0.5, true]])
