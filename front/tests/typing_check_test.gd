extends GdUnitTestSuite

var check: TypingCheck
## Everything the check reported, as [chance as a whole percent, done].
var reported: Array


func before_test() -> void:
	reported = []
	var def: TypingCheckDef = load("res://skill_checks/typing.tres").duplicate()
	def.word_count = 3
	check = auto_free(def.instantiate())
	add_child(check)
	check.words = PackedStringArray(["cat", "dog", "sun"])
	check.reported.connect(func(chance: float, done: bool) -> void:
		reported.append([roundi(chance * 100), done]))


## Types `text` as key presses, a space finishing each word.
func type(text: String) -> void:
	for letter in text:
		var event := InputEventKey.new()
		event.pressed = true
		if letter == " ":
			event.keycode = KEY_SPACE
		else:
			event.unicode = letter.unicode_at(0)
		check._unhandled_key_input(event)


func backspace(ctrl := false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_BACKSPACE
	event.ctrl_pressed = ctrl
	check._unhandled_key_input(event)


func test_the_word_pool_comes_from_the_wordbank() -> void:
	var def: TypingCheckDef = load("res://skill_checks/typing.tres")
	var pool := def.word_pool()
	assert_int(pool.size()).is_greater(1000)
	for word in pool:
		assert_int(word.length()).is_less_equal(def.max_word_length)
	assert_int(check.words.size()).is_equal(3)


func test_each_word_is_reported_as_it_is_finished() -> void:
	type("cat dgo ")
	assert_array(reported).is_equal([[33, false], [33, false]])
	assert_str(check.status()).is_equal("1/3 words")
	type("su")
	assert_array(reported).has_size(2)
	type("N")
	assert_array(reported).is_equal([[33, false], [33, false], [67, true]])
	assert_bool(check.waiting()).is_true()
	type(" more ")
	assert_array(reported).has_size(3)


func test_a_wrong_last_word_waits_for_space() -> void:
	type("cat dog sn")
	type("x")
	assert_array(reported).has_size(2)
	backspace()
	backspace()
	type("un")
	assert_array(reported).is_equal([[33, false], [67, false], [100, true]])


func test_backspace_fixes_the_current_word() -> void:
	type("cxx")
	backspace()
	backspace()
	type("at")
	backspace(true)
	type("cat ")
	assert_array(reported).is_equal([[33, false]])


func test_space_before_any_letter_does_nothing() -> void:
	type("  cat")
	assert_array(reported).is_empty()
	assert_str(check.current).is_equal("cat")


func test_extra_letters_are_capped_and_count_as_wrong() -> void:
	type("catttttttttt")
	assert_int(check.current.length()).is_equal(3 + TypingCheck.MAX_EXTRA)
	type(" ")
	assert_array(reported).is_equal([[0, false]])


func test_practice_keeps_dealing_words_and_reports_nothing() -> void:
	check.practice = true
	type("cat dog sun")
	assert_array(reported).is_empty()
	assert_int(check.typed.size()).is_equal(0)
	assert_int(check.words.size()).is_equal(3)
	assert_int(check._practice_letters).is_equal(12)


func test_a_decided_check_starts_new_words_in_practice() -> void:
	type("cat dog sun ")
	check.practice = true
	type("x")
	assert_int(check.typed.size()).is_equal(0)
	assert_str(check.current).is_equal("x")
