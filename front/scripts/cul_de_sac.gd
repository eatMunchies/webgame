class_name CulDeSac
extends Sprite2D

## The town's ground: grass, a loop of road around a small park, and a road
## coming in from the bottom edge. The park is grass with a paved plaza in the
## middle for the podium and a footpath out to the road on each side. The image
## is painted in code from the sizes below, and lot_position() places the
## houses around the loop from the same numbers, so changing a size keeps the
## road and the houses lined up.
##
## Everything is sized to the 32px characters: the road is about two people
## wide and the plaza holds a crowd of fifteen.
##
## Draw this under everything else (the town scene gives it z_index -2), since
## the yards under each house sit at -1.

const SIZE := Vector2i(456, 360)
const CENTER := Vector2(228, 188)
## The ring of houses: an ellipse through the middle of each house's yard.
const LOT_RADII := Vector2(180, 110)
## How far apart neighbouring lots have to be, across and down. Houses side by
## side need about a yard's width, but houses stacked down the sides of the
## ring only need a yard's depth, so spacing by these instead of by straight
## distance packs the ring tighter.
const LOT_SPACING := Vector2(56, 46)
## How far below the middle of a house's yard its ground point (its node
## origin) is.
const LOT_GROUND_OFFSET := Vector2(0, 13)
## The outside edge of the road loop, the park inside it, and the plaza in the
## middle of the park.
const ROAD_RADII := Vector2(142, 82)
const ISLAND_RADII := Vector2(118, 58)
const PLAZA_RADII := Vector2(36, 22)
const ENTRANCE_WIDTH := 24
const PATH_WIDTH := 8
const CURB := 2

const GRASS := Color(0.45, 0.52, 0.18)
const PARK_GRASS := Color(0.4, 0.56, 0.2)
const ASPHALT := Color(0.32, 0.32, 0.35)
const CURB_COLOR := Color(0.72, 0.71, 0.68)
const PAVING := Color(0.72, 0.66, 0.55)
const CENTER_LINE := Color(0.95, 0.8, 0.25)
const FLOWERS: Array[Color] = [Color(0.93, 0.36, 0.4), Color(0.96, 0.86, 0.35), Color(0.95, 0.95, 0.95), Color(0.6, 0.5, 0.9)]


func _ready() -> void:
	centered = false
	texture = ImageTexture.create_from_image(_paint())


## Returns the ground point of a lot. Lots are numbered clockwise from the
## entrance, so lot 0 is just left of the road in and the last lot is just
## right of it. They're spaced evenly along the ring (as LOT_SPACING measures
## it), with one extra space left empty where the road comes in.
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
			var step := (points[i] - points[i - 1]).abs() / LOT_SPACING
			lengths.append(lengths[i - 1] + maxf(step.x, step.y))
	var target := lengths[STEPS] * (lot + 1) / (lot_count + 1)
	var i := lengths.bsearch(target)
	return points[clampi(i, 0, STEPS)] + LOT_GROUND_OFFSET


func _paint() -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_speckle(image, Rect2i(Vector2i.ZERO, SIZE), GRASS, rng)

	var road_x := int(CENTER.x) - ENTRANCE_WIDTH / 2
	var entrance_top := int(CENTER.y)
	image.fill_rect(Rect2i(road_x - CURB, entrance_top, ENTRANCE_WIDTH + CURB * 2, SIZE.y - entrance_top), CURB_COLOR)
	_fill_ellipse(image, ROAD_RADII, CURB_COLOR)
	_fill_ellipse(image, ROAD_RADII - Vector2(CURB, CURB), ASPHALT)
	# Repaint the entrance without curbs so it opens into the loop.
	image.fill_rect(Rect2i(road_x, entrance_top, ENTRANCE_WIDTH, SIZE.y - entrance_top), ASPHALT)
	for y in range(int(CENTER.y + ROAD_RADII.y) + 4, SIZE.y, 12):
		image.fill_rect(Rect2i(int(CENTER.x) - 1, y, 2, 6), CENTER_LINE)

	_fill_ellipse(image, ISLAND_RADII + Vector2(CURB, CURB), CURB_COLOR)
	_fill_ellipse(image, ISLAND_RADII, PARK_GRASS)
	var park := Rect2i(Vector2i(CENTER - ISLAND_RADII), Vector2i(ISLAND_RADII * 2))
	_speckle(image, park, PARK_GRASS, rng, func(x, y): return _inside(Vector2(x, y), ISLAND_RADII - Vector2(1, 1)))
	_plant_flowers(image, rng)
	# Footpaths from the plaza out to the curb on all four sides.
	var half_path := PATH_WIDTH / 2
	image.fill_rect(Rect2i(int(CENTER.x - ISLAND_RADII.x), int(CENTER.y) - half_path, int(ISLAND_RADII.x * 2), PATH_WIDTH), PAVING)
	image.fill_rect(Rect2i(int(CENTER.x) - half_path, int(CENTER.y - ISLAND_RADII.y), PATH_WIDTH, int(ISLAND_RADII.y * 2)), PAVING)
	_fill_ellipse(image, PLAZA_RADII + Vector2(1, 1), PAVING.darkened(0.25))
	_fill_ellipse(image, PLAZA_RADII, PAVING, func(x, y): return x % 6 == 0 or y % 6 == 0)
	return image


## Scatters lighter and darker pixels over grass so it doesn't look flat.
## When given, keep(x, y) limits them to some of the pixels in the area.
func _speckle(image: Image, area: Rect2i, color: Color, rng: RandomNumberGenerator, keep := Callable()) -> void:
	for i in area.get_area() / 40:
		var x := rng.randi_range(area.position.x, area.end.x - 1)
		var y := rng.randi_range(area.position.y, area.end.y - 1)
		if not keep.is_valid() or keep.call(x, y):
			image.set_pixel(x, y, color.lightened(0.12) if i % 2 else color.darkened(0.12))


## Dots small clumps of flowers around the park, clear of the plaza and paths.
func _plant_flowers(image: Image, rng: RandomNumberGenerator) -> void:
	var planted := 0
	while planted < 18:
		var spot := Vector2i(rng.randi_range(0, SIZE.x - 1), rng.randi_range(0, SIZE.y - 1))
		var offset := Vector2(spot) - CENTER
		var clear_of_paths := absf(offset.x) > PATH_WIDTH and absf(offset.y) > PATH_WIDTH
		if not _inside(Vector2(spot), ISLAND_RADII - Vector2(5, 5)) or _inside(Vector2(spot), PLAZA_RADII + Vector2(5, 5)) or not clear_of_paths:
			continue
		var color: Color = FLOWERS[planted % FLOWERS.size()]
		for petal: Vector2i in [Vector2i(0, 0), Vector2i(2, 1), Vector2i(-1, 2)]:
			image.set_pixelv(spot + petal, color)
			image.set_pixelv(spot + petal + Vector2i(0, 1), PARK_GRASS.darkened(0.3))
		planted += 1


## Whether a point is inside an ellipse around CENTER.
static func _inside(point: Vector2, radii: Vector2) -> bool:
	var d := (point + Vector2(0.5, 0.5) - CENTER) / radii
	return d.length_squared() < 1.0


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
