extends CanvasLayer

enum Outcome { WIN, LOSE, DRAW }

@onready var title_label: Label = $Panel/Box/Title
@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Panel/Box/RestartButton.pressed.connect(_on_restart)
	$Panel/Box/MainMenuButton.pressed.connect(_on_main_menu)
	$Panel/Box/ExitButton.pressed.connect(_on_exit)

## The results own the escape key, so the pause menu cannot stack on top of them
## now that the tree is no longer paused underneath.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

func set_result(title: String, color: Color, outcome: int = Outcome.WIN) -> void:
	title_label.text = title
	title_label.add_theme_color_override("font_color", color)
	_play_entrance(outcome)

func _play_entrance(outcome: int) -> void:
	var elements: Array[Control] = [
		$Panel/TitleBar, title_label,
		$Panel/Box/RestartButton, $Panel/Box/MainMenuButton, $Panel/Box/ExitButton,
	]
	UICascade.reset(elements)
	dim.modulate.a = 0.0
	# One frame so the VBoxContainer has sized its children; scaling around a
	# pivot of (0,0) would otherwise grow each row out of its top-left corner.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	create_tween().tween_property(dim, "modulate:a", 1.0, 0.18)
	UICascade.slam_panel(panel)
	_shake_camera()
	_spawn_result_fx(outcome)
	UICascade.play(elements, UICascade.PANEL_SLAM * 0.55)

	await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		$Panel/Box/RestartButton.grab_focus()

func _shake_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.18)

func _spawn_result_fx(outcome: int) -> void:
	var rect := panel.get_global_rect()
	match outcome:
		Outcome.WIN:
			UIParticles.win(self, rect)
		Outcome.DRAW:
			UIParticles.lose(self, rect, UIParticles.FLARE)
		_:
			UIParticles.lose(self, rect)

func _on_restart() -> void:
	get_tree().paused = false
	Networking.restart_game()

func _on_main_menu() -> void:
	Networking.leave_lobby()
	get_tree().paused = false
	SceneTransition.circle_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	Networking.leave_lobby()
	get_tree().quit()
