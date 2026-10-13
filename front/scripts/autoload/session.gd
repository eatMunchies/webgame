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

## The current lobby's code, or "" when not in a lobby.
var code := ""
var is_host := false


func in_lobby() -> bool:
	return code != ""


## Hosts a new lobby and joins it.
func create_lobby() -> void:
	var new_code := ""
	for i in CODE_LENGTH:
		new_code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	_enter(new_code, true)


## Joins the lobby with the given code. Returns "" on success, or a message
## to show the player.
func join_lobby(raw_code: String) -> String:
	var clean := normalize_code(raw_code)
	if clean.length() != CODE_LENGTH:
		return "Lobby codes are %d characters." % CODE_LENGTH
	for character in clean:
		if not CODE_ALPHABET.contains(character):
			return "\"%s\" can't be in a lobby code." % character
	_enter(clean, false)
	return ""


func leave_lobby() -> void:
	_enter("", false)


## Uppercases a typed code and drops spaces and dashes.
func normalize_code(raw_code: String) -> String:
	return raw_code.to_upper().replace(" ", "").replace("-", "")


func _enter(new_code: String, host: bool) -> void:
	code = new_code
	is_host = host
	lobby_changed.emit()
