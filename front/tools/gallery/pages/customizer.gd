extends GalleryPage

## The customizer ("subject setup") on its Body tab and its House tab, laid
## out in the menus' 1280x720 units (720x1280 on a phone).

const CUSTOMIZER := preload("res://scenes/main/customizer.tscn")

var _variant := ""


func _init() -> void:
	layer = "menu"
	variants = ["body", "house"]
	settle_frames = 20


func build(stage: Control, variant: String) -> void:
	_variant = variant
	stage.add_child(CUSTOMIZER.instantiate())


func after_settle(stage: Control) -> void:
	if _variant == "house":
		var tabs: TabContainer = stage.get_child(0)._tabs
		tabs.current_tab = tabs.get_tab_count() - 1
