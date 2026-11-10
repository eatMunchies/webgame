class_name ArcadeCheck
extends SkillCheck

## A skill check played on a little arcade field: Flappy Bird, Flappy Golf,
## Fruit Ninja and Blackjack. Each game's model works in field units (FIELD,
## 140 by 100), and this fits the field to whatever room the overlay gives,
## centered and scaled evenly, so a game never has to know the panel's size.
##
## A kind draws after fit_field() and turns taps and swipes into field
## units with to_field().

const FIELD := Vector2(140, 100)
const SKY := Color(0.1, 0.11, 0.18)


## How much the field is scaled to fit.
func field_scale() -> float:
	return maxf(minf(size.x / FIELD.x, size.y / FIELD.y), 0.01)


## Where the field's top left corner sits.
func field_corner() -> Vector2:
	return ((size - FIELD * field_scale()) / 2).floor()


## Draws from here on in field units, over the field's background, and
## clips drawing to the field so things coming in from its edges (pipes,
## thrown fruit) don't show past them.
func fit_field() -> void:
	var item := get_canvas_item()
	RenderingServer.canvas_item_set_custom_rect(item, true, Rect2(field_corner(), FIELD * field_scale()))
	RenderingServer.canvas_item_set_clip(item, true)
	field_transform()
	draw_rect(Rect2(Vector2.ZERO, FIELD), SKY)


## Draws from here on in field units, without painting the background, as
## after drawing something turned or moved with its own transform.
func field_transform() -> void:
	draw_set_transform(field_corner(), 0.0, Vector2.ONE * field_scale())


## A point on the control, like a tap's position, in field units.
func to_field(point: Vector2) -> Vector2:
	return (point - field_corner()) / field_scale()


## Draws text centered on `center`, in field units, outlined so it reads
## over anything.
func draw_centered(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var at := Vector2(center.x - 200, center.y + font.get_ascent(font_size) / 2 - 1)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 400, font_size, 2, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 400, font_size, color)
