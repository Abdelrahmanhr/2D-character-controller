extends CanvasLayer

func _ready() -> void:
	# The scene inherits its process mode, so it would freeze under the offline
	# pause menu while another player is still alive and spectating past it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel: Panel = $Panel
	var title: Label = $Panel/Box/Title
	var subtitle: Label = $Panel/Box/Subtitle
	UICascade.reset([title, subtitle])
	await get_tree().process_frame
	if not is_inside_tree():
		return
	UICascade.slam_panel(panel, 0.20)
	UICascade.play([title, subtitle], 0.10)
	UIParticles.lose(self, panel.get_global_rect())

	var breathe := subtitle.create_tween().set_loops()
	breathe.tween_property(subtitle, "modulate:a", 0.55, 0.8)
	breathe.tween_property(subtitle, "modulate:a", 1.0, 0.8)
