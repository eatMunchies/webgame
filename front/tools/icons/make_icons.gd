extends SceneTree

## Draws the UI's woodcut icon set and saves each as a 16x16 PNG in
## assets/sprites/ui/icons/, white on transparent: the UI tints them (ink on
## parchment, the machine's colors on the system layer). Run it after editing
## an icon below:
##
##     godot --headless --path front --script res://tools/icons/make_icons.gd
##
## Each icon is drawn here as text, '#' for ink and '.' for nothing, and is
## centered on the 16x16 grid. The style is a woodcut's: bold strokes, no
## antialiasing, one color. An artist can redraw any PNG in Pixelorama; this
## script will then overwrite it, so remove that icon from ICONS once it's
## drawn by hand.

const OUT := "res://assets/sprites/ui/icons"

const ICONS := {
	# The last will: a page with a quill across it.
	"will": [
		"..........###",
		".........####",
		"........####.",
		"#######.###..",
		"#.....####...",
		"#....####..#.",
		"#...####...#.",
		"#..####....#.",
		"#..###.....#.",
		"#.##.......#.",
		"##.###.##..#.",
		"#..........#.",
		"#.#####.##.#.",
		"#..........#.",
		"############.",
	],
	# Your role: an identity paper with a portrait and lines.
	"role": [
		"################",
		"#..............#",
		"#.####.........#",
		"#.#..#.#######.#",
		"#.#..#.........#",
		"#.####.#####...#",
		"#.#..#.........#",
		"#.####.######..#",
		"#..............#",
		"################",
	],
	# A whisper: a speech curl with dots.
	"whisper": [
		"..#########..",
		".#.........#.",
		"#...........#",
		"#..#..#..#..#",
		"#...........#",
		".#.........#.",
		"..####..###..",
		"......#.#....",
		"......##.....",
		"......#......",
	],
	# A vote: a ballot going into a box.
	"vote": [
		"...######....",
		"...#....#....",
		"...#.##.#....",
		"...#....#....",
		"#############",
		"#...........#",
		"#..#######..#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#############",
	],
	# The chat: a rolled scroll with lines.
	"chat": [
		".###########..",
		"#.#........#..",
		"#.#.######.#..",
		".##........#..",
		"..#.######.#..",
		"..#........#..",
		"..#.#####..#..",
		"..#........#.#",
		"..##########.#",
		"...#.........#",
		"...###########",
	],
	# Dead: a skull.
	"dead": [
		"..########..",
		".#........#.",
		"#..........#",
		"#..........#",
		"#.###..###.#",
		"#.###..###.#",
		"#..........#",
		".#...##...#.",
		"..#......#..",
		"..#.#.#.#...",
		"..########..",
	],
	# Day: the sun.
	"day": [
		"......#......",
		"..#...#...#..",
		"...#.....#...",
		".....###.....",
		"....#####....",
		"###.#####.###",
		"....#####....",
		".....###.....",
		"...#.....#...",
		"..#...#...#..",
		"......#......",
	],
	# Night: a crescent moon.
	"night": [
		"...#####....",
		".###........",
		".##.........",
		"###.........",
		"###.........",
		"###.........",
		"###.........",
		".###.......#",
		".####.....##",
		"..#########.",
		"....#####...",
	],
	# Time: an hourglass.
	"time": [
		"##########",
		"#........#",
		".#......#.",
		"..#....#..",
		"...#..#...",
		"....##....",
		"...#..#...",
		"..#.##.#..",
		".#.####.#.",
		"#.######.#",
		"##########",
	],
	# The host: a crown.
	"host": [
		"#...#...#",
		"##.###.##",
		"#########",
		"#.#.#.#.#",
		"#########",
		"#########",
	],
	# Customize: a Puritan's capotain hat.
	"customize": [
		"....######....",
		"....#....#....",
		"....#....#....",
		"....#....#....",
		"...########...",
		"...#......#...",
		"##############",
		".############.",
	],
	# Paste: a clipboard.
	"paste": [
		"...####...",
		"###....###",
		"#..####..#",
		"#........#",
		"#.######.#",
		"#........#",
		"#.####...#",
		"#........#",
		"#.######.#",
		"#........#",
		"##########",
	],
	# Copy: one page over another.
	"copy": [
		"######....",
		"#....#....",
		"#.######..",
		"#.#....#..",
		"#.#.##.#..",
		"#.#....#..",
		"###.##.#..",
		"..#....#..",
		"..######..",
	],
	# Leave: out through the door.
	"leave": [
		"#######......",
		"#.....#......",
		"#.....#......",
		"#..#..#...#..",
		"#.....#.#####",
		"#.....#...#..",
		"#.....#......",
		"#######......",
	],
	# Close: an ink cross.
	"close": [
		"##......##",
		"###....###",
		".###..###.",
		"..######..",
		"...####...",
		"..######..",
		".###..###.",
		"###....###",
		"##......##",
	],
	# Send: a sealed letter.
	"send": [
		"##############",
		"##..........##",
		"#.#........#.#",
		"#..#......#..#",
		"#...#.##.#...#",
		"#....####....#",
		"#.....##.....#",
		"#............#",
		"##############",
	],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for icon: String in ICONS:
		var rows: Array = ICONS[icon]
		var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		var width := 0
		for row: String in rows:
			width = maxi(width, row.length())
		var left := (16 - width) / 2
		var top := (16 - rows.size()) / 2
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					image.set_pixel(left + x, top + y, Color.WHITE)
		image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, icon]))
	print("Drew %d icons in %s" % [ICONS.size(), OUT])
	quit()
