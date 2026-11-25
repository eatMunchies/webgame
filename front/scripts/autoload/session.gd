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
## A new line in the game log, and its kind: LINE_CHAT (what players
## said), LINE_WHISPER (whispers, and the notice that someone whispered), LINE_GAME (your role, results, deaths, votes and other events) or
## LINE_SYSTEM (the lobby, the connection, errors). `lot` is the lot of the
## player who said a chat line, or -1. Every line so far is in log_lines.
signal log_line(text: String, kind: String, lot: int)
## Someone else's character moved in the town. `facing` is a
## Character.Facing value.
signal player_moved(lot: int, position: Vector2, facing: int, walking: bool)
## What the player can do changed. Read client.actions().
signal actions_changed
## The player's night minigame started, ended, or changed. Read
## client.minigame() and client.fight().
signal minigame_changed
## The connection dropped and Session started trying to get back in, or
## stopped trying (it got back in, or gave up). Read `reconnecting`.
signal reconnecting_changed

const CODE_LENGTH := 6
## Letters and digits that are hard to confuse when read aloud or typed
## (no 0/O, 1/I/L).
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
## A lobby holds this many players, one per lot in the town.
const MAX_PLAYERS := 15
## The port `just server` and `just play` listen on.
const DEFAULT_PORT := 9090
## How long Session keeps trying to get back into the lobby after the
## connection drops, as long as the server keeps a seat waiting before a game
## (RECONNECT_GRACE in webgame-server), and how often it tries.
const RECONNECT_SECONDS := 90.0
const RECONNECT_EVERY := 3.0
## The log keeps this many lines, dropping the oldest.
const MAX_LOG_LINES := 300

var client: GameClient
## The current lobby's code, or "" when not in a lobby.
var code := ""
var is_host := false
## True while the connection is down and Session is trying to get back into
## the lobby: phones drop it when the browser goes to the background. The
## player stays where they are meanwhile; the server keeps their seat (for
## the game, or RECONNECT_SECONDS before one).
var reconnecting := false
## Everyone in the lobby, in lot order.
var players: Array[LobbyPlayer] = []
## The kinds of game log line; see log_line.
const LINE_CHAT := "chat"
const LINE_WHISPER := "whisper"
const LINE_GAME := "game"
const LINE_SYSTEM := "system"

## This player's entry in players, or null when not in a lobby.
var me: LobbyPlayer
## Game text so far, oldest first, so a log that opens later can catch up:
## each {text, kind, lot}, as log_line gives them.
var log_lines: Array[Dictionary] = []
## Why the player was last dropped from a lobby, for the lobby screen to
## show. Cleared once shown.
var last_error := ""
## Whether the lobby screen already acted on `--create` or `--join=`, so it
## doesn't rejoin after the player leaves.
var launch_request_done := false
## Where the player stood by their house on the start screen, in world
## pixels from its ground point, so the town can put them in the same spot by
## their house on its lot, and phase in around them. The town uses it once
## and clears it. A Vector2, or null.
var arrival_spot: Variant = null
## Which way the player faced on the start screen, for the town to match.
var arrival_facing := Character.Facing.DOWN
## Where on screen the start screen centered the player (the middle of the
## part its panel leaves), so the town's camera can start there and glide to
## its own center. A Vector2, or null. The town uses it once and clears it.
var arrival_view_center: Variant = null

## The name the connection was opened with, to reconnect if it changes.
var _connected_as := ""
## While reconnecting: the lobby to get back into, why the connection
## dropped, and when to give up.
var _reconnect_code := ""
var _reconnect_reason := ""
var _reconnect_until_msec := 0
var _reconnect_timer := Timer.new()


func _ready() -> void:
	client = GameClient.new()
	client.name = "GameClient"
	add_child(client)
	client.members_changed.connect(_refresh_players)
	client.phase_changed.connect(phase_changed.emit)
	client.log_line.connect(_add_log_line)
	client.server_error.connect(_on_server_error)
	client.disconnected.connect(_on_disconnected)
	client.player_moved.connect(player_moved.emit)
	client.actions_changed.connect(actions_changed.emit)
	client.minigame_changed.connect(minigame_changed.emit)
	_reconnect_timer.timeout.connect(_try_reconnect)
	add_child(_reconnect_timer)


func in_lobby() -> bool:
	return code != "" or reconnecting


## Whether a game is being played (not in the lobby, not over).
func in_game() -> bool:
	return client.in_game()


## Whether the player is busy with a night minigame, and shouldn't walk.
func in_minigame() -> bool:
	return client.has_minigame()


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
	if reconnecting:
		_stop_reconnecting()
		client.disconnect_from_server()
		_connected_as = ""
	client.leave_lobby()
	_clear()


