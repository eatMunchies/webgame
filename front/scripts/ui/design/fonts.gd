class_name Fonts
extends RefCounted

## The three bundled typefaces (all SIL Open Font License, with their
## license files beside them in assets/fonts):
## - IM Fell English and its small caps, a revival of type cut in the 1670s,
##   for titles and headings: Salem as it was printed.
## - Atkinson Hyperlegible, made to stay readable small, for everything
##   people read and tap: the roster, the chat, buttons.
## - IBM Plex Mono, for the machine that runs the simulation.
##
## They're bundled, not asked of the system, so phones and the web build get
## the same letters. Each falls back to Atkinson, then Godot's own font, for
## letters it lacks (a player's name in another script, say).

const TITLE: FontFile = preload("res://assets/fonts/im_fell/IMFellEnglish-Regular.ttf")
const TITLE_ITALIC: FontFile = preload("res://assets/fonts/im_fell/IMFellEnglish-Italic.ttf")
const HEADING: FontFile = preload("res://assets/fonts/im_fell/IMFellEnglishSC-Regular.ttf")
const BODY: FontFile = preload("res://assets/fonts/atkinson/AtkinsonHyperlegible-Regular.ttf")
const BODY_BOLD: FontFile = preload("res://assets/fonts/atkinson/AtkinsonHyperlegible-Bold.ttf")
const BODY_ITALIC: FontFile = preload("res://assets/fonts/atkinson/AtkinsonHyperlegible-Italic.ttf")
const MONO: FontFile = preload("res://assets/fonts/plex_mono/IBMPlexMono-Regular.ttf")
const MONO_BOLD: FontFile = preload("res://assets/fonts/plex_mono/IBMPlexMono-Bold.ttf")


static func _static_init() -> void:
	var to_body: Array[Font] = [BODY, ThemeDB.fallback_font]
	for font: FontFile in [TITLE, TITLE_ITALIC, HEADING, MONO, MONO_BOLD]:
		font.fallbacks = to_body
	for font: FontFile in [BODY, BODY_BOLD, BODY_ITALIC]:
		font.fallbacks = [ThemeDB.fallback_font] as Array[Font]
