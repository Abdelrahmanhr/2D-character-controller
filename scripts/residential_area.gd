extends ArenaBase


@export_group("Mood")
@export var ambient_tint: Color = Color(0.8706, 0.7412, 0.6863)

@export_group("Tiles")
# Lifted slightly to make up for the neon signs no longer spilling light on the tiles.
@export var tile_lift: float = 1.6
@export var tile_tint: Color = Color(1, 0.9686, 0.9333)

@export_group("Parallax")
@export var parallax_root: NodePath = ^"LocalParallax"

@export var parallax_tints: Array[Color] = [
	Color(0.9569, 0.6235, 0.4471),
	Color(0.5216, 0.4235, 0.5294),
	Color(0.4471, 0.3608, 0.4784),
	Color(0.3765, 0.3020, 0.4275),
	Color(0.2431, 0.1961, 0.3216),
	Color(0.1843, 0.1490, 0.2706),
]

@export_group("Dust")
@export var dust_path: NodePath = ^"DustMotes"
@export var dust_margin: float = 200.0

@export_group("Layer Shadow")
@export var shadow_layer_path: NodePath = ^"tiles/TileMapLayer"
# Off: this duplicated the 2,847-cell TileMapLayer at runtime for a fake drop
# shadow - a whole second rasterization of the largest layer. Flip back to true
# if the flat look turns out to matter.
@export var shadow_enabled: bool = false
@export_range(0, 8) var shadow_steps: int = 1
@export var shadow_offset: Vector2 = Vector2(3.0, 5.0)
@export_range(0.0, 1.0, 0.01) var shadow_opacity: float = 0.25
@export var shadow_color: Color = Color(0.0706, 0.0392, 0.1176)

@export_group("Fireflies")
@export var firefly_path: NodePath = ^"Fireflies"
@export var firefly_margin: float = 60.0

@export_group("Lightning Strike Event")
@export var lightning_event_interval_min: float = 3.0  ## PLAYTEST TUNING: much shorter than the 8-14s norm so it fires often; see power_station.gd's own copy of this note
@export var lightning_event_interval_max: float = 5.0  ## PLAYTEST TUNING: see lightning_event_interval_min
@export var lightning_warning_lead_time: float = 1.0  ## seconds between the warning telegraph and the actual strike
@export var lightning_stun_min: float = 1.0
@export var lightning_stun_max: float = 2.0
@export var lightning_platform_strike_count_min: int = 3
@export var lightning_platform_strike_count_max: int = 3
@export var lightning_high_traffic_weight: float = 2.0  ## relative pick weight for the center + inner platforms
@export var lightning_low_traffic_weight: float = 1.0  ## relative pick weight for the spawn-adjacent outer platforms
@export var lightning_warning_height_offset: float = 40.0  ## how far above the platform surface the "!" hovers

@export_group("Lightning Strike Hit Detection")
@export var lightning_hit_vertical_reach: float = 70.0  ## how far above the platform surface still counts as "on" it
@export var lightning_hit_vertical_slack: float = 12.0  ## small allowance below the surface (landing jitter)
@export var lightning_hit_horizontal_margin: float = 20.0  ## extra reach past the platform edges (~player capsule radius)
@export var lightning_sky_y: float = 0.0  ## world Y the strike visually falls from -- above every platform
## Lightning's own sound, separate from death_zap_sound, which also fires for the
## fall-death zap via ArenaBase._play_death_zone_zap - while the two shared one
## property, retuning the strike retuned the death boundary with it.
##
## Left unassigned this falls back to death_zap_sound at its volume, so lightning
## is never silent before a clip is picked and the arena sounds exactly as it did.
@export var lightning_sound: AudioStream
@export var lightning_volume_db: float = -6.0
@export var lightning_strike_path_half_width: float = 6.0  ## width of the falling-bolt hazard corridor -- matches the bolt sprite, not the platform

