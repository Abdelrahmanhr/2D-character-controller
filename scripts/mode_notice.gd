extends CanvasLayer
class_name ModeNotice

## Shown by main_menu.gd before entering Singleplayer or Tutorial, since neither
## mode is finished yet. Deliberately doesn't know which mode was picked or where
## to go next -- the caller adds this as a child and connects `confirmed`, so the
## actual routing decision (and any LocalPlayers setup that differs per mode)
## stays owned by main_menu.gd rather than being duplicated or passed in here.
signal confirmed

@onready var ok_button: Button = $Panel/Box/OkButton


func _ready() -> void:
	ok_button.pressed.connect(_on_ok_pressed)


## OK is the only thing this dialog can do, so ui_cancel (Escape, or B/Circle now
## that menus are pad-navigable) dismisses it rather than being a dead key. Taken
## in _input, not _unhandled_input: the host scene behind this also listens for
## ui_cancel, and a modal has to consume the press before the screen it covers
## gets a look at it.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_ok_pressed()


func _on_ok_pressed() -> void:
	# Free immediately rather than waiting on whatever scene transition the
	# caller's `confirmed` handler kicks off next (a crossfade, unlike
	# change_scene_to_file, doesn't free the old tree instantly).
	queue_free()
	confirmed.emit()
