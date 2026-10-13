class_name CulDeSac
extends Sprite2D

## The town's ground: grass, a loop of road around a paved island, and a road
## coming in from the bottom edge. The image is painted in code from the sizes
## below, and lot_position() places the houses around the loop from the same
## numbers, so changing a size keeps the road and the houses lined up.
##
## Draw this under everything else (the town scene gives it z_index -2), since
## the yards under each house sit at -1.

const SIZE := Vector2i(640, 480)
const CENTER := Vector2(320, 236)
## The ring of houses: an ellipse through the middle of each house.
const LOT_RADII := Vector2(250, 168)
## How far below a house's middle its ground point (its node origin) is.
const LOT_GROUND_OFFSET := Vector2(0, 32)
## The outside edge of the road loop, and the paved island inside it.
const ROAD_RADII := Vector2(184, 100)
const ISLAND_RADII := Vector2(156, 74)
const ENTRANCE_WIDTH := 32
const CURB := 2

const GRASS := Color(0.45, 0.52, 0.18)
const ASPHALT := Color(0.32, 0.32, 0.35)
const CURB_COLOR := Color(0.72, 0.71, 0.68)
const PAVING := Color(0.72, 0.66, 0.55)
const CENTER_LINE := Color(0.95, 0.8, 0.25)


func _ready() -> void:
	centered = false
	texture = ImageTexture.create_from_image(_paint())


## Returns the ground point of a lot. Lots are numbered clockwise from the
## entrance, so lot 0 is just left of the road in and the last lot is just
## right of it. They're spaced evenly along the ring, with one extra space
## left empty where the road comes in.
static func lot_position(lot: int, lot_count: int) -> Vector2:
	# Walk around the ring in small steps, measuring as we go, and stop once
	# we've covered this lot's share of the distance.
	const STEPS := 720
	var points: Array[Vector2] = []
	var lengths: Array[float] = [0.0]
	for i in STEPS + 1:
		var angle := TAU * i / STEPS
		# Angle 0 is the bottom of the ring; growing angles go clockwise.
		points.append(CENTER + Vector2(-LOT_RADII.x * sin(angle), LOT_RADII.y * cos(angle)))
		if i > 0:
			lengths.append(lengths[i - 1] + points[i].distance_to(points[i - 1]))
	var target := lengths[STEPS] * (lot + 1) / (lot_count + 1)
	var i := lengths.bsearch(target)
	return points[clampi(i, 0, STEPS)] + LOT_GROUND_OFFSET


func _paint() -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in SIZE.x * SIZE.y / 40:
		var spot := Vector2i(rng.randi_range(0, SIZE.x - 1), rng.randi_range(0, SIZE.y - 1))
		image.set_pixelv(spot, GRASS.lightened(0.12) if i % 2 else GRASS.darkened(0.12))

	var road_x := int(CENTER.x) - ENTRANCE_WIDTH / 2
	var entrance_top := int(CENTER.y)
	image.fill_rect(Rect2i(road_x - CURB, entrance_top, ENTRANCE_WIDTH + CURB * 2, SIZE.y - entrance_top), CURB_COLOR)
	_fill_ellipse(image, ROAD_RADII, CURB_COLOR)
	_fill_ellipse(image, ROAD_RADII - Vector2(CURB, CURB), ASPHALT)
	# Repaint the entrance without curbs so it opens into the loop.
	image.fill_rect(Rect2i(road_x, entrance_top, ENTRANCE_WIDTH, SIZE.y - entrance_top), ASPHALT)
	_fill_ellipse(image, ISLAND_RADII + Vector2(CURB, CURB), CURB_COLOR)
	_fill_ellipse(image, ISLAND_RADII, PAVING, func(x, y): return x % 8 == 0 or y % 8 == 0)

	for y in range(int(CENTER.y + ROAD_RADII.y), SIZE.y, 12):
		image.fill_rect(Rect2i(int(CENTER.x) - 1, y, 2, 6), CENTER_LINE)
	return image


## Fills an ellipse around CENTER one row at a time. When given, grout(x, y)
## picks pixels inside it to draw a shade darker, for a paving pattern.
func _fill_ellipse(image: Image, radii: Vector2, color: Color, grout := Callable()) -> void:
	for y in range(int(CENTER.y - radii.y), int(CENTER.y + radii.y) + 1):
		var dy := (y + 0.5 - CENTER.y) / radii.y
		if absf(dy) >= 1.0:
			continue
		var half_width := radii.x * sqrt(1.0 - dy * dy)
		var x0 := roundi(CENTER.x - half_width)
		var x1 := roundi(CENTER.x + half_width)
		image.fill_rect(Rect2i(x0, y, x1 - x0, 1), color)
		if grout.is_valid():
			for x in range(x0, x1):
				if grout.call(x, y):
					image.set_pixel(x, y, color.darkened(0.1))
