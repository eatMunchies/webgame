class_name House
extends StaticBody2D

## One lot in the town. With an appearance it shows that house, built from
## three layered sprites (see HouseCatalog), with the owner's name above the
## roof. Without one the lot is empty and shows a For Sale sign.
##
## The node's origin is where the front of the house meets the ground, like
## a character's feet, so y-sorting draws a player in front of the house or
## behind it. The yard sprite has z_index -1 so players walk on top of it.

@export var appearance: HouseAppearance:
	set(value):
		appearance = value
		if is_node_ready():
			refresh()
@export var owner_name := "":
	set(value):
		owner_name = value
		if is_node_ready():
			refresh()

@onready var _yard: Sprite2D = $Yard
@onready var _facade: Sprite2D = $Facade
@onready var _roof: Sprite2D = $Roof
@onready var _name_label: Label = $NameLabel
@onready var _walls: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	refresh()


## Redraws the lot from appearance and owner_name. Call after changing the
## appearance's fields in place.
func refresh() -> void:
	var empty := appearance == null
	if empty:
		_yard.texture = load(HouseCatalog.EMPTY_LOT)
		_facade.texture = null
		_roof.texture = null
	else:
		_yard.texture = HouseCatalog.texture("yard", appearance.yard)
		_facade.texture = HouseCatalog.texture("facade", appearance.facade)
		_roof.texture = HouseCatalog.texture("roof", appearance.roof)
	_name_label.text = owner_name
	_name_label.visible = not empty and owner_name != ""
	# Roofs differ in height, so sit the name just above this one.
	_name_label.position.y = _drawing_top() - _name_label.size.y
	# An empty lot has no walls to bump into. Collision changes have to wait
	# until the physics step is done, hence set_deferred.
	_walls.set_deferred("disabled", empty)


## The highest drawn pixel of the house, as a y relative to the node's
## origin (so negative). The yard is left out since it lies flat.
func _drawing_top() -> float:
	var top := 0.0
	for sprite: Sprite2D in [_facade, _roof]:
		if sprite.texture != null:
			top = minf(top, sprite.offset.y + sprite.texture.get_image().get_used_rect().position.y)
	return top
