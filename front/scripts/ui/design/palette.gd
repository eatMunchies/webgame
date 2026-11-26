class_name Palette
extends RefCounted

## Every raw color in Table of Salem's UI, named for what it's made of, as
## a 1692 printer or the machine would have it. Nothing draws with these
## directly: components use the semantic names in Tokens, which pick from
## here. docs/DESIGN.md explains the palette; the style gallery
## (`just gallery`) shows every swatch with its contrast.
##
## Two worlds share the screen (see docs/LORE.md): the simulated Salem,
## printed in iron-gall ink on parchment and sealed in wax; and the machine
## running it, black glass with one cold cyan.

# Parchment, by day and by candlelight.
const PAPER_RAISED := Color("#f2e8d2")
const PAPER := Color("#e9dcc0")
const PAPER_SUNKEN := Color("#d9c7a1")
const PAPER_EDGE := Color("#b89b6a")
const PAPER_RAISED_NIGHT := Color("#e2cfa6")
const PAPER_NIGHT := Color("#dcc79c")
const PAPER_SUNKEN_NIGHT := Color("#cdb589")
const PAPER_EDGE_NIGHT := Color("#6e4f2c")

# Iron-gall ink, from fresh to faded.
const INK := Color("#1f1a14")
const INK_BROWN := Color("#4a3f33")
const INK_FADED := Color("#5e503f")
const INK_RULE := Color("#8c7656")

# Sealing wax and gold leaf.
const WAX := Color("#8e1b1b")
const WAX_BRIGHT := Color("#b3261e")
const WAX_DARK := Color("#6e1414")
const GOLD_LEAF := Color("#a37a22")
const GOLD_GLOW := Color("#e8c060")
const CANDLE := Color("#ffb347")

# Dyes of the period, for meaning on paper.
const VERDIGRIS := Color("#25582f")
const WOAD := Color("#2b4c7e")
const LOGWOOD := Color("#5b3f7a")
const OCHRE_DARK := Color("#6e4a00")
const ASH := Color("#554b3e")

# The machine.
const SYS_BLACK := Color("#0a0e10")
const SYS_PANEL := Color("#10171a")
const SYS_LINE := Color("#2a3a40")
const SYS_TEXT := Color("#d7e3e6")
const SYS_DIM := Color("#7f9399")
const SYS_CYAN := Color("#46e0e0")
const SYS_CYAN_DIM := Color("#1f6f73")
const SYS_TEAL_INK := Color("#0d5357")
const SYS_FAULT := Color("#e0466a")

## The fifteen seats' dyes, one per lot, for number badges in the roster and
## the chat. Dark enough that a parchment numeral reads on each, and far
## enough apart in hue to tell neighbours apart.
const SEAT_DYES: Array[Color] = [
	Color("#a8322d"),  # madder
	Color("#94601a"),  # saffron
	Color("#65631a"),  # weld
	Color("#2a6a58"),  # verdigris
	Color("#2b4c7e"),  # woad
	Color("#3a3478"),  # indigo
	Color("#6a3f86"),  # logwood
	Color("#a3245a"),  # cochineal
	Color("#5c4128"),  # walnut
	Color("#3d3a36"),  # oak gall
	Color("#8a501e"),  # ochre
	Color("#4a6541"),  # sage
	Color("#4d5c6b"),  # slate
	Color("#9a4350"),  # rose madder
	Color("#6b4a2f"),  # umber
]

## The colors that change between day and candlelit night, by token name.
## Both tables have the same keys (tests/design_tokens_test.gd checks).
## Ink doesn't change: the night paper stays light enough that every text
## ink keeps a contrast of 4.5 or more on it (tests/design_tokens_test.gd).
const DAY := {
	"paper_raised": PAPER_RAISED,
	"paper_surface": PAPER,
	"paper_sunken": PAPER_SUNKEN,
	"paper_edge": PAPER_EDGE,
	"candle": 0.0,
}
const NIGHT := {
	"paper_raised": PAPER_RAISED_NIGHT,
	"paper_surface": PAPER_NIGHT,
	"paper_sunken": PAPER_SUNKEN_NIGHT,
	"paper_edge": PAPER_EDGE_NIGHT,
	"candle": 1.0,
}
