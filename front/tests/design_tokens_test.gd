extends GdUnitTestSuite

## The design system's promises (docs/DESIGN.md): every ink you read is
## readable on the paper it's on, by day and by candlelight; the machine's
## text reads on its glass; seat numerals read on their dyes; the fonts load
## with the letters the game prints; and both themes define every style.

## Inks that text is set in, on parchment.
const PAPER_TEXT := {
	"ink": Tokens.INK, "secondary": Tokens.INK_SECONDARY, "faint": Tokens.INK_FAINT,
	"you": Tokens.YOU, "dead": Tokens.DEAD, "safe": Tokens.SAFE, "danger": Tokens.DANGER,
	"town": Tokens.FACTION_TOWN, "mafia": Tokens.FACTION_MAFIA, "neutral": Tokens.FACTION_NEUTRAL,
	"wax": Tokens.WAX,
}
const READABLE := 4.5


func after_test() -> void:
	Tokens.use_night(false)


func test_day_and_night_change_the_same_things() -> void:
	assert_array(Palette.DAY.keys()).contains_exactly_in_any_order(Palette.NIGHT.keys())


func test_text_inks_read_on_paper_by_day_and_night() -> void:
	for night in [false, true]:
		Tokens.use_night(night)
		for paper: Color in [Tokens.paper_surface, Tokens.paper_raised]:
			for ink_name: String in PAPER_TEXT:
				var ratio := contrast(PAPER_TEXT[ink_name], paper)
				assert_float(ratio).override_failure_message(
						"%s on %s paper %s is %.2f" % [ink_name, "night" if night else "day", paper.to_html(false), ratio]
				).is_greater_equal(READABLE)


func test_the_machine_text_reads_on_its_glass() -> void:
	for color: Color in [Tokens.SYS_TEXT, Tokens.SYS_DIM, Tokens.SYS_ACCENT, Tokens.SYS_FAULT,
			Tokens.LOG_SAID, Tokens.LOG_WHISPER, Tokens.LOG_GAME, Tokens.LOG_MACHINE]:
		assert_float(contrast(color, Tokens.SYS_BG)).is_greater_equal(READABLE)


func test_seat_numerals_read_on_their_dyes() -> void:
	# Numerals are bold, so large-text contrast would do; ask a little more.
	for n in range(1, 16):
		assert_float(contrast(Tokens.INK_ON_DARK, Tokens.seat(n))).is_greater_equal(4.3)


func test_fonts_have_the_letters_the_game_prints() -> void:
	var needed := "0123456789:/.,!?'()-" + Session.CODE_ALPHABET + "abcdefghijklmnopqrstuvwxyz"
	for font: FontFile in [Fonts.TITLE, Fonts.HEADING, Fonts.BODY, Fonts.BODY_BOLD, Fonts.MONO]:
		for letter in needed:
			assert_bool(font.has_char(letter.unicode_at(0))).override_failure_message(
					"%s lacks '%s'" % [font.resource_path.get_file(), letter]).is_true()


func test_themes_define_every_style() -> void:
	var paper := UiTheme.paper()
	for variation in ["Title", "Heading", "Body", "Caption", "Dim"]:
		assert_bool(paper.has_font_size("font_size", variation)).is_true()
	for variation in ["WaxButton", "QuietButton", "IconButton"]:
		assert_bool(paper.has_stylebox("normal", variation)).is_true()
	var system := UiTheme.system()
	for variation in ["Title", "Heading", "Mono", "Accent", "Caption", "Dim"]:
		assert_bool(system.has_font_size("font_size", variation)).is_true()
	assert_bool(system.has_stylebox("normal", "SysPrimary")).is_true()


func test_night_rebuilds_the_paper_theme() -> void:
	var day := UiTheme.paper()
	Tokens.use_night(true)
	assert_object(UiTheme.paper()).is_not_same(day)


static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var channel := func(v: float) -> float:
		return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * channel.call(c.r) + 0.7152 * channel.call(c.g) + 0.0722 * channel.call(c.b)


## UI scripts take their colors from Tokens, not literals (DESIGN.md). The
## few literals left are the game's content or tints, not UI colors.
const LITERAL_ALLOWED := {
	# Multipliers on the town's art, not colors of their own.
	"scripts/lobby.gd": ["DOOR_GLOW"],
	"scripts/town.gd": ["DEAD_HOUSE_COLOR"],
	# Skin tones a character can have.
	"scripts/wardrobe.gd": ["Color(1.0, 0.87", "Color(0.68, 0.48", "Color(0.6, 0.85"],
}
const UI_SCRIPTS := ["scripts/hud", "scripts/ui/kit", "scripts/ui/text_prompt.gd",
		"scripts/minigame", "scripts/lobby.gd", "scripts/town.gd", "scripts/wardrobe.gd",
		"scripts/customizer.gd"]


func test_ui_scripts_take_colors_from_tokens() -> void:
	var literal := RegEx.create_from_string("Color\\(\\s*[0-9.]")
	var found: Array[String] = []
	var scripts := _scripts(UI_SCRIPTS)
	assert_int(scripts.size()).is_greater(20)
	for path in scripts:
		var allowed: Array = LITERAL_ALLOWED.get(path, [])
		var lines := FileAccess.get_file_as_string("res://" + path).split("\n")
		for i in lines.size():
			var line := lines[i]
			if literal.search(line) == null or line.strip_edges().begins_with("#"):
				continue
			if allowed.any(func(mark: String) -> bool: return mark in line):
				continue
			found.append("%s:%d %s" % [path, i + 1, line.strip_edges()])
	assert_array(found).override_failure_message("Color literals in UI scripts:\n" + "\n".join(found)).is_empty()


static func _scripts(paths: Array) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		if path.ends_with(".gd"):
			out.append(path)
			continue
		for file in DirAccess.get_files_at("res://" + path):
			if file.ends_with(".gd"):
				out.append(path + "/" + file)
	return out
