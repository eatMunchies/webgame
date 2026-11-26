extends GalleryPage

## The real town and HUD, in game states played out by the Rust fixtures
## (GameClient.load_fixture, which runs the actual game rules), so a
## component is seen among everything around it. One variant per fixture.

const TOWN := preload("res://scenes/main/town.tscn")


func _init() -> void:
	variants = ["lobby_host_4", "lobby_full_15", "day_voting", "day_trial", "night_choosing", "spectating"]
	settle_frames = 90


func build(stage: Control, variant: String) -> void:
	var session := stage.get_node("/root/Session")
	session.arrival_spot = null
	var error: String = session.client.load_fixture(variant)
	if error != "":
		stage.add_child(caption(error, Color.RED, 8))
		return
	# The night's candlelight, as the town would set it.
	if session.client.is_night():
		Tokens.use_night(true)
	stage.add_child(TOWN.instantiate())


func after_settle(stage: Control) -> void:
	# The role card opens on its own at a game's start; put it away so the
	# HUD shows. (The dialogs get pages of their own.)
	for card in stage.find_children("*", "RoleCard", true, false):
		card.close()


func teardown(stage: Control) -> void:
	stage.get_node("/root/Session").client.load_fixture("reset")
