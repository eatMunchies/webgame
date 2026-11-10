class_name BlackjackCheck
extends ArcadeCheck

## Blackjack (see BlackjackGame): one hand against the dealer. A win is a
## sure pass, a push is a coin flip and a loss fails, as tuned by a
## BlackjackCheckDef. Under the player's hand it shows the odds that hitting
## busts, from the cards still unseen in the shoe. In practice hands keep
## being dealt and it keeps a record.
##
## H, Left or Space hits; S, Right or Enter stands; or tap the buttons.

const FELT := Color(0.1, 0.36, 0.2)
const CARD_SIZE := Vector2(13, 18)
const CARD_STEP := 9.0
## The buttons fill the bottom of the table, so they're easy to hit with a thumb.
const HIT_RECT := Rect2(6, 82, 62, 15)
const STAND_RECT := Rect2(72, 82, 62, 15)
const OUTCOME_TEXT := {
	"blackjack": "Blackjack!", "win": "You win!", "push": "Push", "lose": "Dealer wins", "bust": "Bust!",
}
## How long a decided hand shows before practice deals the next.
const NEXT_HAND_SECONDS := 1.4

var tuning: BlackjackCheckDef
var game: BlackjackGame
## Practice hands won, pushed and lost.
var wins := 0
var pushes := 0
var losses := 0

var _next_hand_left := 0.0
var _was_over := false


func _ready() -> void:
	tuning = def as BlackjackCheckDef
	if tuning == null:
		tuning = BlackjackCheckDef.new()
	game = BlackjackGame.new(-1, tuning.decks)
	game.deal()
	_check_over()


func hint() -> String:
	return "H, Left or Space hits; S, Right or Enter stands; or tap the buttons. Beat the dealer without going over 21."


func status() -> String:
	return OUTCOME_TEXT.get(game.outcome, "") if game.turn == "over" else ""


func practice_status() -> String:
	return "W%d P%d L%d" % [wins, pushes, losses]


## What a decided hand is worth.
func chance_for(outcome: String) -> float:
	match outcome:
		"blackjack", "win":
			return tuning.win_chance
		"push":
			return tuning.push_chance
	return tuning.lose_chance


func hit() -> void:
	game.hit()
	_check_over()
	changed.emit()


func stand() -> void:
	game.stand()
	changed.emit()


## Reports a hand that's just been decided, or counts it in practice.
func _check_over() -> void:
	var over := game.turn == "over"
	if over and not _was_over:
		_next_hand_left = NEXT_HAND_SECONDS
		if practice:
			match game.outcome:
				"blackjack", "win":
					wins += 1
				"push":
					pushes += 1
				_:
					losses += 1
		else:
			report(chance_for(game.outcome), true)
		changed.emit()
	_was_over = over


func _process(delta: float) -> void:
	game.advance(delta)
	_check_over()
	if game.turn == "over" and practice:
		_next_hand_left -= delta
		if _next_hand_left <= 0.0:
			game.deal()
			_was_over = false
			_check_over()
			changed.emit()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or key.echo:
		return
	match key.physical_keycode:
		KEY_H, KEY_LEFT, KEY_SPACE:
			if key.pressed:
				hit()
		KEY_S, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER:
			if key.pressed:
				stand()
		_:
			return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if is_tap(event):
		var at := to_field(event.position)
		if HIT_RECT.has_point(at):
			hit()
		elif STAND_RECT.has_point(at):
			stand()
		accept_event()


