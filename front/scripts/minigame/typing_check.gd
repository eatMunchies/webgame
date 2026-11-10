class_name TypingCheck
extends SkillCheck

## A typing test, like monkeytype: type the words shown, Space after each.
## The last word finishes itself once it's typed right; typed wrong, it waits
## for Space, so it can still be fixed. Each word typed right is an equal
## share of the chance, so 3 of 4 is 75%. Every word is reported as it's
## finished, so a stage that ends early counts the words not reached as
## wrong. Backspace fixes the word being typed (Ctrl+Backspace clears it). In
## practice the words keep coming and it shows the typing speed. Tuned by a
## TypingCheckDef.

const FONT_SIZE := 8
const LINE_GAP := 3
## How many letters past the end of a word can be typed, shown as mistakes.
const MAX_EXTRA := 5
const UNTYPED_COLOR := Color(1, 1, 1, 0.35)

var word_count := 4
## The words to type.
var words := PackedStringArray()
## What was typed for each finished word.
var typed := PackedStringArray()
## What has been typed of the current word.
var current := ""

var _pool := PackedStringArray()
var _rng := RandomNumberGenerator.new()
## When practice typing started, for the speed, or -1 before it has.
var _practice_started_msec := -1
## Letters in words typed right in practice, each with its space.
var _practice_letters := 0


func _ready() -> void:
	_rng.randomize()
	var tuning := def as TypingCheckDef
	if tuning == null:
		tuning = TypingCheckDef.new()
	word_count = tuning.word_count
	_pool = tuning.word_pool()
	_new_words()


func hint() -> String:
	if practice:
		return "Type the words, Space after each. Nothing rides on this one."
	return "Type the words, Space after each. Each one right is a 1 in %d chance your action works." % words.size()


func status() -> String:
	if typed.is_empty() or practice and typed.size() >= words.size():
		return ""
	return "%d/%d words" % [right_words(), words.size()]


func practice_status() -> String:
	var minutes := (Time.get_ticks_msec() - _practice_started_msec) / 60000.0
	if _practice_started_msec < 0 or minutes <= 0.0:
		return ""
	# Five letters make a word, as typing tests count them.
	return "%d wpm" % roundi(_practice_letters / 5.0 / minutes)


## How many of the finished words were typed right.
func right_words() -> int:
	var right := 0
	for i in typed.size():
		if typed[i] == words[i]:
			right += 1
	return right


## Types some letters into the current word.
func type_text(text: String) -> void:
	if waiting():
		return
	if typed.size() >= words.size():
		_new_words()
	if practice and _practice_started_msec < 0:
		_practice_started_msec = Time.get_ticks_msec()
	var word := words[typed.size()]
	var room := word.length() + MAX_EXTRA - current.length()
	current += text.left(maxi(room, 0))
	if typed.size() == words.size() - 1 and current == word:
		space()


## Finishes the current word. Does nothing before a letter is typed.
func space() -> void:
	if waiting() or current == "" or typed.size() >= words.size():
		return
	var word := words[typed.size()]
	typed.append(current)
	current = ""
	if practice:
		if typed[-1] == word:
			_practice_letters += word.length() + 1
		if typed.size() >= words.size():
			_new_words()
	else:
		report(float(right_words()) / words.size(), typed.size() >= words.size())
	changed.emit()


## Takes back a letter, or the whole current word with `whole_word`.
func backspace(whole_word := false) -> void:
	if waiting():
		return
	current = "" if whole_word else current.left(-1)


func _new_words() -> void:
	words = PackedStringArray()
	for i in word_count:
		words.append(_pool[_rng.randi_range(0, _pool.size() - 1)] if not _pool.is_empty() else "type")
	typed = PackedStringArray()
	current = ""
	changed.emit()


func _process(_delta: float) -> void:
	queue_redraw()


## Brings up the on-screen keyboard on phones and tablets while the test
## shows, since there's no text box to tap.
func _notification(what: int) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		if is_visible_in_tree():
			DisplayServer.virtual_keyboard_show("")
		else:
			DisplayServer.virtual_keyboard_hide()
	elif what == NOTIFICATION_EXIT_TREE:
		DisplayServer.virtual_keyboard_hide()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or not key.pressed:
		return
	if key.keycode == KEY_BACKSPACE:
		backspace(key.ctrl_pressed or key.alt_pressed)
	elif key.keycode == KEY_SPACE:
		if not key.echo:
			space()
	elif key.unicode > 32 and not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed):
		type_text(char(key.unicode).to_lower())
	else:
		return
	get_viewport().set_input_as_handled()


# ----- Drawing -----


## What word `i` shows: the word, with any extra letters typed past its end.
func _shown(i: int) -> String:
	var attempt := _attempt(i)
	return words[i] + attempt.substr(words[i].length())


## What has been typed for word `i`: all of it once finished, then the
## current word's letters so far, then nothing.
func _attempt(i: int) -> String:
	if i < typed.size():
		return typed[i]
	return current if i == typed.size() else ""


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var space_width := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var line_height := font.get_height(FONT_SIZE) + LINE_GAP
	# Lay the words out in lines that fit, each line centered.
	var lines: Array[Array] = [[]]
	var widths: Array[float] = [0.0]
	for i in words.size():
		var width := font.get_string_size(_shown(i), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var with_space := width + (space_width if not lines[-1].is_empty() else 0.0)
		if not lines[-1].is_empty() and widths[-1] + with_space > size.x - 8:
			lines.append([])
			widths.append(0.0)
			with_space = width
		lines[-1].append(i)
		widths[-1] += with_space
	var y := (size.y - line_height * lines.size()) / 2 + font.get_ascent(FONT_SIZE)
	for line in lines.size():
		var x := (size.x - widths[line]) / 2
		for i: int in lines[line]:
			x = _draw_word(font, i, Vector2(x, y)) + space_width
		y += line_height


## Draws word `i` with its baseline starting at `at`, coloring each letter
## by how it was typed, and returns where it ends.
func _draw_word(font: Font, i: int, at: Vector2) -> float:
	var word := words[i]
	var attempt := _attempt(i)
	var finished := i < typed.size()
	var shown := _shown(i)
	var x := at.x
	var caret := -1.0
	for j in shown.length():
		if i == typed.size() and j == attempt.length():
			caret = x
		var color := UNTYPED_COLOR
		if j >= word.length():
			color = MISS_COLOR.darkened(0.3)
		elif j < attempt.length():
			color = Color.WHITE if attempt[j] == word[j] else MISS_COLOR
		elif finished:
			# Letters skipped by finishing the word early.
			color = MISS_COLOR.darkened(0.4)
		font.draw_string(get_canvas_item(), Vector2(x, at.y), shown[j], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		x += font.get_string_size(shown[j], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if i == typed.size() and caret < 0.0:
		caret = x
	if finished and attempt != word:
		draw_line(Vector2(at.x, at.y + 2), Vector2(x, at.y + 2), MISS_COLOR, 1.0)
	if caret >= 0.0 and not waiting():
		var top := at.y - font.get_ascent(FONT_SIZE)
		draw_line(Vector2(caret, top), Vector2(caret, at.y + 1), GOLD, 1.0)
	return x
