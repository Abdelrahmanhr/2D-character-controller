extends "res://scripts/power_station.gd"

const SHIELD_WALK_DISTANCE: float = 110.0

var practice: bool = false

var _director: TutorialDirector = null


func _ready() -> void:
	_seed_roster_if_launched_directly()
	practice = LocalPlayers.tutorial_practice
	super()
	if practice:
		_install_practice_banners()
		return
	MinigameDirector.auto_serve = false
	_disarm_bombs()
	_install_puppets()
	_director = TutorialDirector.new()
	_director.name = "TutorialDirector"
	add_child(_director)


func _seed_roster_if_launched_directly() -> void:
	if not LocalPlayers.joined_devices.is_empty():
		return
	LocalPlayers.singleplayer = true
	LocalPlayers.tutorial_practice = false
	LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
	LocalPlayers.add_bots(2)


func _exit_tree() -> void:
	super()
	MinigameDirector.auto_serve = true


func _disarm_bombs() -> void:
	for player in players:
		if not is_instance_valid(player):
			continue
		var bomb := player.get_node_or_null("BombController") as BombController
		if bomb:
			bomb.lethal = false


func _install_puppets() -> void:
	for player in players:
		if not is_instance_valid(player) or player.bot == null:
			continue
		var stock: Node = player.bot
		player.bot = null
		stock.queue_free()
		var puppet := TutorialPuppet.new()
		puppet.name = "TutorialPuppet"
		player.add_child(puppet)
		player.bot = puppet


func _schedule_next_lightning_event() -> void:
	if practice:
		super()


func _schedule_next_zone_event() -> void:
	if practice:
		super()


func _schedule_next_shield_pickup() -> void:
	if practice:
		super()


func is_weather_busy() -> bool:
	return _weather_event_active or _active_zone != null


func pick_lightning_platform_away_from(away_from: Vector2) -> int:
	var best: int = -1
	var best_distance: float = -1.0
	for i in _lightning_platforms.size():
		var distance: float = _lightning_platforms[i].global_position.distance_to(away_from)
		if distance > best_distance:
			best_distance = distance
			best = i
	return best


func lightning_platform_position(index: int) -> Vector2:
	if index < 0 or index >= _lightning_platforms.size():
		return Vector2.ZERO
	return _lightning_platforms[index].global_position


func fire_lightning(index: int) -> void:
	if index < 0 or index >= _lightning_platforms.size() or is_weather_busy():
		return
	var strike_at: int = _get_timestamp() + int(lightning_warning_lead_time * 1000.0)
	_trigger_lightning_strike([index], strike_at)


func start_safe_zone(spawn_index: int) -> void:
	if is_weather_busy():
		return
	_start_safe_zone_event(spawn_index)


func dismiss_safe_zone() -> void:
	_dismiss_safe_zone()


func get_active_safe_zone() -> SafeZone:
	return _active_zone


func spawn_shield_at(position: Vector2) -> void:
	_spawn_shield_pickup(position)


func ground_spot_beside(from: Vector2, distance: float) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for side in [1.0, -1.0]:
		for shrink in [1.0, 0.65, 0.35]:
			var candidate: Vector2 = from + Vector2(side * distance * shrink, 0.0)
			var query := PhysicsRayQueryParameters2D.create(candidate, candidate + Vector2(0.0, 180.0))
			query.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty():
				return Vector2(candidate.x, hit["position"].y - 26.0)
	return from


func shield_position_near(from: Vector2) -> Vector2:
	if _lightning_platforms.is_empty():
		return from
	var best: int = 0
	var best_distance: float = INF
	for i in _lightning_platforms.size():
		var distance: float = _lightning_platforms[i].global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = i
	var anchor: Marker2D = _lightning_platforms[best]
	var half_width: float = maxf(_lightning_platform_widths[best] * 0.5 - shield_pickup_edge_margin, 0.0)
	var player_offset: float = from.x - anchor.global_position.x
	var away: float = 1.0 if player_offset <= 0.0 else -1.0
	var offset_x: float = clampf(player_offset + away * SHIELD_WALK_DISTANCE, -half_width, half_width)
	return anchor.global_position + Vector2(offset_x, -shield_pickup_hover_height)


func nearest_spawn_index(to: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for i in spawn_points.size():
		var distance: float = spawn_points[i].global_position.distance_to(to)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _begin_outro(winner_peer_id: int, title: String, color: Color, outcome: Outcome) -> void:
	if practice:
		super(winner_peer_id, title, color, outcome)
		return
	_send_off_the_fallen()
	await get_tree().create_timer(celebration_delay).timeout
	if not is_inside_tree():
		return
	_celebrate_winner(winner_peer_id)
	await get_tree().create_timer(maxf(outro_delay - celebration_delay, 0.0)).timeout
	if not is_inside_tree():
		return
	show_completion_menu()


func show_completion_menu() -> void:
	if _director:
		_director.show_completion()


func _install_practice_banners() -> void:
	var seen: Dictionary = {}
	var overlay := TutorialOverlay.new()
	overlay.name = "TutorialOverlay"
	overlay.banner_only = true
	add_child(overlay)

	for player in players:
		if not is_instance_valid(player) or player.bot != null:
			continue
		var bomb := player.get_node_or_null("BombController") as BombController
		if bomb == null:
			continue
		bomb.minigame_spawned.connect(func(instance: Control, _slot: int) -> void:
			var text: String = _first_time_banner(instance)
			if text.is_empty() or seen.has(text):
				return
			seen[text] = true
			overlay.show_banner(text))


func _first_time_banner(instance: Control) -> String:
	if instance is InputSequenceMinigame:
		return "INPUT SEQUENCE  -  press the arrow at the BOTTOM of the queue"
	if instance is ColorMatchMinigame:
		return "COLOR MATCH  -  press the side whose WORD names the colour in the middle"
	return ""