@export_group("Lightning Strike Electrify Effect")
@export var lightning_electrify_duration: float = 0.2
@export var lightning_strike_path_duration: float = 0.1  ## how long the falling-bolt corridor itself stays dangerous, separate from the platform's own hazard window
@export var lightning_electrify_post_count: int = 3
@export var lightning_electrify_density: float = 0.6
@export var lightning_electrify_interval_min: float = 0.12
@export var lightning_electrify_interval_max: float = 0.22
## Shrinks the crackle's horizontal spread relative to the struck platform's
## actual measured width (_lightning_platform_widths, also used for hit
## detection, left untouched by this). 1.0 stretches it across the platform's
## full real width, which reads as oversized for this effect on every
## platform, not just the wider center one - this scales it down uniformly
## instead of only capping the one outlier.
@export_range(0.1, 1.0, 0.05) var lightning_electrify_visual_width_scale: float = 0.45
const ELECTRIFY_SOUND := preload("res://resources/audio/Light Flicker.mp3")

@export_group("Shield Pickup")
@export var shield_pickup_interval_min: float = 4.0  ## PLAYTEST TUNING: real value is 15.0, lowered so pickups spawn often while testing
@export var shield_pickup_interval_max: float = 7.0  ## PLAYTEST TUNING: real value is 25.0, see shield_pickup_interval_min
@export var shield_pickup_duration: float = 10.0  ## passed to the pickup, which passes it to Player.apply_shield
@export var shield_pickup_edge_margin: float = 16.0  ## keeps the spawn point off a platform's very edge
@export var shield_pickup_hover_height: float = 20.0  ## lifts the pickup to visually rest on the platform surface, not sit centered inside it
const SHIELD_PICKUP_SCENE := preload("res://scenes/shield_pickup.tscn")

var _next_lightning_event_ms: int = -1

## Set by _trigger_lightning_strike and resolved by _update_pending_strike, polled
## every frame off the pause-aware clock instead of an `await create_timer(...)`, so
## a strike already in flight when the couch pause menu opens waits out the pause
## instead of landing on real-time while the menu is up.
var _pending_strike_indices: Array = []
var _pending_strike_time_ms: int = -1

var _next_shield_pickup_ms: int = -1
var _active_shield_pickup: ShieldPickup = null

## Populated in _ready from LightningPlatforms' Marker2D children (see scene: each
## marks a real rooftop surface derived from TileMapLayer2's actual tile geometry,
## tagged with metadata/high_traffic so the busier-looking platforms get struck
## more often) -- same convention power_station.gd's own copy of this uses.
var _lightning_platforms: Array[Marker2D] = []
var _lightning_platform_weights: Array[float] = []
var _lightning_platform_widths: Array[float] = []

## Platforms currently electrified, so stepping onto one stays dangerous for its whole
## visible duration, not just the strike instant. Each entry: {idx, expire_ms,
## path_expire_ms, zapped}, where path_expire_ms is the fall-path corridor's own
## (shorter) expiry, independent of the platform's own hazard window, and zapped tracks
## (per this activation) which players have already been hit, so standing there doesn't
## stun every frame.
var _active_electrifications: Array[Dictionary] = []

const SINGLEPLAYER_LIGHTNING_INTERVAL := Vector2(2.0, 3.5)

var _dust: GPUParticles2D
var _dust_shape: ParticleProcessMaterial
var _dust_extents: Vector2 = Vector2.ZERO

var _fireflies: GPUParticles2D
var _fireflies_shape: ParticleProcessMaterial
var _firefly_extents: Vector2 = Vector2.ZERO


func _music_id() -> StringName:
	return &"arena_residential"


## Same singleplayer pressure bump power_station.gd applies to its own lightning
## event, so bots don't get an easy ride here just because this arena's hazards
## were added later.
func _apply_singleplayer_tuning() -> void:
	super()
	if not LocalPlayers.singleplayer:
		return
	lightning_event_interval_min = SINGLEPLAYER_LIGHTNING_INTERVAL.x
	lightning_event_interval_max = SINGLEPLAYER_LIGHTNING_INTERVAL.y


