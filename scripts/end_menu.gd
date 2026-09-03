extends CanvasLayer

@onready var title_label: Label = $Panel/Box/Title

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Panel/Box/RestartButton.pressed.connect(_on_restart)
	$Panel/Box/MainMenuButton.pressed.connect(_on_main_menu)
	$Panel/Box/ExitButton.pressed.connect(_on_exit)

func set_result(title: String, _color: Color) -> void:
	title_label.text = title

func _on_restart() -> void:
	get_tree().paused = false
	Networking.restart_game()

func _on_main_menu() -> void:
	get_tree().paused = false
	SceneTransition.circle_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	get_tree().quit()
