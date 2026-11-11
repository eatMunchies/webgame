extends GdUnitTestSuite

# Each test puts the container in a SubViewport, which stands in for the screen: resizing it is
# what rotating a phone does to the real one.

var _screen: SubViewport
var _flow: AspectFlowContainer


func before_test() -> void:
	_screen = auto_free(SubViewport.new())
	_screen.size = Vector2i(1280, 720)
	add_child(_screen)
	_flow = AspectFlowContainer.new()
	_screen.add_child(_flow)


func test_wide_screen_lays_out_a_row() -> void:
	assert_bool(_flow.vertical).is_false()


func test_tall_screen_lays_out_a_column() -> void:
	_screen.size = Vector2i(720, 1280)
	assert_bool(_flow.vertical).is_true()


func test_rotating_back_restores_the_row() -> void:
	_screen.size = Vector2i(720, 1280)
	_screen.size = Vector2i(1280, 720)
	assert_bool(_flow.vertical).is_false()


func test_flow_changed_reports_each_switch_once() -> void:
	var switches: Array[bool] = []
	_flow.flow_changed.connect(func(vertical: bool) -> void: switches.append(vertical))
	_screen.size = Vector2i(720, 1280)
	_screen.size = Vector2i(700, 1300)
	_screen.size = Vector2i(1280, 720)
	assert_array(switches).is_equal([true, false])


func test_threshold_moves_the_switch_point() -> void:
	# 1280x720 is about 1.78 wide; a threshold above that makes it a column.
	_flow.aspect_threshold = 2.0
	assert_bool(_flow.vertical).is_true()
	_flow.aspect_threshold = 1.5
	assert_bool(_flow.vertical).is_false()


func test_children_follow_the_direction() -> void:
	_flow.size = Vector2(200, 200)
	var first := Control.new()
	var second := Control.new()
	for child in [first, second]:
		child.custom_minimum_size = Vector2(50, 50)
		_flow.add_child(child)
	_screen.size = Vector2i(720, 1280)
	await get_tree().process_frame
	assert_float(second.position.y).is_greater(first.position.y)
	assert_float(second.position.x).is_equal(first.position.x)