## The "!" warnings currently on screen, in world space -- lets bots step away from
## a platform about to be struck the same way they already do in power_station.gd.
func get_danger_positions() -> PackedVector2Array:
	var spots := PackedVector2Array()
	for idx in _pending_strike_indices:
		var i: int = int(idx)
		if i < 0 or i >= _lightning_platforms.size():
			continue
		spots.append(_lightning_platforms[i].global_position)
	return spots


func _ready() -> void:
	super()
	var dim := CanvasModulate.new()
	dim.name = "AmbientDusk"
	dim.color = ambient_tint
	add_child(dim)
	_lift_tiles()
	_tint_parallax()
	_setup_dust()
	_setup_fireflies()
	_build_layer_shadow()
	_collect_lightning_platforms()
	MinigameDirector.match_started.connect(_on_match_started_for_lightning)
	MinigameDirector.match_started.connect(_on_match_started_for_shield_pickup)


func _build_layer_shadow() -> void:
	if not shadow_enabled or shadow_steps <= 0:
		return
	var layer := get_node_or_null(shadow_layer_path) as TileMapLayer
	if layer == null:
		push_warning("residential_area.gd: no TileMapLayer at '%s' to shade." % shadow_layer_path)
		return
	var parent := layer.get_parent()
	var tint := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_opacity)
	for i in shadow_steps:
		var step: float = float(i + 1) / float(shadow_steps)
		var copy := layer.duplicate() as TileMapLayer
		copy.name = "%sShadow%d" % [layer.name, i]
		copy.position = layer.position + shadow_offset * step
		copy.modulate = tint
		copy.collision_enabled = false
		copy.navigation_enabled = false
		parent.add_child(copy)
		parent.move_child(copy, layer.get_index())


func _setup_dust() -> void:
	_dust = get_node_or_null(dust_path)
	if _dust == null:
		push_warning("residential_area.gd: no node at '%s' — no ambient dust." % dust_path)
		return
	_dust.local_coords = false
	_dust_shape = _dust.process_material as ParticleProcessMaterial


## super() first: ArenaBase._process runs the safe-zone scheduler
## (_update_safe_zone_schedule) that every other arena already gets for free
## through inheritance -- this override was shadowing it entirely, which is why
## safe zone events never fired here. The hazard scheduler calls below mirror
## power_station.gd's own _process exactly, so lightning strikes/shield pickups
## behave identically here too.
func _process(delta: float) -> void:
	super._process(delta)
	_update_lightning_schedule()
	_update_pending_strike()
	_update_electrified_hazards()
	_update_shield_pickup_schedule()
	_update_dust()
	_update_fireflies()


func _update_dust() -> void:
	if _dust == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	_dust.global_position = cam.get_screen_center_position()
	if _dust_shape == null:
		return
	var zoom: Vector2 = cam.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return
	var extents := (get_viewport_rect().size / zoom) * 0.5 + Vector2(dust_margin, dust_margin)
	if not extents.is_equal_approx(_dust_extents):
		_dust_extents = extents
		_dust_shape.emission_box_extents = Vector3(extents.x, extents.y, 1.0)


## Same camera-follow/viewport-sized-box technique _update_dust already uses --
## the emission box only ever covers what's on screen (plus a small margin) rather
## than the whole level, so a handful of particles reads as "fireflies everywhere"
## without ever simulating or drawing any that aren't near the visible area.
func _update_fireflies() -> void:
	if _fireflies == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	_fireflies.global_position = cam.get_screen_center_position()
	if _fireflies_shape == null:
		return
	var zoom: Vector2 = cam.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return
	var extents := (get_viewport_rect().size / zoom) * 0.5 + Vector2(firefly_margin, firefly_margin)
	if not extents.is_equal_approx(_firefly_extents):
		_firefly_extents = extents
		_fireflies_shape.emission_box_extents = Vector3(extents.x, extents.y, 1.0)


func _setup_fireflies() -> void:
	_fireflies = get_node_or_null(firefly_path)
	if _fireflies == null:
		push_warning("residential_area.gd: no node at '%s' — no fireflies." % firefly_path)
		return
	_fireflies.local_coords = false
	_fireflies_shape = _fireflies.process_material as ParticleProcessMaterial


