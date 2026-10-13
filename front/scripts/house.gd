extends StaticBody2D

@export var roof_color := Color(0.2, 0.3, 0.2)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Roof.color = roof_color
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
