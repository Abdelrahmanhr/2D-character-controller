extends CanvasLayer

@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Panel
@onready var menu: VBoxContainer = $Panel/Menu
@onready var options_panel: Panel = $Panel/OptionsPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim.hide()
	panel.hide()
	$Panel/Menu/ResumeButton.pressed.connect(_resume)
	$Panel/Menu/RestartButton.pressed.connect(_restart)
	$Panel/Menu/OptionsButton.pressed.connect(_show_options)
	$Panel/Menu/ExitButton.pressed.connect(_exit_game)
	$Panel/OptionsPanel/OptionsLayout/BackButton.pressed.connect(_hide_options)
	$Panel/OptionsPanel/OptionsLayout/VolumeRow/VolumeSlider.value_changed.connect(_set_volume)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if options_panel.visible:
			_hide_options()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if panel.visible:
		_resume()
	else:
		dim.show()
		panel.show()
		get_tree().paused = true

func _resume() -> void:
	options_panel.hide()
	menu.show()
	panel.hide()
	dim.hide()
	get_tree().paused = false

func _restart() -> void:
	get_tree().paused = false
	Networking.restart_game()

func _show_options() -> void:
	menu.hide()
	options_panel.show()

func _hide_options() -> void:
	options_panel.hide()
	menu.show()

func _exit_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
