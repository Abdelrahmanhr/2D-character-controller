extends Node2D
class_name ArenaBase

const PLAYER = preload("uid://dg4t5o3xnmwxn")

const LOSE_POPUP := preload("res://scenes/lose_popup.tscn")
const END_MENU := preload("res://scenes/end_menu.tscn")

var players: Array[CharacterBody2D]
var _spectate_overlay: CanvasLayer
var _end_menu: CanvasLayer

@export var safe_zone_event_interval_min: float = 5.0  # NEW
@export var safe_zone_event_interval_max: float = 10.0  # NEW
@export var safe_zone_active_duration: float = 20.0  # NEW
@export var safe_zone_start_radius: float = 1200.0  # NEW
@export var safe_zone_end_radius: float = 220.0  # NEW
@export var safe_zone_gravity_multiplier: float = 0.6  # NEW
@export var safe_zone_outside_death_time: float = 3.0  # NEW
@export var safe_zone_hold_duration: float = 10.0  # NEW

## Singleplayer turns the pressure up: alone against bots, the stock intervals
## leave long dead stretches. Applied in _ready so multiplayer keeps the values
## that were actually playtested. Arenas with their own hazards extend this (see
## power_station.gd).
const SINGLEPLAYER_SAFE_ZONE_INTERVAL := Vector2(3.0, 6.0)
const SINGLEPLAYER_SAFE_ZONE_HOLD := 7.0

## One per bot slot, so the three of them do not solve in lockstep and expire
## together - the player needs a weakest one to outlast. Indexed by spawn order.
const BOT_REACTION_TIMES: Array[float] = [0.32, 0.45, 0.62]

## How far inside the outermost spawn points bots keep themselves.
const BOT_BOUNDS_MARGIN := 90.0

enum Outcome { WIN, LOSE, DRAW }

@export_group("Match outro")
@export var celebration_delay: float = 0.30
@export var outro_delay: float = 0.60
@export var corpse_fade_duration: float = 0.9
@export var win_focus_zoom: float = 1.7
@export var win_focus_screen_offset: Vector2 = Vector2(210.0, 0.0)  # NEW: winner lands this many px off screen center; scenes/end_menu.tscn's Panel is centered on the same point (+80 lower) so the winner reads as inside the panel

var _active_zone: SafeZone = null  # NEW
var _active_zone_spawn_index: int = -1  # NEW
var _next_zone_event_ms: int = -1  # NEW

## Shared across every "weather" style event (safe zone, lightning strike, ...) so at
## most one of them can ever run at a time. Owning code sets this true when its event
## starts and false when it fully ends; every scheduler checks it before starting.
var _weather_event_active: bool = false

@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var match_result: Label = $MatchResult
@onready var spawn_points: Array[Node2D] = [$SpawnPoint1, $SpawnPoint2, $SpawnPoint3, $SpawnPoint4]


func _ready() -> void:
	_apply_singleplayer_tuning()
	_set_global_parallax_active(false)
	MusicManager.play_id(_music_id())
	$PauseMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_layout_viewport_content)
	_layout_viewport_content()
	MinigameDirector.reset_match()
	MinigameDirector.match_finished.connect(_on_match_finished)
	MinigameDirector.match_started.connect(_on_match_started_for_zone)  # NEW
	_setup_minigame_screens()
	multiplayer_spawner.spawn_function = _spawn_player
	$DeathBox.body_entered.connect(_on_death_zone_body_entered)

	if not _is_networked():
		if LocalPlayers.joined_devices.size() > 0:
			_spawn_local_players()
		else:
			_spawn_local_player()
		return

	Networking.arena_spawn_requested.connect(_on_arena_spawn_requested)
	Networking.disconnected.connect(_on_disconnected)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Networking.notify_arena_ready()


## Overridden by arenas with extra hazards of their own; call super() first.
func _apply_singleplayer_tuning() -> void:
	if not LocalPlayers.singleplayer:
		return
	safe_zone_event_interval_min = SINGLEPLAYER_SAFE_ZONE_INTERVAL.x
	safe_zone_event_interval_max = SINGLEPLAYER_SAFE_ZONE_INTERVAL.y
	safe_zone_hold_duration = SINGLEPLAYER_SAFE_ZONE_HOLD


## Spots the arena has telegraphed as about to become dangerous, for bots to step
## away from. Empty here; arenas with a strike warning override it, which is why
## BotController never has to know what lightning is.
func get_danger_positions() -> PackedVector2Array:
	return PackedVector2Array()


