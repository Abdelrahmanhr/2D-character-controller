extends Control

const EMPTY_LEVEL_SCENE := "res://scenes/empty_level.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const END_SCENE := "res://scenes/end.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

func _ready() -> void:
	$Menu/StartButton.pressed.connect(_on_start_pressed)
	$Menu/CreditsButton.pressed.connect(_on_credits_pressed)
	$Menu/EndButton.pressed.connect(_on_end_pressed)
	$Menu/ExitButton.pressed.connect(_on_exit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)

func _on_end_pressed() -> void:
	get_tree().change_scene_to_file(END_SCENE)

func _on_exit_pressed() -> void:
	get_tree().quit()