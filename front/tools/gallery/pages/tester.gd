extends GalleryPage

## The minigame tester, from the start screen's "practice evaluations":
## the list of games beside the panel, with the timing wheel picked.

const TESTER := preload("res://scenes/main/minigame_tester.tscn")


func _init() -> void:
	settle_frames = 30


func build(stage: Control, _variant: String) -> void:
	stage.add_child(TESTER.instantiate())
