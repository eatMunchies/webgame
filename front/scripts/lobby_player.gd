class_name LobbyPlayer
extends RefCounted

## Someone in the current lobby, as the Session autoload tracks them.

## The server's id for this player's username, as text (it doesn't fit an
## int). The same name always gets the same id.
var user_id: String
var display_name: String
## The number players type to name them in commands like `/vote 3`: their
## lot plus one.
var number: int
## Which of the town's lots is theirs, from 0 to Session.MAX_PLAYERS - 1.
var lot: int
var house: HouseAppearance
## How their character looks, or null until their client has said.
var appearance: CharacterAppearance
## False once they have died in the current game.
var alive := true
## False while their connection is down. Their seat waits for them.
var connected := true
var is_host := false
