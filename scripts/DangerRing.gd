extends Node2D
class_name DangerRing

@export var radius: float = 6.0
@export var ring_width: float = 2.0
@export var background_color: Color = Color(0, 0, 0, 0.4)
@export var safe_ring_color: Color = Color(1.0, 0.95, 0.3, 1.0)
@export var danger_ring_color: Color = Color(1.0, 0.15, 0.1, 1.0)
@export var pulse_threshold: float = 0.75
@export var pulse_speed: float = 10.0
@export var screen_offset: Vector2 = Vector2(-35.0, -10.0)

var progress: float = 0.0
var _visible_state: bool = false
var _pulse_time: float = 0.0
var _overlay: Control
var _overlay_layer: CanvasLayer
var _follow_target: Node2D

func _ready() -> void:
	_follow_target = get_parent() as Node2D
	_setup_overlay()

func _setup_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "DangerRingOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "DangerRingLayer"
	_overlay_layer.layer = 6
	_overlay_layer.add_child(_overlay)
	get_tree().current_scene.add_child.call_deferred(_overlay_layer)

func _process(delta: float) -> void:
	if progress > pulse_threshold:
		_pulse_time += delta * pulse_speed
	else:
		_pulse_time = 0.0
	if _overlay and is_instance_valid(_follow_target):
		_overlay.queue_redraw()

func set_progress(value: float) -> void:
	var should_show: bool = value > 0.0
	if should_show != _visible_state:
		_visible_state = should_show
	progress = clampf(value, 0.0, 1.0)

func _draw_overlay() -> void:
	if not _visible_state or not is_instance_valid(_follow_target):
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view_center: Vector2 = cam.global_position + cam.offset
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_pos: Vector2 = (_follow_target.global_position - view_center) * cam.zoom + viewport_size / 2.0 + screen_offset

	_overlay.draw_arc(screen_pos, radius, 0.0, TAU, 48, background_color, ring_width + 2.0, true)
	if progress <= 0.0:
		return
	var remaining: float = 1.0 - progress
	var color: Color = safe_ring_color.lerp(danger_ring_color, progress)
	var pulse_alpha: float = 1.0
	if progress > pulse_threshold:
		pulse_alpha = 0.6 + 0.4 * absf(sin(_pulse_time))
	color.a *= pulse_alpha
	var start_angle: float = -PI / 2.0
	var end_angle: float = start_angle + TAU * remaining
	_overlay.draw_arc(screen_pos, radius, start_angle, end_angle, 48, color, ring_width, true)

func _exit_tree() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.queue_free()
