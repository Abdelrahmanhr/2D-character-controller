extends Camera2D

@export var margin: float = 150.0
@export var min_zoom: float = 0.6  
@export var max_zoom: float = 1.4 
@export var position_lerp_speed: float = 5.0
@export var zoom_lerp_speed: float = 4.0
@export var world_bounds: Rect2 = Rect2(100, 100, 2200, 1200)
@export var center_point: Vector2 = Vector2.ZERO
@export var top_ui_margin: float = 160.0  # NEW: screen-space pixels reserved at the top for the minigame UI
@export var shake_duration: float = 0.4  # NEW: matches the 8-frame explode animation at speed 20

var _base_offset_y := 0.0  # NEW: the UI-band offset, kept separate so shake never feeds back into its lerp
var _shake := 0.0
var _shake_left := 0.0
var _shake_span := 0.0


func shake(amount: float = 10.0, duration: float = -1.0) -> void:  # NEW: strongest active shake wins, so overlapping hits do not stack into a mess
	_shake = maxf(_shake, amount)
	_shake_left = maxf(_shake_left, duration if duration > 0.0 else shake_duration)
	_shake_span = maxf(_shake_span, _shake_left)

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var live_positions: Array[Vector2] = []
	for p in players:
		if is_instance_valid(p) and not p.is_dead:
			live_positions.append(p.global_position)
	if live_positions.is_empty():
		_apply_shake(delta, zoom.x)  # NEW: keep shaking while every player is mid-death, instead of freezing it until respawn
		return

	var min_pos: Vector2 = live_positions[0]
	var max_pos: Vector2 = live_positions[0]
	for pos in live_positions:
		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)

	var box_center: Vector2 = (min_pos + max_pos) / 2.0
	var box_size: Vector2 = (max_pos - min_pos) + Vector2(margin, margin) * 2.0
	box_size.x = maxf(box_size.x, 1.0)
	box_size.y = maxf(box_size.y, 1.0)

	var viewport_size: Vector2 = get_viewport_rect().size
	var available_size: Vector2 = viewport_size - Vector2(0.0, top_ui_margin)  # NEW: usable screen space, excluding the UI band
	available_size.y = maxf(available_size.y, 1.0)  # NEW: safety floor
	var fit_zoom: Vector2 = available_size / box_size  # CHANGED: was "viewport_size / box_size"
	var target_zoom_scalar: float = clampf(minf(fit_zoom.x, fit_zoom.y), min_zoom, max_zoom)
	var target_zoom := Vector2(target_zoom_scalar, target_zoom_scalar)

	var visible_half_size: Vector2 = (viewport_size / target_zoom_scalar) / 2.0
	var bounds := _framing_bounds()
	var target_center := box_center
	if bounds.size.x >= visible_half_size.x * 2.0:
		target_center.x = clampf(target_center.x, bounds.position.x + visible_half_size.x, bounds.end.x - visible_half_size.x)
	else:
		target_center.x = bounds.position.x + bounds.size.x / 2.0
	if bounds.size.y >= visible_half_size.y * 2.0:
		target_center.y = clampf(target_center.y, bounds.position.y + visible_half_size.y, bounds.end.y - visible_half_size.y)
	else:
		target_center.y = bounds.position.y + bounds.size.y / 2.0

	global_position = global_position.lerp(target_center, clampf(position_lerp_speed * delta, 0.0, 1.0))
	zoom = zoom.lerp(target_zoom, clampf(zoom_lerp_speed * delta, 0.0, 1.0))
	_base_offset_y = lerpf(_base_offset_y, -(top_ui_margin * 0.5) / target_zoom_scalar, clampf(zoom_lerp_speed * delta, 0.0, 1.0))  # NEW: shifts framing down so the reserved band stays empty at the top
	_apply_shake(delta, target_zoom_scalar)


func _framing_bounds() -> Rect2:
	if center_point == Vector2.ZERO:
		return world_bounds
	return Rect2(center_point - world_bounds.size * 0.5, world_bounds.size)


func _apply_shake(delta: float, zoom_scalar: float) -> void:
	_shake_left = maxf(_shake_left - delta, 0.0)  # NEW: eases out evenly across the animation instead of ending early
	var falloff: float = (_shake_left / _shake_span) if _shake_span > 0.0 else 0.0
	var jolt: float = _shake * falloff / maxf(zoom_scalar, 0.01)  # NEW: keeps the shake the same size on screen at any zoom
	offset = Vector2(0.0, _base_offset_y) + Vector2(randf_range(-jolt, jolt), randf_range(-jolt, jolt))