## Populated from LightningPlatforms' Marker2D children -- see the scene comment
## on that node for how their positions were derived from the tileset's actual
## rooftop geometry rather than guessed.
func _collect_lightning_platforms() -> void:
	var group := get_node_or_null("LightningPlatforms")
	if group == null:
		push_warning("residential_area.gd: no LightningPlatforms node — lightning strike event has no targets.")
		return
	for child in group.get_children():
		if not (child is Marker2D):
			continue
		var anchor: Marker2D = child
		var high_traffic: bool = anchor.get_meta("high_traffic", false)
		_lightning_platforms.append(anchor)
		_lightning_platform_weights.append(lightning_high_traffic_weight if high_traffic else lightning_low_traffic_weight)
		_lightning_platform_widths.append(float(anchor.get_meta("platform_width", 128.0)))


func _on_match_started_for_lightning() -> void:
	if _is_zone_authority():
		_schedule_next_lightning_event()


func _schedule_next_lightning_event() -> void:
	var wait: float = randf_range(lightning_event_interval_min, lightning_event_interval_max)
	_next_lightning_event_ms = _get_timestamp() + int(wait * 1000.0)


func _update_lightning_schedule() -> void:
	if MinigameDirector.is_match_finished() or MinigameDirector.is_input_locked():
		return
	if not _is_zone_authority():
		return
	if _next_lightning_event_ms < 0:
		return
	# Never overlap with the safe-zone event (or a lightning strike already in flight) -
	# _weather_event_active is the single shared flag both events gate on.
	if _weather_event_active:
		return
	if _get_timestamp() < _next_lightning_event_ms:
		return
	var indices: Array[int] = _pick_lightning_platform_indices()
	if indices.is_empty():
		return  # no platform anchors in the scene (or fewer than 2) -- safe no-op
	var strike_time_ms: int = _get_timestamp() + int(lightning_warning_lead_time * 1000.0)
	if _is_networked():
		_trigger_lightning_strike.rpc(indices, strike_time_ms)
	else:
		_trigger_lightning_strike(indices, strike_time_ms)


## Weighted sample without replacement: draws a random count (between
## lightning_platform_strike_count_min and _max) of distinct platform indices,
## favoring high-traffic platforms over the spawn-adjacent outer ones per their
## configured weights.
func _pick_lightning_platform_indices() -> Array[int]:
	var count: int = _lightning_platforms.size()
	if count < 2:
		return []
	var remaining: Array[int] = []
	for i in count:
		remaining.append(i)
	var picked: Array[int] = []
	var target_count: int = randi_range(lightning_platform_strike_count_min, lightning_platform_strike_count_max)
	var draws: int = mini(target_count, remaining.size())
	for _n in draws:
		var total_weight: float = 0.0
		for idx in remaining:
			total_weight += _lightning_platform_weights[idx]
		var roll: float = randf() * total_weight
		var chosen_pos: int = remaining.size() - 1
		for j in remaining.size():
			roll -= _lightning_platform_weights[remaining[j]]
			if roll <= 0.0:
				chosen_pos = j
				break
		picked.append(remaining[chosen_pos])
		remaining.remove_at(chosen_pos)
	return picked


## Broadcast so the warning telegraph and the strike land at the same moment on every
## peer -- see power_station.gd's own copy of this for the full reasoning on
## strike_time_ms being an absolute synced timestamp.
@rpc("authority", "call_local", "reliable")
func _trigger_lightning_strike(platform_indices: Array, strike_time_ms: int) -> void:
	if MinigameDirector.is_match_finished():
		return
	_weather_event_active = true

	for idx in platform_indices:
		if idx < 0 or idx >= _lightning_platforms.size():
			continue
		var anchor: Marker2D = _lightning_platforms[idx]
		var warn_pos: Vector2 = anchor.global_position + Vector2(0.0, -lightning_warning_height_offset)
		LightningWarning.spawn(self, warn_pos, lightning_warning_lead_time)

	_pending_strike_indices = platform_indices
	_pending_strike_time_ms = strike_time_ms


