extends GdUnitTestSuite

## The start screen's plaza: the door and house that open the wardrobe, and
## the ring that keeps the player near their house.

const START_SCENE := preload("res://scenes/main/lobby.tscn")


func start_screen() -> Node2D:
	var start: Node2D = auto_free(START_SCENE.instantiate())
	add_child(start)
	return start


func test_the_player_starts_at_the_door() -> void:
	var start := start_screen()
	assert_bool(start.near_door()).is_true()
	start.player.position += Vector2(40, 20)
	assert_bool(start.near_door()).is_false()


func test_the_house_is_tappable_but_its_yard_is_not() -> void:
	var start := start_screen()
	assert_bool(start.on_house(start.house.position + Vector2(0, -30))).is_true()
	assert_bool(start.on_house(start.house.position + Vector2(0, 6))).is_false()


func test_the_player_starts_clear_of_the_house() -> void:
	var start := start_screen()
	await get_tree().physics_frame
	assert_bool(start.player.test_move(start.player.global_transform, Vector2(0, 1))).is_false()


func test_the_ring_stops_the_player_wandering_off() -> void:
	var start := start_screen()
	start.player.position = start.house.position + Vector2(start.EDGE_RADIUS - 12, 0)
	await get_tree().physics_frame
	assert_bool(start.player.test_move(start.player.global_transform, Vector2(30, 0))).is_true()
