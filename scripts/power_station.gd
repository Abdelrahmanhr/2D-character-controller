extends ArenaBase

@export var ambient_tint: Color = Color(0.6353, 0.5765, 0.7686)

@export var platform_lift: float = 1.25
@export var platform_tint: Color = Color(1, 1, 1)

@export var glow_layer_path: NodePath = ^"tiles/TileMapLayer4"
@export var glow_layer_lift: float = 1.7
@export var glow_layer_tint: Color = Color(0.549, 0.8549, 1)
@export var glow_layer_additive: bool = false

@export_group("Lightning Strike Event")
@export var lightning_event_interval_min: float = 3.0  ## PLAYTEST TUNING: much shorter than the 8-14s norm so it fires often; see summary
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
@export var lightning_sky_y: float = 0.0  ## world Y the strike visually falls from -- above every platform (which sit between 288 and 544)
@export var lightning_strike_path_half_width: float = 6.0  ## width of the falling-bolt hazard corridor -- matches the bolt sprite, not the platform

@export_group("Lightning Strike Electrify Effect")
@export var lightning_electrify_duration: float = 0.2
@export var lightning_strike_path_duration: float = 0.1  ## how long the falling-bolt corridor itself stays dangerous, separate from the platform's own hazard window
@export var lightning_electrify_post_count: int = 3  ## restored to 3 now that strike count is fixed at 3 (was temporarily 2 while up to 5 platforms could electrify at once)
@export var lightning_electrify_density: float = 0.6
@export var lightning_electrify_interval_min: float = 0.12
@export var lightning_electrify_interval_max: float = 0.22
const ELECTRIFY_SOUND := preload("res://resources/audio/Light Flicker.mp3")

var _next_lightning_event_ms: int = -1

## Populated in _ready from LightningPlatforms' Marker2D children (see scene: each
## marks a real platform center on the TileMapLayer4 collision layer, tagged with
## metadata/high_traffic so higher-traffic platforms get struck more often).
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


func _ready() -> void:
	super()
	var dim := CanvasModulate.new()
	dim.name = "AmbientDim"
	dim.color = ambient_tint
	add_child(dim)
	_lift_platforms()
	_light_glow_layer()
	_collect_lightning_platforms()
	MinigameDirector.match_started.connect(_on_match_started_for_lightning)


func _collect_lightning_platforms() -> void:
	var group := get_node_or_null("LightningPlatforms")
	if group == null:
		push_warning("power_station.gd: no LightningPlatforms node — lightning strike event has no targets.")
		return
	for child in group.get_children():
		if not (child is Marker2D):
			continue
		var anchor: Marker2D = child
		var high_traffic: bool = anchor.get_meta("high_traffic", false)
		_lightning_platforms.append(anchor)
		_lightning_platform_weights.append(lightning_high_traffic_weight if high_traffic else lightning_low_traffic_weight)
		_lightning_platform_widths.append(float(anchor.get_meta("platform_width", 128.0)))


func _process(delta: float) -> void:
	super._process(delta)
	_update_lightning_schedule()
	_update_electrified_hazards()


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
## favoring high-traffic platforms (center + inner) over the four spawn-adjacent
## outer ones per their configured weights.
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
## peer. strike_time_ms is an absolute synced timestamp chosen by the authority up
## front (rather than each peer awaiting a flat 1s from whenever this RPC happens to
## arrive), so normal RPC latency/jitter doesn't compound into the warning-to-strike
## gap looking different peer to peer.
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

	var remaining_sec: float = maxf(float(strike_time_ms - _get_timestamp()) / 1000.0, 0.0)
	await get_tree().create_timer(remaining_sec).timeout
	if not is_inside_tree() or MinigameDirector.is_match_finished():
		_weather_event_active = false
		return

	for idx in platform_indices:
		if idx < 0 or idx >= _lightning_platforms.size():
			continue
		var anchor: Marker2D = _lightning_platforms[idx]
		_play_lightning_strike_bolt(anchor.global_position)
		_spawn_electrify_effect(idx)

	_weather_event_active = false
	if _is_zone_authority():
		_schedule_next_lightning_event()