## The x band bots should stay inside, as (min, max). Derived from the spawn
## points because they are the one thing every arena has that is guaranteed to
## be standable and inside the map - wandering past the outermost one is how
## bots found the DeathBox.
func get_play_bounds_x() -> Vector2:
	if spawn_points.is_empty():
		return Vector2(-INF, INF)
	var low: float = spawn_points[0].global_position.x
	var high: float = low
	for point in spawn_points:
		low = minf(low, point.global_position.x)
		high = maxf(high, point.global_position.x)
	# Inset, because the outermost spawn points sit close enough to the drop that
	# a bot wandering to exactly that x still walks off the lip.
	return Vector2(low + BOT_BOUNDS_MARGIN, high - BOT_BOUNDS_MARGIN)


## Which MusicManager track this arena plays. Overridden per arena; the default
## keeps a new arena scene from being silent before anyone scores one.
func _music_id() -> StringName:
	return &"arena_default"


func _process(delta: float) -> void:  # NEW
	if not is_inside_tree():
		return
	_update_safe_zone_schedule()


func _is_zone_authority() -> bool:  # NEW
	return not _is_networked() or multiplayer.is_server()


func _get_timestamp() -> int:  # NEW
	return MinigameDirector.get_hazard_time_ms()


func _on_match_started_for_zone() -> void:  # NEW
	if _is_zone_authority():
		_schedule_next_zone_event()


func _schedule_next_zone_event() -> void:  # NEW
	var wait: float = randf_range(safe_zone_event_interval_min, safe_zone_event_interval_max)
	_next_zone_event_ms = _get_timestamp() + int(wait * 1000.0)


func _update_safe_zone_schedule() -> void:  # NEW
	if MinigameDirector.is_match_finished() or MinigameDirector.is_input_locked():
		return
	if not _is_zone_authority():
		return
	if _active_zone != null or _next_zone_event_ms < 0 or _weather_event_active:
		return
	if _get_timestamp() >= _next_zone_event_ms:
		var index: int = randi() % spawn_points.size()
		if _is_networked():
			_start_safe_zone_event.rpc(index)
		else:
			_start_safe_zone_event(index)


@rpc("authority", "call_local", "reliable")
func _start_safe_zone_event(spawn_index: int) -> void:
	if spawn_index < 0 or spawn_index >= spawn_points.size():
		return
	if MinigameDirector.is_match_finished():
		return
	var zone := SafeZone.new()
	zone.name = "SafeZoneEvent"
	zone.z_index = 10
	zone.global_position = spawn_points[spawn_index].global_position
	zone.start_radius = safe_zone_start_radius
	zone.end_radius = safe_zone_end_radius
	zone.shrink_duration = safe_zone_active_duration
	zone.hold_duration = safe_zone_hold_duration  
	zone.outer_gravity_multiplier = safe_zone_gravity_multiplier
	zone.outside_death_time = safe_zone_outside_death_time
	add_child(zone)
	zone.expired.connect(_on_safe_zone_expired)
	zone.activate()
	_active_zone = zone
	_active_zone_spawn_index = spawn_index
	_weather_event_active = true


## Retires the live zone without touching SafeZone.gd. Leaving the group is what
## actually stops the kill - Player._get_safe_zone() resolves through it, so every
## outside-timer resets on the next tick.
func _dismiss_safe_zone() -> void:
	_next_zone_event_ms = -1
	var zone := _active_zone
	_active_zone = null
	_active_zone_spawn_index = -1
	_weather_event_active = false
	if zone == null or not is_instance_valid(zone):
		return
	if zone.expired.is_connected(_on_safe_zone_expired):
		zone.expired.disconnect(_on_safe_zone_expired)
	zone.remove_from_group("safe_zones")
	zone.set_process(false)
	# SafeZone parents its overlay to the current scene rather than to itself, so
	# freeing the zone alone would strand it. It is named, so we can find it.
	var overlay := get_tree().current_scene.get_node_or_null("SafeZoneOverlayLayer") as CanvasLayer
	if overlay:
		_fade_out_overlay(overlay)
	zone.queue_free()


func _fade_out_overlay(layer: CanvasLayer) -> void:
	var target: CanvasItem = null
	for child in layer.get_children():
		if child is CanvasItem:
			target = child
			break
	if target == null:
		layer.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(target, "modulate:a", 0.0, 0.35)
	tw.tween_callback(layer.queue_free)


