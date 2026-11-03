extends Control

## The HUD over the town during a lobby and a game, laid out around the
## middle so the town stays visible:
## - top left, the players with their numbers (PlayerList);
## - top middle, the day or night, its stage and the time left (PhaseClock);
## - right, the chat, under the lobby bar the town keeps at the top right
##   (ChatPanel);
## - bottom middle, what the player can do now (ActionBar);
## - bottom left, the Last will button, a paper and quill that opens the will
##   editor in the chat panel. It shows for the whole game while the player
##   is alive, minigames included.
##
## The night's MinigameOverlay is not part of this scene, since the town
## drives it, but it is placed in the same middle column, between the
## players and the chat (see scenes/main/minigame_overlay.tscn), and the
## ActionBar steps aside while it shows.
##
## Every panel shares HudStyle's theme, set here so the scene file stays
## free of styles.


func _ready() -> void:
	theme = HudStyle.build()
	%WillButton.pressed.connect($ChatPanel.open_will)
	Session.lobby_changed.connect(_update_will_button)
	Session.phase_changed.connect(_update_will_button)
	_update_will_button()


func _update_will_button() -> void:
	%WillButton.visible = Session.in_game() and Session.me != null and Session.me.alive
