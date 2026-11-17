extends GdUnitTestSuite

## Arriving in the town: the player can walk out of a house they start in,
## and it blocks them again once they're out, and the start screen's floor
## dissolves into the town around them.

const TOWN_SCENE := preload("res://scenes/main/town.tscn")
const START_SCENE := preload("res://scenes/main/lobby.tscn")
## A spot by a house, from its ground point, that's inside its walls.
const IN_WALLS := Vector2(16, 2)


## A town with a house on the first lot and the player standing in its
## walls, before the town lets them out.
func town_with_player_in_a_house() -> Node2D:
	var town: Node2D = auto_free(TOWN_SCENE.instantiate())
	add_child(town)
	var house: House = town.houses.get_child(0)
	house.appearance = HouseAppearance.random(1)
	town.player.position = house.position + IN_WALLS
	return town


func test_the_spot_is_inside_the_house_walls() -> void:
	var town := town_with_player_in_a_house()
	assert_bool(town._overlaps(town.houses.get_child(0))).is_true()


func test_without_letting_them_out_the_house_traps_them() -> void:
	var town := town_with_player_in_a_house()
	await get_tree().physics_frame
	assert_bool(town.player.test_move(town.player.global_transform, Vector2(0, -4))).is_true()


func test_a_house_the_player_stands_in_does_not_block_them() -> void:
	var town := town_with_player_in_a_house()
	var house: House = town.houses.get_child(0)
	town._let_out_of_houses()
	assert_array(town._passing_through).contains_exactly([house])
	await get_tree().physics_frame
	assert_bool(town.player.test_move(town.player.global_transform, Vector2(0, -4))).is_false()


func test_the_house_blocks_them_again_once_they_are_out() -> void:
	var town := town_with_player_in_a_house()
	var house: House = town.houses.get_child(0)
	town._let_out_of_houses()
	town.player.position = house.position + Vector2(0, 20)
	town._physics_process(0.0)
	assert_array(town._passing_through).is_empty()
	await get_tree().physics_frame
	assert_bool(town.player.test_move(town.player.global_transform, Vector2(0, -20))).is_true()


func test_empty_lots_are_never_passed_through() -> void:
	var town: Node2D = auto_free(TOWN_SCENE.instantiate())
	add_child(town)
	town.player.position = town.houses.get_child(0).position
	town._let_out_of_houses()
	assert_array(town._passing_through).is_empty()


func test_the_start_screen_hands_over_where_the_player_stands() -> void:
	var start: Node2D = auto_free(START_SCENE.instantiate())
	add_child(start)
	start.player.position = start.house.position + Vector2(30, 20)
	assert_vector(start.arrival_spot()).is_equal(Vector2(30, 20))


func test_the_floor_dissolves_with_the_player_and_their_house_above_it() -> void:
	var town: Node2D = auto_free(TOWN_SCENE.instantiate())
	add_child(town)
	var house: House = town.houses.get_child(0)
	town._phase_in(house.position)
	assert_object(town._phase_floor).is_not_null()
	assert_int(town.player.z_index).is_greater(town._phase_floor.z_index)
	assert_int(house.z_index).is_greater(town._phase_floor.z_index)
	assert_int(town.houses.get_child(1).z_index).is_equal(0)
	town._end_phase_in()
	assert_object(town._phase_floor).is_null()
	assert_int(town.player.z_index).is_equal(0)
	assert_int(house.z_index).is_equal(0)