## Reuses the same bolt/sound/shake ArenaBase._play_death_zone_zap already provides for
## the fall-death zap, but that function hardcodes the shared DeathRail's own position
## (world y=740, below every platform) as the strike's origin -- fine for a zap next to
## the death boundary, but backwards for a lightning strike, which should fall from
## above. This is power_station.gd-only so the shared death-zap behavior other arenas
## rely on stays untouched; only the origin point differs (lightning_sky_y instead of
## the rail's own y), still spawning through the same rail emitter/pool.
func _play_lightning_strike_bolt(at: Vector2) -> void:
	if death_zap_sound:
		SfxManager.play(death_zap_sound, death_zap_volume_db, 0.12)
	var rail := get_tree().get_first_node_in_group("lightning_emitters")
	if rail and rail.has_method("strike_global"):
		rail.strike_global(Vector2(at.x, lightning_sky_y), at)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(14.0)


## Only counts as "on" an electrified platform once the player is within its real
## footprint horizontally (plus lightning_hit_horizontal_margin so standing right at
## the lip still counts) and within the vertical band a standing player actually
## occupies: up to lightning_hit_vertical_reach ABOVE the anchor (anchors sit below the
## real surface a player stands on) and lightning_hit_vertical_slack below it (landing
## jitter). Deliberately doesn't gate on is_on_floor() -- CharacterBody2D's floor flag
## can miss right at a platform's edge when only a sliver of the collision shape
## overlaps, which was letting players stand at the lip without getting zapped. Now
## that lightning_electrify_duration is short (a fraction of a second, not 3s), the
## risk of catching someone mid-jump passing through this band is much smaller than it
## was when the hazard lingered for the platform's whole visible duration.
func _player_landed_on_platform(idx: int, player: Node2D) -> bool:
	var anchor: Marker2D = _lightning_platforms[idx]
	var half_width: float = _lightning_platform_widths[idx] * 0.5 + lightning_hit_horizontal_margin
	if absf(player.global_position.x - anchor.global_position.x) > half_width:
		return false
	var min_y: float = anchor.global_position.y - lightning_hit_vertical_reach
	var max_y: float = anchor.global_position.y + lightning_hit_vertical_slack
	return player.global_position.y >= min_y and player.global_position.y <= max_y


## The strike's fall path: a thin corridor centered on the target platform's x
## position, matching the bolt sprite's own width (lightning_strike_path_half_width)
## rather than the platform's footprint -- a platform stacked directly above the target
## still sits inside it since it shares the same x, but the corridor itself no longer
## fans out to the platform's edges.
func _strike_path_rect(idx: int) -> Rect2:
	var anchor: Marker2D = _lightning_platforms[idx]
	var half_width: float = lightning_strike_path_half_width
	var bottom: float = anchor.global_position.y
	return Rect2(anchor.global_position.x - half_width, lightning_sky_y, half_width * 2.0, bottom - lightning_sky_y)


## Runs every frame for as long as any platform is electrified (registered by
## _spawn_electrify_effect, pruned here once its duration expires). Checks two
## separate things per platform: whether the player has actually landed on it
## (_player_landed_on_platform, grounded + within its footprint) and whether they're
## passing through its fall path in the air (_strike_path_rect, a pure overlap check --
## this is what should catch someone falling through the bolt on a platform stacked
## above the target). Each entry's `zapped` dict is this activation's "already hit" set
## (shared across both checks), so a player who stays on (or returns to) an electrified
## platform, or lingers in its fall path, is only stunned once per activation, not
## every frame.
## Authority pattern matches _on_death_zone_body_entered: every peer evaluates the same
## shared `players` list locally (and everyone plays the shock sound, same as the
## initial strike's zap is heard by all peers), but only the peer that owns a given
## player calls apply_stun on it, so a hit is never applied twice over the network.
func _update_electrified_hazards() -> void:
	if _active_electrifications.is_empty():
		return
	if MinigameDirector.is_match_finished():
		return
	var now := _get_timestamp()
	for i in range(_active_electrifications.size() - 1, -1, -1):
		var entry: Dictionary = _active_electrifications[i]
		if now >= int(entry["expire_ms"]):
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
			if death_zap_sound:
				SfxManager.play(death_zap_sound, death_zap_volume_db, 0.12)
			if _is_networked() and not player.is_multiplayer_authority():
				continue
			var duration: float = randf_range(lightning_stun_min, lightning_stun_max)
			player.apply_stun(Vector2.ZERO, 0.0, duration)