func _update_pending_strike() -> void:
	if _pending_strike_time_ms < 0:
		return
	if MinigameDirector.is_match_finished():
		_pending_strike_indices = []
		_pending_strike_time_ms = -1
		_weather_event_active = false
		return
	if _get_timestamp() < _pending_strike_time_ms:
		return
	var indices: Array = _pending_strike_indices
	_pending_strike_indices = []
	_pending_strike_time_ms = -1

	for idx in indices:
		if idx < 0 or idx >= _lightning_platforms.size():
			continue
		var anchor: Marker2D = _lightning_platforms[idx]
		_play_lightning_strike_bolt(anchor.global_position)
		_spawn_electrify_effect(idx)

	_weather_event_active = false
	if _is_zone_authority():
		_schedule_next_lightning_event()


## Reuses ArenaBase._play_death_zone_zap's shared DeathRail/bolt/sound plumbing,
## just falling from lightning_sky_y (above the platforms) instead of the rail's
## own death-boundary position -- same approach power_station.gd's own copy uses.
func _play_lightning_strike_bolt(at: Vector2) -> void:
	_play_lightning_sound()
	var rail := get_tree().get_first_node_in_group("lightning_emitters")
	if rail and rail.has_method("strike_global"):
		rail.strike_global(Vector2(at.x, lightning_sky_y), at)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(14.0)


func _player_landed_on_platform(idx: int, player: Node2D) -> bool:
	var anchor: Marker2D = _lightning_platforms[idx]
	var half_width: float = _lightning_platform_widths[idx] * 0.5 + lightning_hit_horizontal_margin
	if absf(player.global_position.x - anchor.global_position.x) > half_width:
		return false
	var min_y: float = anchor.global_position.y - lightning_hit_vertical_reach
	var max_y: float = anchor.global_position.y + lightning_hit_vertical_slack
	return player.global_position.y >= min_y and player.global_position.y <= max_y


func _strike_path_rect(idx: int) -> Rect2:
	var anchor: Marker2D = _lightning_platforms[idx]
	var half_width: float = lightning_strike_path_half_width
	var bottom: float = anchor.global_position.y
	return Rect2(anchor.global_position.x - half_width, lightning_sky_y, half_width * 2.0, bottom - lightning_sky_y)


func _update_electrified_hazards() -> void:
	if _active_electrifications.is_empty():
		return
	if MinigameDirector.is_match_finished():
		return
	var now := _get_timestamp()
	for i in range(_active_electrifications.size() - 1, -1, -1):
		var entry: Dictionary = _active_electrifications[i]
		if now >= int(entry["expire_ms"]):
			var emitter: Node = entry.get("emitter")
			if is_instance_valid(emitter):
				emitter.queue_free()
			_active_electrifications.remove_at(i)
			continue
		var idx: int = int(entry["idx"])
		var path_active: bool = now < int(entry["path_expire_ms"])
		var zapped: Dictionary = entry["zapped"]
		for player in players:
			if not is_instance_valid(player) or player.is_dead:
				continue
			if zapped.has(player):
				continue
			var in_path: bool = path_active and _strike_path_rect(idx).has_point(player.global_position)
			if not (_player_landed_on_platform(idx, player) or in_path):
				continue
			zapped[player] = true
			_play_lightning_sound()
			if _is_networked() and not player.is_multiplayer_authority():
				continue
			var duration: float = randf_range(lightning_stun_min, lightning_stun_max)
			player.apply_electrocution(duration)


func _spawn_electrify_effect(idx: int) -> void:
	var anchor: Marker2D = _lightning_platforms[idx]
	var width: float = _lightning_platform_widths[idx]
	var visual_width: float = width * lightning_electrify_visual_width_scale
	var emitter := LightningEmitter.new()
	emitter.rail_mode = true
	emitter.rail_x_min = -visual_width * 0.5
	emitter.rail_x_max = visual_width * 0.5
	emitter.rail_post_count = lightning_electrify_post_count
	emitter.rail_density = lightning_electrify_density
	emitter.interval_min = lightning_electrify_interval_min
	emitter.interval_max = lightning_electrify_interval_max
	emitter.bolt_sound = ELECTRIFY_SOUND
	emitter.sound_volume_db = -22.0
	emitter.sound_chance = 0.25
	add_child(emitter)
	emitter.global_position = anchor.global_position
	emitter.remove_from_group("lightning_emitters")

	var entry: Dictionary = {
		"idx": idx,
		"expire_ms": _get_timestamp() + int(lightning_electrify_duration * 1000.0),
		"path_expire_ms": _get_timestamp() + int(lightning_strike_path_duration * 1000.0),
		"zapped": {},
		"emitter": emitter,
	}
	_active_electrifications.append(entry)


