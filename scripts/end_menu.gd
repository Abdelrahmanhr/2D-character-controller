extends CanvasLayer

enum Outcome { WIN, LOSE, DRAW }

## Result stings. These reuse in-match cues pitched down, so the result reads as
## a heavier version of a sound the player already knows. Deliberately mixed
## below the action (the loud one-shots in this game sit at -10 to -6) and with
## no pitch variance - a result should sound identical every time.
@export var win_sound: AudioStream = preload("res://resources/audio/Minigame Complete .wav")
@export var lose_sound: AudioStream = preload("res://resources/audio/Time Penalty.wav")
@export var draw_sound: AudioStream = preload("res://resources/audio/Bonus Time.wav")
@export var win_volume_db: float = -12.0
@export var lose_volume_db: float = -12.0
@export var draw_volume_db: float = -13.0
@export var win_pitch: float = 0.9
@export var lose_pitch: float = 0.75
@export var draw_pitch: float = 0.85

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
			SfxManager.play(win_sound, win_volume_db, 0.0, win_pitch)
		Outcome.DRAW:
			UIParticles.lose(self, rect, UIParticles.FLARE)
			SfxManager.play(draw_sound, draw_volume_db, 0.0, draw_pitch)
		_:
			UIParticles.lose(self, rect)
			SfxManager.play(lose_sound, lose_volume_db, 0.0, lose_pitch)

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
