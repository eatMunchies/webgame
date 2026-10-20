extends Node

## The connection to the game server and the lobby the player is in,
## available everywhere as the Session autoload.
##
## The talking is done by `client`, a GameClient from the Rust extension,
## which uses the same protocol types as the server. This script turns what it
## reports into things scenes can use directly: the lobby code, the players as
## LobbyPlayer objects, and a log of game text.
##
## Requests go to the server, so their results arrive later: after
## create_lobby() or join_lobby(), wait for lobby_changed (with in_lobby()
## true) or request_failed.

## The lobby's players, the host, or the code changed.
signal lobby_changed
## The game moved to a new phase.
signal phase_changed
## A request was refused or the server couldn't be reached. `message` is
## written for the player.
signal request_failed(message: String)
## A new line in the game log. Every line so far is in log_lines.
signal log_line(text: String)
## Someone else's character moved in the town. `facing` is a
## Character.Facing value.
signal player_moved(lot: int, position: Vector2, facing: int, walking: bool)
## What the player can do changed. Read client.actions().
signal actions_changed

const CODE_LENGTH := 6
## Letters and digits that are hard to confuse when read aloud or typed
## (no 0/O, 1/I/L).
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
## A lobby holds this many players, one per lot in the town.
const MAX_PLAYERS := 15
## The port `just server` and `just play` listen on.
const DEFAULT_PORT := 9090
## The log keeps this many lines, dropping the oldest.
const MAX_LOG_LINES := 300

var client: GameClient
## The current lobby's code, or "" when not in a lobby.
var code := ""
var is_host := false
## Everyone in the lobby, in lot order.
var players: Array[LobbyPlayer] = []
## This player's entry in players, or null when not in a lobby.
var me: LobbyPlayer
## Game text so far, oldest first, so a log that opens later can catch up.
var log_lines: Array[String] = []
## Why the player was last dropped from a lobby, for the lobby screen to
## show. Cleared once shown.
var last_error := ""

## The name the connection was opened with, to reconnect if it changes.
var _connected_as := ""


func _ready() -> void:
	client = GameClient.new()
	client.name = "GameClient"
	add_child(client)
	client.members_changed.connect(_refresh_players)
	client.phase_changed.connect(phase_changed.emit)
	client.log_line.connect(_add_log_line)
	client.server_error.connect(request_failed.emit)
	client.disconnected.connect(_on_disconnected)
	client.player_moved.connect(player_moved.emit)
	client.actions_changed.connect(actions_changed.emit)


func in_lobby() -> bool:
	return code != ""


## Whether a game is being played (not in the lobby, not over).
func in_game() -> bool:
	return client.in_game()


## Hosts a new lobby on the server and joins it.
func create_lobby() -> void:
	if _connect_if_needed():
		client.create_lobby()


## Asks to join the lobby with the given code. Returns "" when the request
## was sent, or a message if the code itself is wrong.
func join_lobby(raw_code: String) -> String:
	var clean := normalize_code(raw_code)
	if clean.length() != CODE_LENGTH:
		return "Lobby codes are %d characters." % CODE_LENGTH
	if not _connect_if_needed():
		return ""
	return client.join_lobby(clean)


func leave_lobby() -> void:
	client.leave_lobby()
	_clear()


## Sends a line typed into the game chat: plain text is chat, and lines like
## `/vote 3` are commands (see client.help_text()). Returns "" when sent, or
## a message saying what was wrong.
func submit(line: String) -> String:
	return client.submit(line)


## Tells everyone in the lobby how this player's character looks, from
## PlayerProfile. Sent on joining a lobby.
func send_appearance() -> void:
	var look := PlayerProfile.appearance
	client.set_appearance(look.body_type, look.gender, look.skin_color, look.items)


## Returns the player who owns a lot, or null if it's empty.
func player_on_lot(lot: int) -> LobbyPlayer:
	for player in players:
		if player.lot == lot:
			return player
	return null


## Uppercases a typed code and drops spaces and dashes.
func normalize_code(raw_code: String) -> String:
	return raw_code.to_upper().replace(" ", "").replace("-", "")


## Where the game server is. Run with `-- --server=ws://host:port/ws` to
## choose one. In a browser it is the host that served the page, on
## DEFAULT_PORT; otherwise this machine.
func server_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			return arg.trim_prefix("--server=")
	if OS.has_feature("web"):
		var host: String = JavaScriptBridge.eval("window.location.hostname")
		var secure: bool = JavaScriptBridge.eval("window.location.protocol") == "https:"
		return "%s://%s:%d/ws" % ["wss" if secure else "ws", host, DEFAULT_PORT]
	return "ws://127.0.0.1:%d/ws" % DEFAULT_PORT


## Opens a connection as the profile's username, unless one is already open
## under that name. Returns false, after emitting request_failed, when it
## couldn't start.
func _connect_if_needed() -> bool:
	var username := PlayerProfile.username
	if client.is_online() and _connected_as == username:
		return true
	_connected_as = username
	var error := client.connect_to_server(server_url(), username)
	if error != "":
		_connected_as = ""
		request_failed.emit(error)
		return false
	return true


## Rebuilds `players` from the client's member list.
func _refresh_players() -> void:
	var new_code := client.lobby_code()
	# The log belongs to one lobby, but its first lines arrive just before
	# the lobby does, so it is only cleared on the way out.
	if new_code == "":
		log_lines.clear()
	var joined := new_code != "" and new_code != code
	code = new_code
	is_host = client.is_host()
	players.clear()
	me = null
	for member in client.members():
		var player := LobbyPlayer.new()
		player.user_id = member["user_id"]
		player.display_name = member["name"]
		player.number = member["number"]
		player.lot = member["lot"]
		player.alive = member["alive"]
		player.connected = member["connected"]
		player.is_host = member["is_host"]
		if member["appearance"] != null:
			player.appearance = _appearance_from(member["appearance"])
		# Seeded from the lobby code and user id, so every client in the
		# lobby builds the same house for this player.
		player.house = HouseAppearance.random(hash("%s/%s" % [code, player.user_id]))
		players.append(player)
		if member["is_me"]:
			me = player
	if joined:
		send_appearance()
	lobby_changed.emit()


func _appearance_from(fields: Dictionary) -> CharacterAppearance:
	var look := CharacterAppearance.new()
	look.body_type = fields["body_type"]
	look.gender = fields["gender"]
	look.skin_color = fields["skin_color"]
	var items: Dictionary = fields["items"]
	for slot in items:
		look.items[str(slot)] = str(items[slot])
	return look


func _add_log_line(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()
	log_line.emit(text)


func _on_disconnected(reason: String) -> void:
	_connected_as = ""
	if in_lobby():
		last_error = reason
	_clear()
	request_failed.emit(reason)


func _clear() -> void:
	code = ""
	is_host = false
	players.clear()
	me = null
	log_lines.clear()
	lobby_changed.emit()
