class_name LobbyPlayer
extends RefCounted

## Someone in the current lobby, as the Session autoload tracks them.

## Unique within the lobby. Handed out in join order and never reused.
var id: int
var display_name: String
## Which of the town's lots is theirs, from 0 to Session.MAX_PLAYERS - 1.
var lot: int
var house: HouseAppearance
