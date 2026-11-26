class_name Icons
extends RefCounted

## The UI's woodcut icons (assets/sprites/ui/icons/, drawn by
## tools/icons/make_icons.gd), white on transparent so they take the color
## they're drawn in: set a Button's icon colors or a TextureRect's
## self_modulate to Tokens.INK on parchment, Tokens.SYS_TEXT on the machine.
##
##     button.icon = Icons.get_icon(&"will")

const DIR := "res://assets/sprites/ui/icons/%s.png"
const NAMES: Array[StringName] = [
	&"will", &"role", &"whisper", &"vote", &"chat", &"dead", &"day", &"night",
	&"time", &"host", &"customize", &"paste", &"copy", &"leave", &"close", &"send",
]


static func get_icon(icon: StringName) -> Texture2D:
	return load(DIR % icon)
