extends Node

## The lobby the player is in, available everywhere as the Session autoload.
##
## This is a local stand-in until the game server exists: creating a lobby
## just makes up a code, and joining accepts any well-formed code without
## checking that the lobby exists. The functions are shaped like the real
## thing (a request that can fail with a message) so the lobby screen won't
## need to change when they start talking to the server.

signal lobby_changed

const CODE_LENGTH := 6
## Letters and digits that are hard to confuse when read aloud or typed
## (no 0/O, 1/I/L).
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
## A lobby holds this many players, one per lot in the town.
const MAX_PLAYERS := 15
## The stand-in lobby pretends this many other people are already in it, so
## the town has houses to look at. Set it to 0 to see empty lots.
const STUB_OTHER_PLAYERS := 14
const STUB_NAMES: Array[String] = [
	"Ada", "Bram", "Cleo", "Dev", "Edie", "Finn", "Gus",
	"Hana", "Ivo", "Juno", "Kit", "Lou", "Mo", "Nell",
]

## The current lobby's code, or "" when not in a lobby.
var code := ""
var is_host := false
## Everyone in the lobby, in join order.
var players: Array[LobbyPlayer] = []
## This player's entry in players, or null when not in a lobby.
var me: LobbyPlayer

var _next_player_id := 0


func in_lobby() -> bool:
	return code != ""


## Hosts a new lobby and joins it. The host gets the first lot.
func create_lobby() -> void:
	var new_code := ""
	for i in CODE_LENGTH:
		new_code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	_start(new_code, true)
	me = _add_player("You")
	_add_stub_players()
	lobby_changed.emit()


## Joins the lobby with the given code. Returns "" on success, or a message
## to show the player.
func join_lobby(raw_code: String) -> String:
	var clean := normalize_code(raw_code)
	if clean.length() != CODE_LENGTH:
		return "Lobby codes are %d characters." % CODE_LENGTH
	for character in clean:
		if not CODE_ALPHABET.contains(character):
			return "\"%s\" can't be in a lobby code." % character
	_start(clean, false)
	# The stand-in players were "already there", so they hold the first lots.
	_add_stub_players()
	me = _add_player("You")
	if me == null:
		_start("", false)
		return "That lobby is full."
	lobby_changed.emit()
	return ""


func leave_lobby() -> void:
	_start("", false)
	lobby_changed.emit()


## Returns the player who owns a lot, or null if it's empty.
func player_on_lot(lot: int) -> LobbyPlayer:
	for player in players:
		if player.lot == lot:
			return player
	return null


## Uppercases a typed code and drops spaces and dashes.
func normalize_code(raw_code: String) -> String:
	return raw_code.to_upper().replace(" ", "").replace("-", "")


func _start(new_code: String, host: bool) -> void:
	code = new_code
	is_host = host
	players.clear()
	me = null
	_next_player_id = 0


## Adds a player on the lowest free lot, so lots fill in join order and a
## lot freed by someone leaving goes to the next person in. Returns null
## when the lobby is full.
func _add_player(display_name: String) -> LobbyPlayer:
	if players.size() >= MAX_PLAYERS:
		return null
	var player := LobbyPlayer.new()
	player.id = _next_player_id
	_next_player_id += 1
	player.display_name = display_name
	player.lot = 0
	while player_on_lot(player.lot) != null:
		player.lot += 1
	# Seeded from the lobby code and player id, so every client in the lobby
	# would build the same house for this player.
	player.house = HouseAppearance.random(hash("%s/%d" % [code, player.id]))
	players.append(player)
	return player


func _add_stub_players() -> void:
	for i in STUB_OTHER_PLAYERS:
		_add_player(STUB_NAMES[i % STUB_NAMES.size()])
