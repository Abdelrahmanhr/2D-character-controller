extends Control

func _ready() -> void:
	$Menu/CreditsButton.pressed.connect(_on_credits_pressed)
	$Menu/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Menu/ExitButton.pressed.connect(_on_exit_pressed)

func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/credits.tscn")

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
