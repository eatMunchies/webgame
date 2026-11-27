extends GalleryPage

## The real town and HUD, in game states played out by the Rust fixtures
## (GameClient.load_fixture, which runs the actual game rules), so a
## component is seen among everything around it. One variant per fixture,
## and the briefing open over the lobby.

const TOWN := preload("res://scenes/main/town.tscn")

var _variant := ""


func _init() -> void:
	variants = ["lobby_host_4", "briefing", "lobby_full_15", "day_voting", "day_trial", "night_choosing", "spectating", "reconnecting", "role_card", "night_minigame"]
	# Past the candle's fade in (town.gd DAY_FADE_SECONDS).
	settle_frames = 120


func build(stage: Control, variant: String) -> void:
	var session := stage.get_node("/root/Session")
	session.arrival_spot = null
	# Reconnecting is a voting day with the connection down; role_card the
	# same day with the role card open.
	_variant = variant
	var fixture := "day_voting" if variant in ["reconnecting", "role_card"] else variant
	if variant == "briefing":
		fixture = "lobby_host_4"
	var error: String = session.client.load_fixture(fixture)
	if error != "":
		stage.add_child(caption(error, Color.RED, 8))
		return
	# The night's candlelight, as the town would set it.
	if session.client.is_night():
		Tokens.use_night(true)
	stage.add_child(TOWN.instantiate())
	if variant == "briefing":
		# Opened well before the capture, so its glitch has settled.
		stage.get_tree().create_timer(0.5).timeout.connect(func() -> void:
			for card in stage.find_children("*", "Briefing", true, false):
				card.open())
	if variant == "reconnecting":
		session.reconnecting = true
		session.reconnecting_changed.emit()


func after_settle(stage: Control) -> void:
	if _variant == "briefing":
		return
	# The briefing opens on its own in a lobby; put it away too.
	for card in stage.find_children("*", "Briefing", true, false):
		card.close()
	if _variant == "role_card":
		for card in stage.find_children("*", "RoleCard", true, false):
			card.open()
		return
	# The role card opens on its own at a game's start; put it away so the
	# HUD shows. (The dialogs get pages of their own.)
	for card in stage.find_children("*", "RoleCard", true, false):
		card.close()


func teardown(stage: Control) -> void:
	stage.get_node("/root/Session").reconnecting = false
	stage.get_node("/root/Session").client.load_fixture("reset")