## Makes the struck platform visibly crackle for a moment by reusing LightningEmitter's
## existing rail_mode (the same mechanism DeathRail already uses for its "electrified
## boundary" look) rather than building a new effect, spanning exactly the platform's
## real width. Explicitly leaves the "lightning_emitters" group it joins on _ready so it
## can never be picked up by _play_death_zone_zap's group lookup in place of the real
## DeathRail (verified: group membership is insertion-order, and DeathRail is always
## registered first at scene load, so this is defense-in-depth rather than a fix for an
## observed bug).
func _spawn_electrify_effect(idx: int) -> void:
	var anchor: Marker2D = _lightning_platforms[idx]
	var width: float = _lightning_platform_widths[idx]
	var emitter := LightningEmitter.new()
	emitter.rail_mode = true
	emitter.rail_x_min = -width * 0.5
	emitter.rail_x_max = width * 0.5
	emitter.rail_post_count = lightning_electrify_post_count
	emitter.rail_density = lightning_electrify_density
	emitter.interval_min = lightning_electrify_interval_min
	emitter.interval_max = lightning_electrify_interval_max
	emitter.bolt_sound = ELECTRIFY_SOUND
	emitter.sound_volume_db = -22.0
	emitter.sound_chance = 0.25
	# global_position must be set AFTER add_child: this node has no parent yet, so
	# assigning it beforehand ignores PowerStation's own root offset (40, 0) and the
	# emitter ends up parented 40px off from the platform it's meant to straddle -- half
	# on the platform, half floating past its edge. LightningWarning.spawn() already
	# gets this order right; this one didn't.
	add_child(emitter)
	emitter.global_position = anchor.global_position
	emitter.remove_from_group("lightning_emitters")

	var entry: Dictionary = {
		"idx": idx,
		"expire_ms": _get_timestamp() + int(lightning_electrify_duration * 1000.0),
		"path_expire_ms": _get_timestamp() + int(lightning_strike_path_duration * 1000.0),
		"zapped": {},
	}
	_active_electrifications.append(entry)

	# Both the visual and the hazard's collision window used to be timed
	# independently -- the emitter freed itself off get_tree().create_timer (local
	# engine time), while the hazard's expire_ms was computed off _get_timestamp()
	# (the synced match clock). Those two clocks can drift, which is why the
	# collision was outliving the visual. Now a single timer drives both: when it
	# fires, the emitter frees itself AND the hazard entry is force-expired in the
	# same frame, so they can never fall out of sync.
	var expire_timer := get_tree().create_timer(lightning_electrify_duration)
	expire_timer.timeout.connect(emitter.queue_free)
	expire_timer.timeout.connect(func() -> void: entry["expire_ms"] = 0)


func _light_glow_layer() -> void:
	var layer := get_node_or_null(glow_layer_path)
	if layer == null:
		push_warning("power_station.gd: no node at '%s' to glow." % glow_layer_path)
		return
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	if glow_layer_additive:
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = mat
	layer.modulate = Color(
		glow_layer_tint.r * glow_layer_lift,
		glow_layer_tint.g * glow_layer_lift,
		glow_layer_tint.b * glow_layer_lift,
	)


func _lift_platforms() -> void:
	var platforms := get_node_or_null("tiles/TileMapLayer2")
	if platforms == null:
		push_warning("power_station.gd: no tiles/TileMapLayer2 to light — platforms stay dim.")
		return
	platforms.modulate = Color(
		platform_tint.r * platform_lift,
		platform_tint.g * platform_lift,
		platform_tint.b * platform_lift,
	)
