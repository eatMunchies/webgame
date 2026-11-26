class_name Modal
extends Control

## The base of everything that opens over the screen and waits: a dimmed
## backdrop and one panel on it. TextPrompt (typing) and RoleCard (reading)
## are built on it; see DESIGN.md, Modals and dialogs, for when to use one
## at all (rarely: inline is the default).
##
## The panel is a parchment Document in Salem, or the machine's glass on the
## machine's screens (`system`). It sits in the upper middle (UPPER, clear of
## a phone's keyboard) or the middle (CENTER), `width` units wide at most.
## Escape or a tap on the backdrop closes it, as does whatever close the
## subclass offers. Put the contents in `rows`.

enum Place { UPPER, CENTER }

## Where an UPPER panel's top sits, as a share of the screen's height.
const TOP_SHARE := 0.14
## The panel's share of the screen's width at most.
const WIDTH_SHARE := 0.92
## How long after opening a tap on the backdrop is ignored. One tap on a
## phone arrives as a touch and a made-up mouse click; when the first opens
## the modal, the second would land on the backdrop and close it again.
const BACKDROP_GRACE_MSEC := 400

## Closed, by any means.
signal closed

## The panel's width in units, at most.
var width := 200.0
var place := Place.CENTER
## The machine's glass instead of parchment. Set before the modal is added.
var system := false
## The panel, and the column its contents go in.
var panel: PanelContainer
var rows := VBoxContainer.new()

var _backdrop := ColorRect.new()
var _opened_msec := 0


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_backdrop.color = Tokens.SYS_SCRIM if system else Tokens.PAPER_SCRIM
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)
	if system:
		panel = SystemPanel.new()
		panel.theme = UiTheme.system()
	else:
		var paper := ParchmentPanel.new()
		paper.tier = ParchmentPanel.Tier.DOCUMENT
		paper.paper_theme = true
		panel = paper
	add_child(panel)
	rows.add_theme_constant_override("separation", Tokens.SPACE_SM)
	panel.add_child(rows)
	resized.connect(_place)


## Fills `parent` (a Control, or a CanvasLayer for the whole screen) and
## stays hidden until shown.
func fill(parent: Node) -> void:
	parent.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_modal() -> void:
	visible = true
	_opened_msec = Time.get_ticks_msec()
	_place()
	if system:
		(panel as SystemPanel).glitch_in()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Sizes and places the panel for the screen it's on.
func _place() -> void:
	if not visible:
		return
	var w := minf(width, size.x * WIDTH_SHARE)
	# Wrapping labels measure their height at the width they have, so each
	# gets the panel's inner width up front; with none they'd wrap every word.
	var inner := w - panel.get_theme_stylebox("panel").get_minimum_size().x
	# (Labels that share a row with something else shouldn't wrap.)
	for label: Label in rows.find_children("*", "Label", true, false):
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			label.custom_minimum_size.x = inner
	panel.custom_minimum_size.x = w
	panel.size = Vector2(w, 0)
	_settle.call_deferred()


## Places the panel once its wrapped text has a height.
func _settle() -> void:
	panel.size = Vector2(panel.size.x, 0)
	var y := roundf(size.y * TOP_SHARE) if place == Place.UPPER \
			else roundf((size.y - panel.size.y) / 2.0)
	panel.position = Vector2(roundf((size.x - panel.size.x) / 2.0), y)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - _opened_msec < BACKDROP_GRACE_MSEC:
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		close()
