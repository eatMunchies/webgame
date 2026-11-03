class_name MemoryGame
extends RefCounted

## The practice game: a 4x4 board of face-down cards, eight pairs. The board
## is shown face up for a moment, then turned over, and the player turns two
## cards at a time looking for pairs. A pair stays up; two cards that don't
## match are shown briefly and turned back. Finding every pair deals a new
## board.
##
## Only practice rounds use it, the ones with nothing riding on them, so it
## never reports anything to the server. Skill checks keep the TimingWheel,
## whose odds the server counts on.
##
## Cards are numbered 0 to 15 left to right, top to bottom. A card's face is
## a number from 0 to 7, and the two cards of a pair share it.

const COLUMNS := 4
const ROWS := 4
const CARDS := COLUMNS * ROWS
## How long a new board stays face up to be memorized, in seconds.
const PEEK_SECONDS := 2.0
## How long two cards that don't match stay face up.
const MISS_SECONDS := 0.7
## How long a finished board stays up before the next one is dealt.
const CLEARED_SECONDS := 0.8

## Each card's face.
var faces: Array[int] = []
## Whether each card's pair has been found.
var matched: Array[bool] = []
## The cards turned up by the player and not yet matched, at most two.
var turned: Array[int] = []
## The card the keyboard cursor is on.
var cursor := 0
## Pairs found over every board, the practice score.
var pairs_found := 0
## Boards finished.
var boards_cleared := 0

var _peek_left := 0.0
var _miss_left := 0.0
var _cleared_left := 0.0
var _rng := RandomNumberGenerator.new()


## A seed of -1 picks a random one.
func _init(seed_value := -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	deal()


## Lays out a fresh shuffled board, face up for the peek.
func deal() -> void:
	faces = []
	for face in CARDS / 2:
		faces.append_array([face, face])
	# Fisher-Yates with our own RNG, so a seed always deals the same board.
	for i in range(CARDS - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := faces[i]
		faces[i] = faces[j]
		faces[j] = swap
	matched = []
	matched.resize(CARDS)
	matched.fill(false)
	turned = []
	_peek_left = PEEK_SECONDS
	_miss_left = 0.0
	_cleared_left = 0.0


func advance(delta: float) -> void:
	_peek_left = maxf(_peek_left - delta, 0.0)
	if _miss_left > 0.0:
		_miss_left -= delta
		if _miss_left <= 0.0:
			turned = []
	if _cleared_left > 0.0:
		_cleared_left -= delta
		if _cleared_left <= 0.0:
			deal()


## Whether the board is still being shown before play starts.
func peeking() -> bool:
	return _peek_left > 0.0


## Seconds left to memorize the board.
func peek_left() -> float:
	return _peek_left


## Whether two cards that didn't match are showing.
func missed() -> bool:
	return _miss_left > 0.0


## Whether every pair on this board has been found.
func cleared() -> bool:
	return not matched.has(false)


func face_up(card: int) -> bool:
	return peeking() or matched[card] or turned.has(card) or _cleared_left > 0.0


## Turns a card over. Returns "turned" for the first card of a try, "match"
## or "miss" for the second, or "" when the card can't be turned now (during
## the peek, or a card already up). Picking while a miss is showing turns
## the missed pair back straight away, so play never has to wait.
func pick(card: int) -> String:
	if card < 0 or card >= CARDS or peeking() or _cleared_left > 0.0:
		return ""
	if missed():
		_miss_left = 0.0
		turned = []
	if matched[card] or turned.has(card):
		return ""
	cursor = card
	turned.append(card)
	if turned.size() < 2:
		return "turned"
	if faces[turned[0]] != faces[turned[1]]:
		_miss_left = MISS_SECONDS
		return "miss"
	for up in turned:
		matched[up] = true
	turned = []
	pairs_found += 1
	if cleared():
		boards_cleared += 1
		_cleared_left = CLEARED_SECONDS
	return "match"


## Moves the keyboard cursor by whole cards, stopping at the board's edges.
func move_cursor(step: Vector2i) -> void:
	var column := clampi(cursor % COLUMNS + step.x, 0, COLUMNS - 1)
	var row := clampi(cursor / COLUMNS + step.y, 0, ROWS - 1)
	cursor = row * COLUMNS + column
