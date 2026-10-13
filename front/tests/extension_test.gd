extends GdUnitTestSuite


func test_rust_classes_are_registered() -> void:
	for class_name_ in [&"StateMachine", &"State"]:
		assert_bool(ClassDB.class_exists(class_name_)) \
				.override_failure_message("%s isn't registered; is the extension built?" % class_name_) \
				.is_true()


func test_frames_use_fixed_step() -> void:
	var start := Engine.get_process_frames()
	for i in 3:
		await get_tree().process_frame
	assert_int(Engine.get_process_frames() - start).is_equal(3)
	assert_float(get_process_delta_time()).is_equal_approx(1.0 / 60.0, 0.000001)
