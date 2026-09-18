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


func _on_ok_pressed() -> void:
	# Free immediately rather than waiting on whatever scene transition the
	# caller's `confirmed` handler kicks off next (a crossfade, unlike
	# change_scene_to_file, doesn't free the old tree instantly).
	queue_free()
	confirmed.emit()
