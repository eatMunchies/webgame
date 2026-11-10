class_name MemoryCheck
extends SkillCheck

## Card Memory: a 4x4 board of face-down cards to pair up (see MemoryGame).
## It is a practice game only, one of the MinigameOverlay's
## `practice_checks`, so it never reports a chance; skill checks that count
## are the overlay's `skill_checks`.
##
## The overlay keeps the night's practice game from stage to stage, so a
## Card Memory carries on with the same board until a skill check or fight
## interrupts it.
##
## Tap a card to turn it, or move with the arrow keys and press Space.

const MATCH_COLOR := Color(0.45, 0.85, 0.45)
const CARD_BACK := Color(0.29, 0.21, 0.15)
const CARD_FACE := Color(0.93, 0.87, 0.74)
## One color per card face, so a pair reads at a glance even when tiny.
const FACE_COLORS: Array[Color] = [
	Color(0.85, 0.2, 0.25), Color(0.2, 0.45, 0.9), Color(0.15, 0.65, 0.3), Color(0.9, 0.65, 0.1),
	Color(0.6, 0.3, 0.85), Color(0.95, 0.45, 0.15), Color(0.1, 0.7, 0.75), Color(0.9, 0.35, 0.65),
]
const ARROW_STEPS := {
	KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT, KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN,
}
## How long a match or miss flashes the turned cards' borders, in seconds.
const FLASH_SECONDS := 0.25

var game := MemoryGame.new()

var _flash := 0.0
var _flash_color := MATCH_COLOR


func _init() -> void:
	practice = true


func title() -> String:
	return def.title if def != null else "Card Memory"


func hint() -> String:
	return "Tap two cards to turn them, or move with the arrow keys and press Space. Find the pairs."


## Turns over a card: the first of a try, or the second, which flashes green
## for a pair and red for a miss.
func pick_card(card: int) -> void:
	var outcome := game.pick(card)
	if outcome == "match" or outcome == "miss":
		_flash = FLASH_SECONDS
		_flash_color = MATCH_COLOR if outcome == "match" else MISS_COLOR
	changed.emit()


func _process(delta: float) -> void:
	game.advance(delta)
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_visible_in_tree() or key == null or key.echo:
		return
	if key.physical_keycode == KEY_SPACE:
		if key.pressed:
			pick_card(game.cursor)
	elif ARROW_STEPS.has(key.physical_keycode):
		if key.pressed:
			game.move_cursor(ARROW_STEPS[key.physical_keycode])
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if is_tap(event):
		var card := card_at(event.position)
		if card >= 0:
			pick_card(card)
		accept_event()


## Where a card is drawn: the board fills the height, centered, with cards a
## little taller than wide. Cards are at least a pixel, so the rects stay
## valid before the first layout.
func card_rect(card: int) -> Rect2:
	const GAP := 2.0
	var cols := MemoryGame.COLUMNS
	var rows := MemoryGame.ROWS
	var height := maxf(floorf((size.y - GAP * (rows - 1)) / rows), 1.0)
	var width := maxf(minf(floorf((size.x - GAP * (cols - 1)) / cols), floorf(height * 0.8)), 1.0)
	var board := Vector2(width * cols + GAP * (cols - 1), height * rows + GAP * (rows - 1))
	var corner := ((size - board) / 2).floor()
	var cell := Vector2(card % cols, card / cols)
	return Rect2(corner + cell * Vector2(width + GAP, height + GAP), Vector2(width, height))


## The card under a point, or -1.
func card_at(point: Vector2) -> int:
	for card in MemoryGame.CARDS:
		if card_rect(card).has_point(point):
			return card
	return -1


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for card in MemoryGame.CARDS:
		var rect := card_rect(card)
		if game.face_up(card):
			draw_rect(rect, CARD_FACE.darkened(0.35) if game.matched[card] else CARD_FACE)
			_draw_face(game.faces[card], rect.get_center(), minf(rect.size.x, rect.size.y) * 0.3)
		else:
			draw_rect(rect, CARD_BACK)
			draw_rect(rect.grow(-2), GOLD.darkened(0.45), false, 1.0)
		var border := Color(0, 0, 0, 0.6)
		if game.missed() and game.turned.has(card):
			border = MISS_COLOR
		elif game.matched[card] and _flash > 0.0:
			border = _flash_color
		draw_rect(rect, border, false, 1.0)
		if card == game.cursor and not game.peeking():
			draw_rect(rect.grow(1), Color.WHITE, false, 1.0)
	if game.peeking():
		var text := "Memorize! %d" % ceili(game.peek_left())
		var at := Vector2(0, size.y / 2 + 3)
		draw_rect(Rect2(0, size.y / 2 - 7, size.x, 13), Color(0.06, 0.06, 0.1, 0.85))
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, 3, Color(0, 0, 0, 0.85))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, GOLD)


## Draws one of the eight card faces: a different colored shape each, so
## pairs can be told apart by shape as well as color.
func _draw_face(face: int, center: Vector2, radius: float) -> void:
	var color: Color = FACE_COLORS[face]
	match face:
		0:
			draw_circle(center, radius, color)
		1:
			draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2), color)
		2:
			draw_colored_polygon(_polygon(center, radius * 1.15, 3, -PI / 2), color)
		3:
			draw_colored_polygon(_polygon(center, radius * 1.15, 4, -PI / 2), color)
		4:
			draw_colored_polygon(_star(center, radius * 1.2), color)
		5:
			draw_rect(Rect2(center - Vector2(radius, radius * 0.35), Vector2(radius * 2, radius * 0.7)), color)
			draw_rect(Rect2(center - Vector2(radius * 0.35, radius), Vector2(radius * 0.7, radius * 2)), color)
		6:
			draw_arc(center, radius * 0.8, 0, TAU, 16, color, maxf(radius * 0.45, 1.5))
		7:
			draw_colored_polygon(_polygon(center, radius * 1.1, 6, 0), color)


## A regular polygon's points around `center`.
func _polygon(center: Vector2, radius: float, sides: int, start: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(center + Vector2.from_angle(start + TAU * i / sides) * radius)
	return points


## A five-pointed star's points around `center`.
func _star(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var reach := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2.from_angle(-PI / 2 + TAU * i / 10) * reach)
	return points
