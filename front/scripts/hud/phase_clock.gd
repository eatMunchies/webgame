extends PanelContainer

## The clock at the top middle of the town: which day or night it is, the
## stage under it (Discussion, Voting, Defense: Bram ...), and the time left
## in that stage, counting down. Before a game it says how many are in the
## lobby, since that is what the host waits on.
##
## Past choosing, a night shows only its title: the stages it plays through
## (roleblocks, fight rounds, protection, investigations) and their timers
## are hidden, so nobody can tell from the clock what is happening tonight.
## The minigame overlay shows what the player is doing.

## The night stage whose name and timer still show, since players need to
## know how long they have to pick.
const CHOOSING_STAGE := "Choose your action"

## The countdown turns red with this many seconds or fewer left, so a
## closing vote or judgement is hard to miss.
const HURRY_SECONDS := 5

@onready var title_label: Label = %Title
@onready var time_label: Label = %Time
@onready var stage_label: Label = %Stage


func _process(_delta: float) -> void:
	# The countdown ticks, so this reads the phase every frame. It is one
	# small Dictionary from the client, cheap next to drawing the town.
	var info: Dictionary = Session.client.phase_info()
	var night: bool = info["night"]
	title_label.text = info["title"]
	title_label.add_theme_color_override("font_color",
			HudStyle.NIGHT_TITLE_COLOR if night else RpgTheme.GOLD_BRIGHT)
	var stage: String = info["stage"]
	if not Session.in_game() and Session.in_lobby():
		stage = _lobby_stage() if info["title"] == "Lobby" else "The host can start a new game"
	var seconds: int = info["seconds_left"]
	if night and stage != CHOOSING_STAGE:
		stage = ""
		seconds = -1
	stage_label.text = stage
	stage_label.visible = stage != ""
	time_label.visible = seconds >= 0
	if seconds >= 0:
		time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
		time_label.add_theme_color_override("font_color",
				HudStyle.DANGER_COLOR if seconds <= HURRY_SECONDS else RpgTheme.TEXT)


## What the lobby is waiting for: more players, or the host to start.
func _lobby_stage() -> String:
	var count := Session.players.size()
	if count < 4:
		return "%d joined, 4 to start" % count
	return "%d joined, host starts" % count
