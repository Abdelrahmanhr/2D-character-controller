extends Control

func _ready() -> void:
	MusicManager.play_id(&"menu")
	$Menu/BackButton.pressed.connect(_on_back_pressed)

## ui_cancel is Escape and, since menus became pad-navigable, B/Circle. Backing
## out of a dead-end page is the other half of navigating to it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
