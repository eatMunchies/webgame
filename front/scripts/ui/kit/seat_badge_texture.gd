class_name SeatBadgeTexture
extends Texture2D

## A SeatBadge as a texture, drawn with the font at whatever size it's shown,
## so it stays sharp at any screen scale. For places that take a texture
## rather than a Control: the chat puts one before each player's line.

var number := 1
var height := SeatBadge.HEIGHT


func _init(seat := 1, tall := SeatBadge.HEIGHT) -> void:
	number = seat
	height = tall


func _get_width() -> int:
	return ceili(SeatBadge.width_for(number, height))


func _get_height() -> int:
	return ceili(height)


func _draw(to_canvas_item: RID, pos: Vector2, _modulate: Color, _transpose: bool) -> void:
	SeatBadge.paint(to_canvas_item, Rect2(pos, Vector2(_get_width(), _get_height())), number)


func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, _modulate: Color, _transpose: bool) -> void:
	SeatBadge.paint(to_canvas_item, rect, number)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, _modulate: Color,
		_transpose: bool, _clip_uv: bool) -> void:
	SeatBadge.paint(to_canvas_item, rect, number)
