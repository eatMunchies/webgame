class_name NumberBadge
extends RefCounted

## A player's number in a colored circle, white on the color, so a player is
## easy to spot in the roster and the chat. Each seat has its own color, the
## same everywhere. The badges are pixel art drawn in code (a 3x5 digit font
## on a 9 pixel tall circle, or a pill for two digits), made once per number
## and kept.

## Each seat's color, by lot (number - 1).
const COLORS: Array[Color] = [
	Color("#d04848"), Color("#e07b2a"), Color("#c9a227"), Color("#5f9e3a"),
	Color("#2f9e8f"), Color("#3a7bd5"), Color("#6a5acd"), Color("#a64ac9"),
	Color("#d0508f"), Color("#8a6a3f"), Color("#4f8a8b"), Color("#7a8f2a"),
	Color("#b5563c"), Color("#5b6b9e"), Color("#9e4f6e"),
]
const HEIGHT := 9
const DIGIT := Color(1, 1, 1)
## The digits 0 to 9, 3 pixels wide and 5 tall, row by row.
const FONT := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001010010010",
	"111101111101111", "111101111001111",
]

static var _cache := {}


## The badge for player `number` (from 1).
static func texture(number: int) -> Texture2D:
	if _cache.has(number):
		return _cache[number]
	var digits := str(number)
	var text_width := digits.length() * 4 - 1
	var width := maxi(HEIGHT, text_width + 4)
	var image := Image.create_empty(width, HEIGHT, false, Image.FORMAT_RGBA8)
	var color: Color = COLORS[(number - 1) % COLORS.size()]
	var radius := HEIGHT / 2.0
	for y in HEIGHT:
		for x in width:
			# A circle, stretched into a pill when two digits need the room.
			var cx := clampf(x + 0.5, radius, width - radius)
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, radius)) <= radius:
				image.set_pixel(x, y, color)
	var left := (width - text_width) / 2
	for i in digits.length():
		var glyph: String = FONT[int(digits[i])]
		for row in 5:
			for column in 3:
				if glyph[row * 3 + column] == "1":
					image.set_pixel(left + i * 4 + column, 2 + row, DIGIT)
	var made := ImageTexture.create_from_image(image)
	_cache[number] = made
	return made