func _on_match_started_for_shield_pickup() -> void:
	if _is_zone_authority():
		_schedule_next_shield_pickup()


func _schedule_next_shield_pickup() -> void:
	var wait: float = randf_range(shield_pickup_interval_min, shield_pickup_interval_max)
	_next_shield_pickup_ms = _get_timestamp() + int(wait * 1000.0)


func _update_shield_pickup_schedule() -> void:
	if MinigameDirector.is_match_finished() or MinigameDirector.is_input_locked():
		return
	if not _is_zone_authority():
		return
	if _next_shield_pickup_ms < 0:
		return
	if is_instance_valid(_active_shield_pickup):
		return
	if _get_timestamp() < _next_shield_pickup_ms:
		return
	if _lightning_platforms.is_empty():
		return
	var spawn_pos: Vector2 = _random_shield_pickup_position()
	if _is_networked():
		_spawn_shield_pickup.rpc(spawn_pos)
	else:
		_spawn_shield_pickup(spawn_pos)


func _random_shield_pickup_position() -> Vector2:
	var idx: int = randi() % _lightning_platforms.size()
	var anchor: Marker2D = _lightning_platforms[idx]
	var half_width: float = maxf(_lightning_platform_widths[idx] * 0.5 - shield_pickup_edge_margin, 0.0)
	var offset_x: float = randf_range(-half_width, half_width)
	return anchor.global_position + Vector2(offset_x, -shield_pickup_hover_height)


@rpc("authority", "call_local", "reliable")
func _spawn_shield_pickup(spawn_pos: Vector2) -> void:
	if MinigameDirector.is_match_finished():
		return
	if is_instance_valid(_active_shield_pickup):
		return
	var pickup: ShieldPickup = SHIELD_PICKUP_SCENE.instantiate()
	pickup.name = "ShieldPickup"
	pickup.shield_duration = shield_pickup_duration
	add_child(pickup)
	pickup.global_position = spawn_pos
	pickup.tree_exited.connect(_on_shield_pickup_gone)
	_active_shield_pickup = pickup


func _on_shield_pickup_gone() -> void:
	_active_shield_pickup = null
	if _is_zone_authority():
		_schedule_next_shield_pickup()


func _lift_tiles() -> void:
	var tiles := get_node_or_null("tiles")
	if tiles == null:
		push_warning("residential_area.gd: no 'tiles' node — platforms stay dim.")
		return
	var lifted := Color(
		tile_tint.r * tile_lift,
		tile_tint.g * tile_lift,
		tile_tint.b * tile_lift,
	)
	for layer in tiles.get_children():
		if layer is CanvasItem:
			layer.modulate = lifted


func _tint_parallax() -> void:
	var root := get_node_or_null(parallax_root)
	if root == null:
		push_warning("residential_area.gd: no node at '%s' to tint." % parallax_root)
		return
	var index := 0
	for layer in root.get_children():
		if not layer is ParallaxLayer2D:
			continue
		if index < parallax_tints.size():
			layer.modulate = parallax_tints[index]
		index += 1


## Every lightning-caused sound goes through here - the falling bolt and the zap
## on a player it catches - so one property retunes all of it.
func _play_lightning_sound() -> void:
	var clip: AudioStream = lightning_sound if lightning_sound != null else death_zap_sound
	if clip == null:
		return
	var db: float = lightning_volume_db if lightning_sound != null else death_zap_volume_db
	SfxManager.play(clip, db, 0.12)
