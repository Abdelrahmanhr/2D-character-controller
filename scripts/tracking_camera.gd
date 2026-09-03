extends Camera2D

@export var margin: float = 150.0
@export var min_zoom: float = 0.6  
@export var max_zoom: float = 1.4 
@export var position_lerp_speed: float = 5.0
@export var zoom_lerp_speed: float = 4.0
@export var world_bounds: Rect2 = Rect2(100, 100, 2200, 1200)

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var live_positions: Array[Vector2] = []
	for p in players:
		if is_instance_valid(p) and not p.is_dead:
			live_positions.append(p.global_position)
	if live_positions.is_empty():
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
	var fit_zoom: Vector2 = viewport_size / box_size
	var target_zoom_scalar: float = clampf(minf(fit_zoom.x, fit_zoom.y), min_zoom, max_zoom)
	var target_zoom := Vector2(target_zoom_scalar, target_zoom_scalar)

	var visible_half_size: Vector2 = (viewport_size / target_zoom_scalar) / 2.0
	var target_center := box_center
	if world_bounds.size.x >= visible_half_size.x * 2.0:
		target_center.x = clampf(target_center.x, world_bounds.position.x + visible_half_size.x, world_bounds.end.x - visible_half_size.x)
	else:
		target_center.x = world_bounds.position.x + world_bounds.size.x / 2.0
	if world_bounds.size.y >= visible_half_size.y * 2.0:
		target_center.y = clampf(target_center.y, world_bounds.position.y + visible_half_size.y, world_bounds.end.y - visible_half_size.y)
	else:
		target_center.y = world_bounds.position.y + world_bounds.size.y / 2.0

	global_position = global_position.lerp(target_center, clampf(position_lerp_speed * delta, 0.0, 1.0))
	zoom = zoom.lerp(target_zoom, clampf(zoom_lerp_speed * delta, 0.0, 1.0))