## Sends a line typed into the game chat: plain text is chat, and lines like
## `/vote 3` are commands (see client.help_text()). Returns "" when sent, or
## a message saying what was wrong.
func submit(line: String) -> String:
	return client.submit(line)


## Tells everyone in the lobby how this player's character and house look,
## from PlayerProfile. Sent on joining a lobby.
func send_appearance() -> void:
	var look := PlayerProfile.appearance
	client.set_appearance(look.body_type, look.gender, look.skin_color, look.items, PlayerProfile.house.to_dictionary())


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
## choose one. In a browser served over https it is `/ws` on the page's own
## origin, since a proxy in front (like a Cloudflare Tunnel) routes that path
## to the server and only answers on the standard port. Over plain http, as
## when testing an export locally, it is the page's host on DEFAULT_PORT.
## Otherwise it is this machine.
func server_url() -> String:
	var chosen := LaunchOptions.value("server")
	if chosen != "":
		return chosen
	if OS.has_feature("web"):
		var secure: bool = JavaScriptBridge.eval("window.location.protocol") == "https:"
		if secure:
			var origin_host: String = JavaScriptBridge.eval("window.location.host")
			return "wss://%s/ws" % origin_host
		var host: String = JavaScriptBridge.eval("window.location.hostname")
		return "ws://%s:%d/ws" % [host, DEFAULT_PORT]
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
	if new_code == "" and code != "" and not client.is_online():
		# The connection dropped; `disconnected` comes next and starts getting
		# back in, so keep showing the lobby until then.
		return
	if reconnecting:
		if new_code == "":
			# The dropped connection's empty lobby: keep showing the last one.
			return
		_stop_reconnecting()
		add_log_line("Reconnected.")
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
		# Layers the player didn't pick are random, seeded from the lobby
		# code and user id so every client in the lobby builds the same house.
		player.house = HouseAppearance.random(hash("%s/%s" % [code, player.user_id]))
		if member["appearance"] != null:
			player.appearance = _appearance_from(member["appearance"])
			player.house.apply_dictionary(member["appearance"]["house"])
		players.append(player)
		if member["is_me"]:
			me = player
	if joined:
		# `just clients` reads the host's code from this line.
		print("Joined lobby %s" % code)
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


## Adds a line of this client's own to the game log, like the reason a
## button's command was refused. Everyone else's lines come from the client.
func add_log_line(text: String, kind := LINE_SYSTEM) -> void:
	_add_log_line(text, kind, -1)


func _add_log_line(text: String, kind: String, lot: int) -> void:
	log_lines.append({"text": text, "kind": kind, "lot": lot})
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()
	log_line.emit(text, kind, lot)


func _on_server_error(message: String) -> void:
	if reconnecting:
		# The way back in was refused (the lobby is gone, say): stop trying.
		_reconnect_reason = message
		_give_up_reconnecting()
		return
	request_failed.emit(message)


func _on_disconnected(reason: String) -> void:
	_connected_as = ""
	if reconnecting:
		# A try that didn't get through; the timer tries again.
		return
	if code != "":
		_start_reconnecting(reason)
		return
	_clear()
	request_failed.emit(reason)


## Keeps the player where they are and tries to get back into the lobby, as
## the same name, every RECONNECT_EVERY seconds for RECONNECT_SECONDS.
func _start_reconnecting(reason: String) -> void:
	reconnecting = true
	_reconnect_code = code
	_reconnect_reason = reason
	_reconnect_until_msec = Time.get_ticks_msec() + int(RECONNECT_SECONDS * 1000)
	add_log_line("Connection lost. Reconnecting...")
	_reconnect_timer.start(RECONNECT_EVERY)
	reconnecting_changed.emit()
	_try_reconnect()


func _try_reconnect() -> void:
	if not reconnecting:
		return
	if Time.get_ticks_msec() >= _reconnect_until_msec:
		_give_up_reconnecting()
		return
	if client.is_online():
		return
	_connected_as = PlayerProfile.username
	if client.connect_to_server(server_url(), PlayerProfile.username) == "":
		# Sent once the connection is up.
		client.join_lobby(_reconnect_code)
	else:
		_connected_as = ""


func _stop_reconnecting() -> void:
	reconnecting = false
	_reconnect_timer.stop()
	reconnecting_changed.emit()


func _give_up_reconnecting() -> void:
	_stop_reconnecting()
	client.disconnect_from_server()
	_connected_as = ""
	last_error = _reconnect_reason
	_clear()
	request_failed.emit(_reconnect_reason)


func _clear() -> void:
	code = ""
	is_host = false
	players.clear()
	me = null
	log_lines.clear()
	lobby_changed.emit()