func _draw() -> void:
	fit_field()
	draw_rect(Rect2(Vector2.ZERO, FIELD), FELT)
	var dealer_label := "Dealer %d" % game.dealer_shown_total()
	_draw_label(dealer_label, Vector2(4, 9))
	_draw_hand(game.dealer, Vector2(FIELD.x / 2, 12), game.hole_hidden)
	_draw_label("You %d" % BlackjackGame.total(game.player), Vector2(4, 45))
	_draw_hand(game.player, Vector2(FIELD.x / 2, 48), false)
	if game.turn == "player":
		_draw_label("Hit busts %d%%" % roundi(game.bust_chance() * 100), Vector2(FIELD.x - 52, 45))
		_draw_button(HIT_RECT, "Hit")
		_draw_button(STAND_RECT, "Stand")
	elif game.turn == "over":
		var color := GOLD if game.outcome in ["blackjack", "win"] else (Color.WHITE if game.outcome == "push" else MISS_COLOR)
		draw_centered(OUTCOME_TEXT[game.outcome], Vector2(FIELD.x / 2, 89), 10, color)
	_draw_label("Shoe %d" % game.shoe.size(), Vector2(FIELD.x - 32, 9))


## A hand fanned out, centered on `top_middle`.
func _draw_hand(hand: Array[int], top_middle: Vector2, hide_second: bool) -> void:
	var width := CARD_SIZE.x + CARD_STEP * (hand.size() - 1)
	for i in hand.size():
		var at := Vector2(top_middle.x - width / 2 + CARD_STEP * i, top_middle.y)
		_draw_card(hand[i], at, hide_second and i == 1)


func _draw_card(card: int, at: Vector2, face_down: bool) -> void:
	var rect := Rect2(at, CARD_SIZE)
	if face_down:
		draw_rect(rect, Color(0.55, 0.15, 0.18))
		draw_rect(rect.grow(-1.5), Color(0.8, 0.3, 0.3), false, 0.6)
		draw_rect(rect, Color.BLACK, false, 0.5)
		return
	draw_rect(rect, Color(0.97, 0.95, 0.9))
	draw_rect(rect, Color(0, 0, 0, 0.5), false, 0.5)
	var color := Color(0.8, 0.12, 0.15) if BlackjackGame.is_red(card) else Color(0.1, 0.1, 0.12)
	draw_string(ThemeDB.fallback_font, at + Vector2(1.2, 6.5), BlackjackGame.rank_name(card),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, color)
	# Under the rank, where the next card in the hand doesn't cover it.
	_draw_suit(card / 13 % 4, at + Vector2(4, 11), 2.4, color)


## A suit as a little shape: 0 spades, 1 hearts, 2 diamonds, 3 clubs.
func _draw_suit(suit: int, center: Vector2, r: float, color: Color) -> void:
	match suit:
		1:
			draw_circle(center + Vector2(-r * 0.5, -r * 0.3), r * 0.55, color)
			draw_circle(center + Vector2(r * 0.5, -r * 0.3), r * 0.55, color)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-r * 1.05, -r * 0.1), center + Vector2(r * 1.05, -r * 0.1), center + Vector2(0, r),
			]), color)
		2:
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r * 0.7, 0), center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
			]), color)
		0:
			draw_circle(center + Vector2(-r * 0.5, r * 0.2), r * 0.55, color)
			draw_circle(center + Vector2(r * 0.5, r * 0.2), r * 0.55, color)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-r * 1.05, r * 0.05), center + Vector2(r * 1.05, r * 0.05), center + Vector2(0, -r),
			]), color)
			draw_line(center, center + Vector2(0, r), color, 0.7)
		3:
			draw_circle(center + Vector2(0, -r * 0.45), r * 0.48, color)
			draw_circle(center + Vector2(-r * 0.5, r * 0.15), r * 0.48, color)
			draw_circle(center + Vector2(r * 0.5, r * 0.15), r * 0.48, color)
			draw_line(center, center + Vector2(0, r), color, 0.7)


func _draw_label(text: String, at: Vector2) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.85))


func _draw_button(rect: Rect2, text: String) -> void:
	draw_rect(rect, Color(0.29, 0.21, 0.15))
	draw_rect(rect, GOLD, false, 0.7)
	draw_centered(text, rect.get_center(), 8, Color.WHITE)
