extends CanvasLayer

const MAX_R := 1.6

@onready var rect: ColorRect = $Rect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 100
	rect.material.set_shader_parameter("radius", MAX_R)
	_mat = rect.material
	_update_aspect()
	get_viewport().size_changed.connect(_update_aspect)

func _update_aspect() -> void:
	var s := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", s.x / s.y)

func circle_to(scene_path: String, duration: float = 0.5) -> void:
	rect.visible = true
	var tw := create_tween()
	tw.tween_method(_set_radius, MAX_R, 0.0, duration)
	await tw.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_method(_set_radius, 0.0, MAX_R, duration)
	await tw2.finished
	rect.visible = false

func _set_radius(r: float) -> void:
	_mat.set_shader_parameter("radius", r)
