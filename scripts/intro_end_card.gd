extends CanvasLayer

## Teaser end card. Stays hidden until the timeline calls show_card(), so the
## cutscene can land it on the beat after the mushroom settles rather than having
## it keyed frame by frame.
##
## Sits on its own CanvasLayer above the grade, so the panel keeps the crisp UI
## palette instead of picking up the vignette and the split tone.
##
## Deliberately does NOT use UICascade: the house pop ladder snaps on twos, which
## is right for in-game UI landing over a match and wrong for the last shot of a
## teaser. This settles inward instead - a hair oversized and transparent, easing
## down onto its resting size.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## How much larger than rest the panel starts. Small on purpose: this is a camera
## settling, not a UI element popping.
const START_SCALE := 1.06
const SETTLE := 0.5

@onready var _panel: Panel = $Panel
@onready var _play: Button = $Panel/Box/PlayButton
@onready var _sub: Label = $Panel/Box/Sub


func _ready() -> void:
	hide()
	_play.pressed.connect(_on_play_pressed)


## Cutscene hook. A no-op once it is already up, so scrubbing the timeline
## backwards and forwards cannot stack tweens on the panel.
func show_card() -> void:
	if visible:
		return
	show()
	# Containers size their children a frame after they are shown, so neither the
	# resting size nor the pivot below is final until this returns.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# The pivot is authored in the scene, because a Control under a hidden
	# CanvasLayer has not been laid out yet and still reports size (0, 0) here -
	# which would put the pivot back in the top-left corner and make the panel
	# scale out of it sideways. Only recompute once layout has actually run.
	if _panel.size != Vector2.ZERO:
		_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * START_SCALE
	_panel.modulate.a = 0.0
	_play.modulate.a = 0.0
	_sub.modulate.a = 0.0
	# Focused up front so the button fades in already lit, rather than snapping
	# to its focus style once the tween lands.
	_play.grab_focus()

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2.ONE, SETTLE)
	tw.tween_property(_panel, "modulate:a", 1.0, SETTLE * 0.7)
	tw.tween_property(_play, "modulate:a", 1.0, 0.3).set_delay(0.12)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.3).set_delay(0.22)
	await tw.finished
	if not is_inside_tree():
		return

	var breathe := _sub.create_tween().set_loops()
	breathe.set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_sub, "modulate:a", 0.62, 1.1)
	breathe.tween_property(_sub, "modulate:a", 1.0, 1.1)


func _on_play_pressed() -> void:
	# Same track the menu is about to ask for, so this does not restart anything -
	# it just fades the cutscene's louder level down to the menu's. Done here rather
	# than in main_menu._ready so the drop plays out under the circle wipe instead
	# of landing after the menu is already up.
	MusicManager.play_id(&"menu")
	SceneTransition.circle_to(MENU_SCENE)
