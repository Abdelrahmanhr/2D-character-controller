extends CanvasLayer

@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Panel
@onready var menu: VBoxContainer = $Panel/Menu
@onready var options_panel: Panel = $Panel/OptionsPanel
@onready var title_bar: Label = $Panel/TitleBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim.hide()
	panel.hide()
	# The frame's title bar names the page, so the options page's own heading is redundant here.
	# (The main menu steals OptionsPanel before this script ever runs, so its heading stays.)
	$Panel/OptionsPanel/OptionsLayout/Title.hide()
	$Panel/Menu/ResumeButton.pressed.connect(_resume)
	$Panel/CloseButton.pressed.connect(_resume)
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
		if not Networking.is_connected_online():
			# Soft pause: bomb timers freeze and input is ignored, but the arena,
			# music and particles keep running. Online we deliberately do neither -
			# bomb time is wall-clock derived and would silently drain, and one
			# player must never be able to freeze the match for everyone else.
			MinigameDirector.lock_input(MinigameDirector.LOCK_MENU)
			MinigameDirector.set_timers_frozen(true)
		_cascade_page(menu)

func _resume() -> void:
	options_panel.hide()
	menu.show()
	title_bar.text = "PAUSED"
	panel.hide()
	dim.hide()
	_release_soft_pause()

func _restart() -> void:
	_release_soft_pause()
	Networking.restart_game()

func _show_options() -> void:
	menu.hide()
	options_panel.show()
	title_bar.text = "OPTIONS"
	_cascade_page($Panel/OptionsPanel/OptionsLayout)

func _hide_options() -> void:
	options_panel.hide()
	menu.show()
	title_bar.text = "PAUSED"
	_cascade_page(menu)

func _exit_game() -> void:
	Networking.leave_lobby()
	_release_soft_pause()
	SceneTransition.circle_to("res://scenes/main_menu.tscn")

func _release_soft_pause() -> void:
	MinigameDirector.unlock_input(MinigameDirector.LOCK_MENU)
	MinigameDirector.set_timers_frozen(false)
	get_tree().paused = false


func _cascade_page(page: Control) -> void:
	var elements: Array[Control] = []
	for child in page.get_children():
		if child is Control and child.visible:
			elements.append(child)
	UICascade.reset(elements)
	UICascade.slam_panel(panel, 0.20)
	await get_tree().process_frame
	if is_inside_tree():
		UICascade.play(elements, 0.0, 0.055)


func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
