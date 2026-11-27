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
const UNTYPED_COLOR := SIM_FAINT
## Shown under the words on a touch screen until the first letter is typed.
const TAP_TO_TYPE := "tap here to type"

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
## On a touch screen, an invisible text box in the test that takes the
## on-screen keyboard (see _notification).
var _keys: LineEdit


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


## On a touch screen there's no keyboard to press keys on, so an invisible
## text box in the test takes the on-screen keyboard while the test shows,
## and every change typed into it comes here as keys would. The HUD moves the
## minigame to the top of a tall screen meanwhile (Session.keyboard_minigame),
## above the keyboard. A tap on the test brings the keyboard back if it was
## put away. An iPhone won't open the keyboard for a box that takes focus on
## its own, only during a tap (the web page's head_include script focuses
## Godot's text box again as the finger lifts), so until the first letter
## the test says to tap it.
func _notification(what: int) -> void:
	if not TextPrompt.touch:
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		if is_visible_in_tree():
			_take_keyboard.call_deferred()
		else:
			_give_up_keyboard()
	elif what == NOTIFICATION_EXIT_TREE:
		_give_up_keyboard()


func _take_keyboard() -> void:
	if not is_visible_in_tree():
		return
	if _keys == null:
		_keys = LineEdit.new()
		# Drawn by nobody, and in nobody's way; it only takes the keyboard.
		_keys.self_modulate.a = 0.0
		_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keys.custom_minimum_size = Vector2.ZERO
		_keys.size = Vector2(1, 1)
		_keys.add_theme_font_size_override("font_size", 1)
		_keys.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_keys.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_keys.text_changed.connect(func(text: String) -> void: _sync_keys(_on_prompt_text(text)))
		_keys.text_submitted.connect(func(text: String) -> void: _sync_keys(_on_prompt_text(text + " ")))
		add_child(_keys)
	_keys.text = current
	_keys.grab_focus()
	Session.set_keyboard_minigame(true)


func _give_up_keyboard() -> void:
	if _keys != null and _keys.is_inside_tree():
		_keys.release_focus()
	if Session.keyboard_minigame:
		Session.set_keyboard_minigame(false)


func _sync_keys(text: String) -> void:
	if _keys.text != text:
		_keys.text = text
		_keys.caret_column = text.length()


func _gui_input(event: InputEvent) -> void:
	if _keys != null and is_tap(event):
		# Taking focus again asks for the keyboard again, even when Godot's
		# box still has focus but the phone put its keyboard away.
		_keys.release_focus()
		_keys.grab_focus()
		accept_event()


## Takes what the invisible box holds: the word being typed, and a space
## (or Enter) after it to finish it. Returns what the box should hold now:
## the rest of the word being typed.
func _on_prompt_text(text: String) -> String:
	var parts := text.split(" ")
	for i in parts.size():
		var word := parts[i]
		if word != current:
			if word.begins_with(current):
				type_text(word.substr(current.length()))
			else:
				backspace(true)
				type_text(word)
		if i < parts.size() - 1:
			space()
	changed.emit()
	return current


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
	draw_words_on(self, size)
	if TextPrompt.touch and typed.is_empty() and current == "":
		var font := Fonts.MONO
		var y := size.y - LINE_GAP - font.get_descent(FONT_SIZE)
		draw_string(font, Vector2(0, y), TAP_TO_TYPE, HORIZONTAL_ALIGNMENT_CENTER, size.x,
				FONT_SIZE, UNTYPED_COLOR)


## Draws the words on `canvas`, laid out to fit `area`.
func draw_words_on(canvas: CanvasItem, area: Vector2) -> void:
	var font := Fonts.MONO
	var space_width := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var line_height := font.get_height(FONT_SIZE) + LINE_GAP
	# Lay the words out in lines that fit, each line centered.
	var lines: Array[Array] = [[]]
	var widths: Array[float] = [0.0]
	for i in words.size():
		var width := font.get_string_size(_shown(i), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var with_space := width + (space_width if not lines[-1].is_empty() else 0.0)
		if not lines[-1].is_empty() and widths[-1] + with_space > area.x - 8:
			lines.append([])
			widths.append(0.0)
			with_space = width
		lines[-1].append(i)
		widths[-1] += with_space
	var y := (area.y - line_height * lines.size()) / 2 + font.get_ascent(FONT_SIZE)
	for line in lines.size():
		var x := (area.x - widths[line]) / 2
		for i: int in lines[line]:
			x = _draw_word(canvas, font, i, Vector2(x, y)) + space_width
		y += line_height


## Draws word `i` with its baseline starting at `at`, coloring each letter
## by how it was typed, and returns where it ends.
func _draw_word(canvas: CanvasItem, font: Font, i: int, at: Vector2) -> float:
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
			color = SIM_TEXT if attempt[j] == word[j] else MISS_COLOR
		elif finished:
			# Letters skipped by finishing the word early.
			color = MISS_COLOR.darkened(0.4)
		font.draw_string(canvas.get_canvas_item(), Vector2(x, at.y), shown[j], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		x += font.get_string_size(shown[j], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if i == typed.size() and caret < 0.0:
		caret = x
	if finished and attempt != word:
		canvas.draw_line(Vector2(at.x, at.y + 2), Vector2(x, at.y + 2), MISS_COLOR, 1.0)
	if caret >= 0.0 and not waiting():
		var top := at.y - font.get_ascent(FONT_SIZE)
		canvas.draw_line(Vector2(caret, top), Vector2(caret, at.y + 1), GOLD, 1.0)
	return x
