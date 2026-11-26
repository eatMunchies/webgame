class_name Tokens
extends RefCounted

## The design system's named values: what each color is for, the type scale,
## spacing, sizes, motion and stacking. Components ask for `Tokens.ink`, not
## for a hex value, so the look can change in one place. The raw colors are
## in Palette; docs/DESIGN.md is the written guide.
##
## Sizes are in HUD units, where the window's short side is 180 (see
## ScreenScale). Menu screens laid out in 1280x720 pass a unit of 4 to
## UiTheme, which multiplies these.
##
## Colors that change between day and candlelit night are static vars that
## use_night() swaps; everything else is fixed. Nothing here touches an
## autoload, so tools that run before autoloads exist can use it.

# --- In-world: parchment and ink -------------------------------------------

static var paper_raised := Palette.PAPER_RAISED
static var paper_surface := Palette.PAPER
static var paper_sunken := Palette.PAPER_SUNKEN
static var paper_edge := Palette.PAPER_EDGE
## 0 by day, 1 at night: how far surfaces lean toward candlelight.
static var candle := 0.0

const INK := Palette.INK
const INK_SECONDARY := Palette.INK_BROWN
const INK_FAINT := Palette.INK_FADED
const INK_RULE := Palette.INK_RULE
## Text on wax or ink fills.
const INK_ON_DARK := Palette.PAPER_LIGHT
const PAPER_SHADOW := Color(Palette.INK, 0.3)
## The dim over the screen behind a parchment card or text box.
const PAPER_SCRIM := Color(Palette.INK, 0.55)

const WAX := Palette.WAX
const WAX_HOVER := Palette.WAX_BRIGHT
const WAX_PRESSED := Palette.WAX_DARK
const GOLD := Palette.GOLD_LEAF
const GLOW := Palette.GOLD_GLOW

# State on paper.
const YOU := Palette.WOAD
const DEAD := Palette.ASH
const DANGER := Palette.WAX
const SAFE := Palette.VERDIGRIS
## A choice made (a vote cast, an ability aimed): filled ink.
const SELECTED := Palette.INK

# Factions, for the role card only: a faction's color anywhere else on screen
# would tell an onlooker your role.
const FACTION_TOWN := Palette.VERDIGRIS
const FACTION_MAFIA := Palette.WAX
const FACTION_NEUTRAL := Palette.LOGWOOD

# The chat, which is the machine's log of the session, on its glass.
const LOG_SAID := Palette.SYS_TEXT
const LOG_WHISPER := Palette.SYS_CYAN
## Game news (deaths, votes, results): the log's one warm color, so the
## news stands out from talk.
const LOG_GAME := Palette.GOLD_GLOW
## The machine's own lines (the connection, errors, help).
const LOG_MACHINE := Palette.SYS_DIM
## How much of the town shows through the log's glass.
const LOG_GLASS_ALPHA := 0.82

# The town by candlelight (shaders/candle_vignette.gdshader): the tint over
# the middle of the pool of light, and the dark at the screen's edges.
const NIGHT_CANDLE := Color(0.16, 0.08, 0.02, 0.58)
const NIGHT_DARK := Color(Palette.SYS_BLACK, 0.94)

# Labels over the town itself (names over houses and people, hints).
const WORLD_LABEL := Palette.PAPER_RAISED
const WORLD_LABEL_OUTLINE := Palette.INK
const WORLD_HINT := Palette.GOLD_GLOW

# --- The machine -------------------------------------------------------------

const SYS_BG := Palette.SYS_BLACK
const SYS_SURFACE := Palette.SYS_PANEL
const SYS_LINE := Palette.SYS_LINE
const SYS_TEXT := Palette.SYS_TEXT
const SYS_DIM := Palette.SYS_DIM
const SYS_ACCENT := Palette.SYS_CYAN
const SYS_ACCENT_DIM := Palette.SYS_CYAN_DIM
const SYS_FAULT := Palette.SYS_FAULT
const SYS_SCRIM := Color(0, 0, 0, 0.6)

# --- Type scale (HUD units) -------------------------------------------------

## The start screen's title.
const TYPE_DISPLAY := 14
## "Day 2", a role's name, a prompt's title.
const TYPE_TITLE := 10
## Section heads in small caps: "Players", "Ability".
const TYPE_HEADING := 7
## The roster, the chat, buttons.
const TYPE_BODY := 6
## What's being typed in the text box.
const TYPE_BODY_LARGE := 8
## A player's name where it's the thing you read: the roster's rows.
const TYPE_NAME := 7
## The primary action's words, set in IM Fell small caps on wax.
const TYPE_SEAL := 8
## Small print that's never something to tap.
const TYPE_CAPTION := 5
const TYPE_MONO := 6
const TYPE_MONO_SMALL := 5
## A minigame's countdown digit.
const TYPE_MONO_HUGE := 22

# --- Spacing and size (HUD units) -------------------------------------------

const SPACE_HAIR := 1
const SPACE_XS := 2
const SPACE_SM := 3
const SPACE_MD := 4
const SPACE_LG := 6
const SPACE_XL := 8
const SPACE_XXL := 12
## The least height for anything tapped on a phone.
const TOUCH_MIN := 14
const ICON := 16
const RULE := 1

# --- Motion (seconds) -------------------------------------------------------

const DUR_FAST := 0.12
const DUR_BASE := 0.2
const DUR_PHASE := 1.5
const DUR_GLITCH := 0.25

# --- Stacking (z_index) -----------------------------------------------------

const Z_SHEET := 10
const Z_NOTICE := 80
const Z_CARD := 90
const Z_PROMPT := 100


## A seat's dye, for player number `number` (from 1).
static func seat(number: int) -> Color:
	return Palette.SEAT_DYES[(number - 1) % Palette.SEAT_DYES.size()]


## Switches the surfaces to candlelit night, or back to day.
static func use_night(on: bool) -> void:
	var table: Dictionary = Palette.NIGHT if on else Palette.DAY
	paper_raised = table["paper_raised"]
	paper_surface = table["paper_surface"]
	paper_sunken = table["paper_sunken"]
	paper_edge = table["paper_edge"]
	candle = table["candle"]