func _on_safe_zone_expired() -> void:  # NEW
	_active_zone = null
	_active_zone_spawn_index = -1
	_weather_event_active = false
	if _is_zone_authority():
		_schedule_next_zone_event()


func _exit_tree() -> void:
	_set_global_parallax_active(true)


# Every arena draws its own LocalParallax, so the GlobalParallax autoload sitting at
# layer -10 underneath it is 15 full-screen quads of pure overdraw, repositioned
# every frame. Park it for the duration of the match.
func _set_global_parallax_active(active: bool) -> void:
	var global_parallax := get_node_or_null("/root/GlobalParallax") as CanvasLayer
	if global_parallax == null:
		return
	global_parallax.visible = active
	global_parallax.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _on_arena_spawn_requested(slots: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for peer_id in slots.keys():
		multiplayer_spawner.spawn({"peer": int(peer_id), "slot": int(slots[peer_id])})


func _setup_minigame_screens() -> void:
	var layout := get_node_or_null("MinigameLayout/Layout")
	if layout == null:
		return
	var screens := MinigameScreens.new()
	screens.name = "MinigameScreens"
	add_child(screens)
	screens.build(layout)
	MinigameDirector.match_started.connect(screens.play_entrance)


func _on_disconnected(message: String) -> void:
	NetDebug.log_event("returned to menu: %s" % message)
	get_tree().paused = false
	MinigameDirector.reset_match()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")


func _layout_viewport_content() -> void:
	var viewport_size := get_viewport_rect().size
	match_result.position = (viewport_size - match_result.size) / 2.0


func _is_networked() -> bool:
	# Guards against _process (still ticking mid-teardown on quit/restart, after this
	# node has already left the tree) touching get_multiplayer() once it's gone null.
	if not is_inside_tree():
		return false
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


## Couch-only: slot -> device_id -> whatever was typed into that device's lobby
## slot, same P<n> fallback as everywhere else. joined_devices is ordered the
## same way _spawn_local_players spawned from it, so index == slot.
func _couch_display_name(slot: int) -> String:
	if slot >= 0 and slot < LocalPlayers.joined_devices.size():
		return LocalPlayers.get_display_name(LocalPlayers.joined_devices[slot], slot)
	return "P%d" % (slot + 1)


func _on_death_zone_body_entered(body: Node) -> void:
	# The match is over; nobody dies during the victory lap.
	if MinigameDirector.is_match_finished():
		return
	if body is CharacterBody2D and not body.is_dead:
		_play_death_zone_zap(body.global_position)
	if body is CharacterBody2D and (not _is_networked() or body.is_multiplayer_authority()) and not body.is_dead:
		body.get_node("BombController").player_died() 


@export var death_zap_sound: AudioStream
@export var death_zap_volume_db: float = -6.0


func _play_death_zone_zap(at: Vector2) -> void:
	if death_zap_sound:
		SfxManager.play(death_zap_sound, death_zap_volume_db, 0.12)
	var rail := get_tree().get_first_node_in_group("lightning_emitters")
	if rail and rail.has_method("strike_global"):
		rail.strike_global(Vector2(at.x, rail.global_position.y), at)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(14.0)


func show_lose_popup() -> void:
	if _spectate_overlay or _end_menu:
		return
	_spectate_overlay = LOSE_POPUP.instantiate()
	add_child(_spectate_overlay)


func _on_match_finished(winner_peer_id: int) -> void:
	if _spectate_overlay:
		_spectate_overlay.queue_free()
		_spectate_overlay = null
	_dismiss_safe_zone()

	var title: String
	var color: Color
	var outcome: Outcome

	if winner_peer_id == 0:
		title = "DRAW"
		color = Color(1, 0.8784, 0.5686, 1)
		outcome = Outcome.DRAW
	elif not _is_networked():
		var winner_slot: int = winner_peer_id - 1
		var winner_color: Color = BombController.PLAYER_COLORS[clampi(winner_slot, 0, 3)]
		title = "%s WINS!" % _couch_display_name(winner_slot)
		color = winner_color
		# One shared screen, so there is no per-viewer loser to show ash to.
		outcome = Outcome.WIN
	else:
		if winner_peer_id == multiplayer.get_unique_id():
			title = "YOU WIN"
			color = Color(0.549, 1, 0.6078, 1)
			outcome = Outcome.WIN
		else:
			title = "YOU LOSE"
			color = Color(1, 0.4118, 0.3529, 1)
			outcome = Outcome.LOSE

	# Deliberately no get_tree().paused: MinigameDirector has already frozen every
	# bomb and locked input, so the arena can keep breathing behind the results.
	_begin_outro(winner_peer_id, title, color, outcome)


func _begin_outro(winner_peer_id: int, title: String, color: Color, outcome: Outcome) -> void:
	_send_off_the_fallen()
	await get_tree().create_timer(celebration_delay).timeout
	if not is_inside_tree():
		return
	_celebrate_winner(winner_peer_id)
	await get_tree().create_timer(maxf(outro_delay - celebration_delay, 0.0)).timeout
	if not is_inside_tree() or _end_menu != null:
		return
	_end_menu = END_MENU.instantiate()
	add_child(_end_menu)
	_end_menu.set_result(title, color, int(outcome))


func _celebrate_winner(winner_peer_id: int) -> void:
	if winner_peer_id == 0:
		return
	var winner := get_node_or_null(str(winner_peer_id)) as CharacterBody2D
	if winner == null or winner.is_dead:
		return
	# Purely local/visual, so every peer zooms in - unlike play_celebration below,
	# which is authority-gated because it drives the winner's own physics.
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("focus_on"):
		cam.focus_on(winner, win_focus_screen_offset, win_focus_zoom)
	if _is_networked() and not winner.is_multiplayer_authority():
		return
	if winner.has_method("play_celebration"):
		winner.play_celebration()


func _send_off_the_fallen() -> void:
	for player in players:
		if not is_instance_valid(player) or not player.is_dead:
			continue
		UIParticles.wisp(self, player.global_position)
		var tw := create_tween()
		tw.tween_interval(0.05)
		tw.tween_property(player, "modulate:a", 0.0, corpse_fade_duration)


func _spawn_local_player() -> void:
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = "1"
	player.position = spawn_points[0].position
	add_child(player)
	players.append(player)


func _spawn_player(data: Variant) -> Node:
	var peer_id: int = int(data["peer"])
	var slot: int = int(data["slot"])
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = str(peer_id)
	player.position = spawn_points[slot % spawn_points.size()].position
	for other in players.duplicate():
		if not is_instance_valid(other) or not other is PhysicsBody2D:
			players.erase(other)
			continue
		player.add_collision_exception_with(other)
		other.add_collision_exception_with(player)
	players.append(player)
	return player


func _on_peer_disconnected(peer_id: int) -> void:
	MinigameDirector.player_disconnected(peer_id)
	var player := get_node_or_null(str(peer_id))
	if player:
		players.erase(player)
		player.queue_free()


func _spawn_local_players() -> void:
	var devices := LocalPlayers.joined_devices
	# Defaults to 1, which would start the countdown on the first registration
	# rather than once the whole roster is in. Harmless while everyone spawns in
	# one frame, but singleplayer depends on all four being counted.
	MinigameDirector.set_expected_player_count(devices.size())
	for i in devices.size():
		var device_id: int = devices[i]
		var player := PLAYER.instantiate() as CharacterBody2D
		player.name = str(i + 1)
		player.device_id = device_id
		player.position = spawn_points[i % spawn_points.size()].position

		for other in players.duplicate():
			if not is_instance_valid(other) or not other is PhysicsBody2D:
				players.erase(other)
				continue
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)

		add_child(player)
		var bomb_controller: Node = player.get_node("BombController")
		bomb_controller.device_id = device_id
		if LocalPlayers.is_bot(device_id):
			var brain := BotController.new()
			brain.name = "BotController"
			brain.reaction_time = BOT_REACTION_TIMES[i % BOT_REACTION_TIMES.size()]
			player.add_child(brain)
			player.bot = brain
		players.append(player)


func respawn_player(player: CharacterBody2D) -> void:
	var target_index: int  # NEW
	if _active_zone != null and _active_zone_spawn_index >= 0:  # NEW: respawn at the event's location while it's active
		target_index = _active_zone_spawn_index  # NEW
	else:  # NEW
		target_index = player.get_node("BombController").get_slot_index()  # CHANGED: was inlined directly below
	player.global_position = spawn_points[target_index % spawn_points.size()].global_position
