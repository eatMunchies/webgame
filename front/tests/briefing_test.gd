extends GdUnitTestSuite

## The briefing: its topics in order, and opening by itself once per lobby
## for a player who isn't ready yet.

var _code := ""
var _me: LobbyPlayer


func before_test() -> void:
	_code = Session.code
	_me = Session.me
	Briefing._opened_for.clear()


func after_test() -> void:
	Session.code = _code
	Session.me = _me
	Briefing._opened_for.clear()


func briefing() -> Briefing:
	var host: Control = auto_free(Control.new())
	add_child(host)
	return Briefing.create(host)


func test_the_topics_come_in_order() -> void:
	var headings: Array = Briefing.TOPICS.map(func(topic: Dictionary) -> String: return topic["heading"])
	assert_array(headings).contains_exactly(
		["intro: an expanded mafia experience", "the factions", "game flow and minigames"])
	var icons: Array = Briefing.ICON_MEANINGS.map(func(meaning: Array) -> StringName: return meaning[0])
	assert_array(icons).contains([&"briefing", &"will", &"role"])


func test_it_opens_once_per_lobby_until_ready() -> void:
	var card := briefing()
	Session.code = "ABC234"
	Session.me = LobbyPlayer.new()
	card.open_on_joining()
	assert_bool(card.visible).is_true()
	card.close()
	card.open_on_joining()
	assert_bool(card.visible).is_false()
	# A new lobby, but this player is already ready: it stays shut.
	Session.code = "XYZ789"
	Session.me.ready = true
	card.open_on_joining()
	assert_bool(card.visible).is_false()
	assert_bool(Briefing.waiting_on_me()).is_false()
