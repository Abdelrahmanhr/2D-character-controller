extends CharacterBody2D
@export var speed: float = 300.0
@export var acceleration: float = 2600.0
@export var friction: float = 3200.0
@export var air_acceleration: float = 1800.0
@export var air_friction: float = 900.0
@export var turn_acceleration: float = 4500.0
@export var apex_threshold: float = 60.0
@export var apex_gravity_mult: float = 0.55
@export var fast_fall_gravity_mult: float = 2.4
@export var fast_fall_max_speed: float = 1100.0
@export var land_impact_reference: float = 900.0
@export var dust_color: Color = Color(0.7569, 0.851, 0.949, 0.9)
@export var dust_offset_y: float = 22.0
@export var jump_height: float = 64.0
@export var time_to_peak: float = 0.35
@export var time_to_descent: float = 0.28
@export var jump_cut_off: float = 0.5
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.1
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.6
@export var dash_end_momentum_retention: float = 0.35 
@export var stun_duration: float = 0.8
@export var knockback_speed: float = 500.0
@export var knockback_friction: float = 1200.0
@export var hitstop_duration: float = 0.08
@export var dash_sound: AudioStream
@export var land_sound: AudioStream
@export var jump_sound: AudioStream  
@export var slam_sound: AudioStream  
@export var footstep_sound: AudioStream
@export var footstep_frames: Array[int] = [0,2]
@export var footstep_pitch_variance: float = 0.15
@export var footstep_debounce: float = 0.1
@export var dash_conflict_knockback_multiplier: float = 1.2  ## CHANGED: was 2.0 - attacker still bounces off a shielded victim, just less forcefully
@export var dash_conflict_flash_color: Color = Color(0.8667, 0.2157, 0.2706, 1.0)
@export var dash_conflict_flash_duration: float = 0.25
## NEW: the counter-slam timing window. See _on_dash_hitbox_body_entered's
## is_counter_clash check.
@export var counter_window_ms: int = 200
const COUNTER_TIEBREAK_MS := 60  ## NEW: intentionally not exported, see the comment where it's used
@export var shield_duration: float = 10.0
@export var shield_flash_color: Color = Color(0.3216, 0.6392, 1.0, 1.0)
@export var shield_block_sound: AudioStream = preload("res://resources/audio/SheildBlock.wav")
@export var shield_block_volume_db: float = -8.0
@export var explode_sound: AudioStream  
@export var explode_pitch_variance: float = 0.1  

@export var stun_tilt_angle_degrees: float = 25.0  
@export var stun_tilt_speed: float = 10.0  

@export var device_id: int = -2
## Set by ArenaBase._spawn_local_players for bot players. Non-null means input
## comes from there instead of from a device; every other system (dash, jump cut,
## fast fall, safe zone slowdown, stun, death) is unaware and unchanged.
var bot: BotController = null

## CHANGED: was seven @export Key fields. Bindings now live in Settings so the
## options page can edit them; these are a cache, because _handle_input runs
## every physics frame for every player and this used to be a plain field read.
var keyboard_left: Key = KEY_A
var keyboard_right: Key = KEY_D
var keyboard_up: Key = KEY_W
var keyboard_down: Key = KEY_S
var keyboard_jump: Key = KEY_SPACE
var keyboard_dash: Key = KEY_SHIFT
var keyboard_dash_alt: Key = KEY_F

## Layered under Jump.wav rather than replacing it - effort beneath the jump,
## not a second event. Only on the real jump; _celebrate_hop stays ungrunted.
@export var jump_grunt_sound: AudioStream = preload("res://resources/audio/jump-grunt.wav")
@export var jump_grunt_volume_db: float = -16.0

@export var invulnerability_flash_speed: float = 0.1
@export var player_light_energy: float = 1.0
@export var player_light_scale: float = 2.2

@export_group("Long Fall")
@export var fall_fx_distance: float = 300.0
@export var fall_streak_color: Color = Color(0.7804, 0.8706, 1, 0.55)
@export var fall_ghost_color: Color = Color(0.549, 0.6784, 0.9490, 0.55)
@export var fall_whoosh_sound: AudioStream
@export var fall_whoosh_volume_db: float = -8.0

@export var zone_drag: float = 1.5  # NEW: higher = more resistance, feels thicker
@export var zone_gravity_multiplier: float = 0.4  # NEW: still want reduced fall speed, just not the whole effect
@export var zone_jump_multiplier: float = 0.9  # NEW: jumps feel softer/shorter, like jumping in water
@export var zone_move_speed_multiplier: float = 0.6  # NEW: walking/air control feels sluggish


var _danger_ring: DangerRing  

var _zone_outside_timer: float = 0.0  
var dash_start_time_ms: int = 0  
var is_invulnerable: bool = false 
var _invuln_time_left: float = 0.0 
var _invuln_flash_timer: float = 0.0 
var _death_animation_id: int = 0  

const STICK_DEADZONE: float = 0.2
const TELEPORT_DISTANCE: float = 600.0
const FALL_MIN_SPEED: float = 250.0

var _prev_jump_held: bool = false  
var _prev_dash_held: bool = false  
var _last_move_input: Vector2 = Vector2.ZERO  

var _was_on_floor: bool = true

var _was_walking: bool = false
var _last_footstep_time: float = -999.0

var is_frozen: bool = false
var freeze_time_left: float = 0.0

var is_stunned: bool = false
var stun_time_left: float = 0.0

## Electrocution shake. Layered on top of apply_stun (the hazard's existing
## damage/stun call) rather than reusing is_stunned itself, since is_stunned is
## shared by every stun source (dash conflicts, shield bounces, ...) and only
## the electrify hazard should read as an electrical shock. Position-based, and
## nothing else in this script ever touches animated_sprite.position, so this
## can't collide with the scale/rotation/modulate/material effects already here.
const ELECTROCUTION_SHAKE_AMPLITUDE := 3.0
const ELECTROCUTION_SHAKE_INTERVAL := 0.03
const ELECTROCUTION_SETTLE_DURATION := 0.08
var _electrocution_tween: Tween
var _electrocution_base_position: Vector2 = Vector2.ZERO
var _electrocution_shake_id: int = 0

## Kill-feed attribution: who last landed a stun on this player, and when, so a
## death shortly afterward can be credited to them instead of read as an anonymous
## fall/explosion. Cleared on respawn so a hit from a prior life never carries over.
const ATTACKER_CREDIT_WINDOW_MS := 3000
var _last_attacker_key: int = -1  ## attacker's player.name.to_int() - the same peer_id/slot+1 identifier MinigameDirector keys everything else by
var _last_attacker_name: String = ""
var _last_attacker_color: Color = Color.WHITE
var _last_attacker_time_ms: int = -1000000

## Independent of is_invulnerable: blocks stun/knockback (see _do_apply_stun) rather
## than damage/death, and has its own blue tint instead of the white respawn flash.
var is_shielded: bool = false
var shield_time_left: float = 0.0

var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

var coyote_time_counter: float = 0.0
var jump_buffer_counter: float = 0.0

var cut_jump: bool = false
var jump_pressed: bool = false

var direction: float = 0.0
var rise_gravity: float
var fall_gravity: float
var jump_velocity: float

var facing_right := true
var animation_name: StringName = &"idle_right"

# Preallocated so the per-tick animation pick costs no String concat + StringName
# interning. Indexed as ANIM_<state>[facing_right].
const ANIM_IDLE: Array[StringName] = [&"idle_left", &"idle_right"]
const ANIM_WALK: Array[StringName] = [&"walk_left", &"walk_right"]
const ANIM_JUMP: Array[StringName] = [&"jump_left", &"jump_right"]
const ANIM_DIE: Array[StringName] = [&"die_left", &"die_right"]

var is_dead := false
var is_celebrating := false

@export_group("Celebration")
@export var celebrate_hop_velocity_scale: float = 0.62
@export var celebrate_hop_interval: float = 0.46
@export var celebrate_hops: int = 5

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var player_tag: Label = $PlayerTag
@onready var glow: Sprite2D = $Glow
@onready var bomb_controller: BombController = $BombController
@onready var dash_hitbox: Area2D = $DashHitbox
@onready var dash_afterimage = $DashAfterimage

var _identity_slot: int = -1
var _identity_name: String = ""
var _sprite_base_scale: Vector2 = Vector2.ONE
var _dash_hitbox_base_scale_x: float = 1.0
var _fall_speed: float = 0.0
var _land_dust: CPUParticles2D
var _jump_dust: CPUParticles2D
var _run_dust: CPUParticles2D
var _fall_streaks: CPUParticles2D
var _fall_whoosh: AudioStreamPlayer2D
var _fall_fx_active: bool = false
var _fall_fx_last_y: float = 0.0
var _fall_distance: float = 0.0
var _dash_ghost_color: Color = Color.WHITE
var _player_light: PointLight2D

# Remote players are position-driven only: the synchronizer hands us discrete
# snapshots, so we glide between the last two instead of snapping to each one.
const NET_SNAP_DISTANCE: float = 200.0  # respawns and teleports must not slide across the arena
const NET_INTERP_MIN: float = 0.02
const NET_INTERP_MAX: float = 0.25

var _net_position: Vector2 = Vector2.ZERO
var net_position: Vector2:
	get:
		return _net_position
	set(value):
		_net_position = value
		_receive_net_position(value)

var _net_prev_pos: Vector2 = Vector2.ZERO
var _net_target_pos: Vector2 = Vector2.ZERO
var _net_lerp_t: float = 0.0
var _net_interp_span: float = 0.033
var _net_last_recv_ms: int = 0
var _net_primed: bool = false


func _ready() -> void:
	dash_hitbox.body_entered.connect(_on_dash_hitbox_body_entered)
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	dash_hitbox.monitoring = false
	_dash_hitbox_base_scale_x = absf(dash_hitbox.scale.x) if dash_hitbox.scale.x != 0.0 else 1.0
	add_to_group("players")
	_dash_hitbox_base_scale_x = absf(dash_hitbox.scale.x) if dash_hitbox.scale.x != 0.0 else 1.0
	_recalculate_jump_physics()
	_setup_glow_texture()
	_update_identity()
	_setup_life_hearts()
	_setup_danger_ring()  # NEW
	_sprite_base_scale = animated_sprite.scale
	_setup_dust()
	_setup_fall_fx()
	_net_position = global_position  # so the first sync carries the spawn point, not (0, 0)
	_refresh_keys()
	Settings.keys_changed.connect(_refresh_keys)
	if _is_networked() and is_multiplayer_authority() and device_id == -2:
		device_id = -1
		if bomb_controller:
			bomb_controller.device_id = device_id

## Pulled once on spawn and again whenever the options page rebinds something,
## rather than asking Settings inside the input loop.
func _refresh_keys() -> void:
	keyboard_left = Settings.get_key(&"move_left")
	keyboard_right = Settings.get_key(&"move_right")
	keyboard_up = Settings.get_key(&"move_up")
	keyboard_down = Settings.get_key(&"move_down")
	keyboard_jump = Settings.get_key(&"jump")
	keyboard_dash = Settings.get_key(&"dash")
	keyboard_dash_alt = Settings.get_key(&"dash_alt")


func _setup_danger_ring() -> void:
	_danger_ring = DangerRing.new()
	_danger_ring.name = "DangerRing"
	_danger_ring.position = Vector2(-42.0, -10.0)  
	add_child(_danger_ring)

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _publish_net_position() -> void:
	_net_position = global_position


func _receive_net_position(value: Vector2) -> void:
	if not _is_networked() or is_multiplayer_authority():
		return
	# Snapshots arrive on the sender's cadence, which drifts. Time the gap so the
	# glide always lands on the new target just as the next one shows up.
	var now := Time.get_ticks_msec()
	if _net_primed:
		_net_interp_span = clampf(float(now - _net_last_recv_ms) / 1000.0, NET_INTERP_MIN, NET_INTERP_MAX)
	_net_last_recv_ms = now
	if not _net_primed or _net_target_pos.distance_to(value) > NET_SNAP_DISTANCE:
		_net_prev_pos = value
		_net_target_pos = value
		_net_lerp_t = 1.0
		_net_primed = true
		global_position = value
		return
	_net_prev_pos = _net_target_pos
	_net_target_pos = value
	_net_lerp_t = 0.0


func _advance_net_interpolation(delta: float) -> void:
	if not _net_primed:
		return
	if _net_lerp_t >= 1.0:
		global_position = _net_target_pos
		return
	_net_lerp_t = minf(_net_lerp_t + delta / _net_interp_span, 1.0)
	global_position = _net_prev_pos.lerp(_net_target_pos, _net_lerp_t)


func _recalculate_jump_physics() -> void:
	rise_gravity = (2.0 * jump_height) / (time_to_peak * time_to_peak)
	fall_gravity = (2.0 * jump_height) / (time_to_descent * time_to_descent)
	jump_velocity = -rise_gravity * time_to_peak


func _physics_process(delta: float) -> void:
	if is_dead:
		if _is_networked() and not is_multiplayer_authority():
			_advance_net_interpolation(delta)
			return
		var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
		velocity.y += gravity * delta
		move_and_slide()
		_publish_net_position()
		return
	
	if is_invulnerable:
		_invuln_time_left -= delta
		_invuln_flash_timer -= delta
		if _invuln_flash_timer <= 0.0:
			_invuln_flash_timer = invulnerability_flash_speed
			animated_sprite.visible = not animated_sprite.visible
		if _invuln_time_left <= 0.0:
			is_invulnerable = false
			animated_sprite.visible = true
	
	if is_stunned:
		stun_time_left -= delta
		if stun_time_left <= 0.0:
			is_stunned = false

	if is_shielded:
		shield_time_left -= delta
		if shield_time_left <= 0.0:
			is_shielded = false
			_set_shield_outline_active(false)

	if is_frozen:
		freeze_time_left -= delta
		if freeze_time_left <= 0.0:
			is_frozen = false
			animated_sprite.speed_scale = 1.0
	
	if _is_networked() and not is_multiplayer_authority():
		_advance_net_interpolation(delta)
		return
	
	if is_frozen:  
		return
	
	
	if is_stunned:
		if is_dashing:
			_end_dash_immediately()
		_apply_stun_physics(delta)
		move_and_slide()
		_publish_net_position()
		_update_animation()
		return
	
	_handle_input(delta)
	_apply_movement(delta)
	_fall_speed = velocity.y
	move_and_slide()
	_publish_net_position()
	_check_landing()
	_update_animation()

func _apply_stun_physics(delta: float) -> void:
	var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
	var zone := _get_safe_zone()
	var outside_zone: bool = zone != null and zone.is_outside(global_position)
	if outside_zone:
		gravity *= zone_gravity_multiplier  
	velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
	if outside_zone:  # NEW
		velocity = velocity.move_toward(Vector2.ZERO, zone_drag * delta * velocity.length())
	_update_zone_timer(delta, outside_zone, zone)
	
	var target_tilt: float = 0.0
	if is_stunned and abs(velocity.x) > 10.0:
		target_tilt = deg_to_rad(stun_tilt_angle_degrees) * sign(velocity.x)
	animated_sprite.rotation = lerp_angle(animated_sprite.rotation, target_tilt, stun_tilt_speed * delta)


func _process(delta: float) -> void:
	_update_identity()
	_update_fall_fx(delta)
	if is_dead:
		return
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)

func _setup_glow_texture() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.18),
		Color(1, 1, 1, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	glow.texture = texture
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = glow_mat
	_player_light = PointLight2D.new()
	_player_light.texture = texture
	_player_light.texture_scale = player_light_scale
	_player_light.energy = player_light_energy
	add_child(_player_light)

func _squash(x_mult: float, y_mult: float, duration: float) -> void:
	animated_sprite.scale = _sprite_base_scale * Vector2(x_mult, y_mult)
	var tw := create_tween()
	tw.tween_property(animated_sprite, "scale", _sprite_base_scale, duration) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dust_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_dust(amount: int, lifetime: float, spread: float, vmin: float, vmax: float) -> CPUParticles2D:
	var dust := CPUParticles2D.new()
	dust.texture = _dust_texture()
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = amount
	dust.lifetime = lifetime
	dust.spread = spread
	dust.initial_velocity_min = vmin
	dust.initial_velocity_max = vmax
	dust.gravity = Vector2(0.0, 320.0)
	dust.scale_amount_min = 3.0
	dust.scale_amount_max = 7.0
	dust.damping_min = 40.0
	dust.damping_max = 90.0
	dust.color = dust_color
	dust.position = Vector2(0.0, dust_offset_y)
	dust.z_index = 1
	add_child(dust)
	return dust


func _streak_texture() -> Texture2D:
	var img := Image.create(1, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _setup_fall_fx() -> void:
	_fall_whoosh = get_node_or_null("FallWhoosh")
	if dash_afterimage:
		_dash_ghost_color = dash_afterimage.ghost_color
	_fall_fx_last_y = global_position.y

	var streaks := CPUParticles2D.new()
	streaks.name = "FallStreaks"
	streaks.texture = _streak_texture()
	streaks.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	streaks.emitting = false
	streaks.amount = 22
	streaks.lifetime = 0.35
	streaks.local_coords = false
	streaks.direction = Vector2(0.0, -1.0)
	streaks.spread = 6.0
	streaks.initial_velocity_min = 120.0
	streaks.initial_velocity_max = 320.0
	streaks.gravity = Vector2.ZERO
	streaks.scale_amount_min = 1.0
	streaks.scale_amount_max = 3.0
	streaks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	streaks.emission_rect_extents = Vector2(14.0, 12.0)
	streaks.color = fall_streak_color
	streaks.z_index = 1
	add_child(streaks)
	_fall_streaks = streaks


func _update_fall_fx(delta: float) -> void:
	if delta <= 0.0:
		return
	var y: float = global_position.y
	var moved: float = y - _fall_fx_last_y
	_fall_fx_last_y = y
	if absf(moved) > TELEPORT_DISTANCE:
		_fall_distance = 0.0
		return
	if is_dead or moved / delta < FALL_MIN_SPEED:
		_fall_distance = 0.0
	else:
		_fall_distance += moved
	var falling: bool = _fall_distance >= fall_fx_distance
	if falling != _fall_fx_active:
		_set_fall_fx(falling)


func _set_fall_fx(on: bool) -> void:
	_fall_fx_active = on
	if _fall_streaks:
		_fall_streaks.emitting = on
	if dash_afterimage:
		if on:
			dash_afterimage.ghost_color = fall_ghost_color
			dash_afterimage.start()
		elif not is_dashing:
			dash_afterimage.stop()
			dash_afterimage.ghost_color = _dash_ghost_color
	if _fall_whoosh == null:
		return
	if on and fall_whoosh_sound:
		if not _fall_whoosh.playing:
			_fall_whoosh.stream = fall_whoosh_sound
			_fall_whoosh.volume_db = fall_whoosh_volume_db
			_fall_whoosh.play()
	elif not on:
		_fall_whoosh.stop()


func _setup_dust() -> void:
	_land_dust = _make_dust(12, 0.45, 70.0, 60.0, 150.0)
	_land_dust.direction = Vector2(1.0, -0.35)
	_jump_dust = _make_dust(8, 0.35, 45.0, 50.0, 110.0)
	_jump_dust.direction = Vector2(0.0, 1.0)
	_run_dust = _make_dust(3, 0.3, 35.0, 30.0, 70.0)
	_run_dust.direction = Vector2(-1.0, -0.4)


func _fx_jump_net() -> void:
	if _is_networked():
		_fx_jump.rpc()
	else:
		_fx_jump()


@rpc("any_peer", "call_local", "reliable")
func _fx_jump() -> void:
	_squash(0.75, 1.32, 0.18)  ## CHANGED: was (0.78, 1.28) - a little more pronounced
	if _jump_dust:
		_jump_dust.restart()


func _fx_land_net(impact: float) -> void:
	if _is_networked():
		_fx_land.rpc(impact)
	else:
		_fx_land(impact)


@rpc("any_peer", "call_local", "reliable")
func _fx_land(impact: float) -> void:
	_squash(lerpf(1.0, 1.44, impact), lerpf(1.0, 0.61, impact), 0.22)  ## CHANGED: was (1.38, 0.66) - a little more pronounced
	if _land_dust and impact > 0.08:
		_land_dust.amount = int(lerpf(4.0, 14.0, impact))
		_land_dust.initial_velocity_max = lerpf(80.0, 190.0, impact)
		_land_dust.restart()


## Player action sounds (jump, land, dash, footstep, ...) used to be bare local
## SfxManager.play calls sitting right next to _fx_jump_net/_fx_land_net -- the
## squash+dust synced to every peer via that RPC, but the sound itself only ever
## played for whichever peer's input actually triggered it. Routed the same
## any_peer/call_local way as apply_stun/apply_hitstop, but unreliable: these are
## frequent, low-stakes cosmetic triggers, not authoritative state, so a dropped
## packet just means one peer misses hearing one jump/footstep, not a desync.
func _play_jump_sound_net() -> void:
	if _is_networked():
		_play_jump_sound.rpc()
	else:
		_play_jump_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_jump_sound() -> void:
	SfxManager.play(jump_sound, -10.0, 0.1)
	SfxManager.play(jump_grunt_sound, jump_grunt_volume_db, 0.12)


func _play_land_sound_net() -> void:
	if _is_networked():
		_play_land_sound.rpc()
	else:
		_play_land_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_land_sound() -> void:
	SfxManager.play(land_sound, -20.0, 0.2)


func _setup_life_hearts() -> void:
	var hearts := LifeHearts.new()
	hearts.name = "LifeHearts"
	hearts.setup(self, bomb_controller)
	add_child(hearts)


func _update_identity() -> void:
	if bomb_controller == null:
		return
	var slot := bomb_controller.get_slot_index()
	var display_name := bomb_controller.get_player_display_name()
	# Slot alone isn't enough to gate this: online, the Steam name can arrive (via
	# Networking's synced RPC) a beat after the player already spawned and its
	# slot settled, so the tag would get stuck on the P<n> fallback forever if
	# this only re-checked on slot change.
	if slot == _identity_slot and display_name == _identity_name:
		return
	_identity_slot = slot
	_identity_name = display_name
	var color := bomb_controller.get_player_color()
	player_tag.text = display_name
	player_tag.add_theme_color_override("font_color", color)
	player_tag.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.35))
	player_tag.add_theme_constant_override("shadow_offset_x", 0)
	player_tag.add_theme_constant_override("shadow_offset_y", 0)
	player_tag.add_theme_constant_override("shadow_outline_size", 3)
	player_tag.add_theme_font_size_override("font_size", 13)
	glow.modulate = Color(color.r, color.g, color.b, 0.7)
	if _player_light:
		_player_light.color = color
	animated_sprite.modulate = Color.WHITE.lerp(color, 0.28)

func _explode_anim_length() -> float:  # NEW: shake lasts exactly as long as the explosion plays
	var frames := animated_sprite.sprite_frames
	var speed: float = frames.get_animation_speed(&"explode")
	if speed <= 0.0:
		return 0.4
	return frames.get_frame_count(&"explode") / speed


func play_death_animation(cause: String = "fall") -> void:
	if is_dead:
		return
	is_dead = true
	_death_animation_id += 1
	var my_id := _death_animation_id
	if _electrocution_tween and _electrocution_tween.is_valid():
		_stop_electrocution_shake()
	velocity = Vector2.ZERO
	var anim_name: StringName
	if cause == "explode":
		anim_name = &"explode"
		SfxManager.play(explode_sound, 0.0, explode_pitch_variance)  
	else:
		anim_name = ANIM_DIE[1 if facing_right else 0]
	animation_name = anim_name
	animated_sprite.sprite_frames.set_animation_loop(animation_name, false)
	animated_sprite.play(animation_name)
	if cause == "explode":
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(10.0, _explode_anim_length())
	await animated_sprite.animation_finished
	# The node can be freed mid-await (round end, arena unload, peer disconnect),
	# at which point get_tree() below would return null.
	if not is_inside_tree() or my_id != _death_animation_id:
		return
	animated_sprite.stop()
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count(animation_name) - 1
	var elapsed := 0.0
	while not is_on_floor() and elapsed < 3.0:
		await get_tree().physics_frame
		if not is_inside_tree() or my_id != _death_animation_id:
			return
		elapsed += get_physics_process_delta_time()


## Victory hop. There is no celebrate animation in the SpriteFrames, so the
## read comes from cadence + squash + dust + an alternating facing flip, driving
## the existing jump/idle frames. Authority-only: peers see it through the
## replicated animation_name, net position and the call_local jump dust.
func play_celebration() -> void:
	if is_dead or is_celebrating:
		return
	is_celebrating = true
	_death_animation_id += 1
	var my_id: int = _death_animation_id
	for index in celebrate_hops:
		while is_inside_tree() and not is_on_floor():
			await get_tree().physics_frame
			if not is_inside_tree() or is_dead or my_id != _death_animation_id:
				is_celebrating = false
				return
		if not is_inside_tree() or is_dead or my_id != _death_animation_id:
			is_celebrating = false
			return
		_celebrate_hop(index)
		await get_tree().create_timer(celebrate_hop_interval).timeout
	is_celebrating = false


func _celebrate_hop(index: int) -> void:
	velocity.y = jump_velocity * celebrate_hop_velocity_scale
	velocity.x = 0.0
	facing_right = index % 2 == 0
	animation_name = ANIM_JUMP[1 if facing_right else 0]
	animated_sprite.play(animation_name)
	_squash(0.72, 1.34, 0.20)
	_play_celebration_hop_sound_net()
	_fx_jump_net()


func _play_celebration_hop_sound_net() -> void:
	if _is_networked():
		_play_celebration_hop_sound.rpc()
	else:
		_play_celebration_hop_sound()


## Deliberately its own RPC rather than reusing _play_jump_sound: the celebration
## hop plays at a different volume and, per the original comment on jump_grunt_sound,
## is deliberately "ungrunted."
@rpc("any_peer", "call_local", "unreliable")
func _play_celebration_hop_sound() -> void:
	SfxManager.play(jump_sound, -12.0, 0.18)


func _update_animation() -> void:
	if is_dead:  
		return  
	if direction != 0.0:
		facing_right = direction > 0.0
		dash_hitbox.scale.x = _dash_hitbox_base_scale_x * (1.0 if facing_right else -1.0)

	var facing: int = 1 if facing_right else 0
	var next_animation: StringName
	var is_walking_now := false
	if not is_on_floor():
		next_animation = ANIM_JUMP[facing]
	elif direction != 0.0:
		next_animation = ANIM_WALK[facing]
		is_walking_now = true
	else:
		next_animation = ANIM_IDLE[facing]

	if is_walking_now and not _was_walking:
		_play_footstep()
	_was_walking = is_walking_now

	if animation_name != next_animation:
		animation_name = next_animation
		animated_sprite.play(animation_name)

func _handle_input(delta: float) -> void:
	var move_x: float
	var move_y: float
	var jump_held: bool
	var dash_held: bool
	
	if bot != null:
		move_x = bot.move_x
		move_y = bot.move_y
		jump_held = bot.jump_held
		dash_held = bot.dash_held
	elif _is_networked():  # NEW: online players merge keyboard + first controller
		var kb_move_x: float = float(Input.is_physical_key_pressed(keyboard_right)) - float(Input.is_physical_key_pressed(keyboard_left))
		var kb_move_y: float = float(Input.is_physical_key_pressed(keyboard_down)) - float(Input.is_physical_key_pressed(keyboard_up))
		var kb_jump_held: bool = Input.is_physical_key_pressed(keyboard_jump)
		var kb_dash_held: bool = Input.is_physical_key_pressed(keyboard_dash) or Input.is_physical_key_pressed(keyboard_dash_alt)
		
		var pad_move_x: float = 0.0
		var pad_move_y: float = 0.0
		var pad_jump_held: bool = false
		var pad_dash_held: bool = false
		var pads: Array[int] = Input.get_connected_joypads()
		if not pads.is_empty():
			var pad_id: int = pads[0]
			pad_move_x = PadState.get_axis(pad_id, JOY_AXIS_LEFT_X)
			pad_move_y = PadState.get_axis(pad_id, JOY_AXIS_LEFT_Y)
			if abs(pad_move_x) < STICK_DEADZONE:
				pad_move_x = 0.0
			if abs(pad_move_y) < STICK_DEADZONE:
				pad_move_y = 0.0
			pad_jump_held = PadState.is_pressed(pad_id, JOY_BUTTON_A)
			pad_dash_held = PadState.is_pressed(pad_id, JOY_BUTTON_X)
		
		move_x = pad_move_x if pad_move_x != 0.0 else kb_move_x
		move_y = pad_move_y if pad_move_y != 0.0 else kb_move_y
		jump_held = kb_jump_held or pad_jump_held
		dash_held = kb_dash_held or pad_dash_held
	else:  # CHANGED: unchanged local-multiplayer logic, exactly as it was before
		var is_keyboard: bool = device_id == LocalPlayers.KEYBOARD_DEVICE_ID
		if is_keyboard:
			move_x = float(Input.is_physical_key_pressed(keyboard_right)) - float(Input.is_physical_key_pressed(keyboard_left))
			move_y = float(Input.is_physical_key_pressed(keyboard_down)) - float(Input.is_physical_key_pressed(keyboard_up))
			jump_held = Input.is_physical_key_pressed(keyboard_jump)
			dash_held = Input.is_physical_key_pressed(keyboard_dash) or Input.is_physical_key_pressed(keyboard_dash_alt)
		else:
			move_x = PadState.get_axis(device_id, JOY_AXIS_LEFT_X)
			move_y = PadState.get_axis(device_id, JOY_AXIS_LEFT_Y)
			if abs(move_x) < STICK_DEADZONE:
				move_x = 0.0
			if abs(move_y) < STICK_DEADZONE:
				move_y = 0.0
			jump_held = PadState.is_pressed(device_id, JOY_BUTTON_A)
			dash_held = PadState.is_pressed(device_id, JOY_BUTTON_X)
	
	direction = move_x
	_last_move_input = Vector2(move_x, move_y)
	
	var jump_just_pressed: bool = jump_held and not _prev_jump_held
	var jump_just_released: bool = not jump_held and _prev_jump_held
	var dash_just_pressed: bool = dash_held and not _prev_dash_held
	_prev_jump_held = jump_held
	_prev_dash_held = dash_held
	
	if MinigameDirector.is_input_locked():
		direction = 0.0
		_last_move_input = Vector2.ZERO
		jump_buffer_counter = 0.0
		coyote_time_counter = 0.0
		return
	
	if dash_just_pressed and not is_dashing and dash_cooldown_left <= 0.0:
		_start_dash()
	
	if is_on_floor():
		coyote_time_counter = coyote_time
	else:
		coyote_time_counter -= delta
	
	if jump_just_pressed:
		jump_buffer_counter = jump_buffer_time
	else:
		jump_buffer_counter -= delta
	
	if jump_buffer_counter > 0.0 and (is_on_floor() or coyote_time_counter > 0.0):
		jump_pressed = true
		jump_buffer_counter = 0.0
		coyote_time_counter = 0.0
	
	if jump_just_released and velocity.y < 0.0:
		cut_jump = true


func _apply_movement(delta: float) -> void:
	if dash_cooldown_left > 0.0:
		dash_cooldown_left -= delta
	
	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			is_dashing = false
			dash_hitbox.monitoring = false
			velocity = dash_direction * dash_speed * dash_end_momentum_retention
			dash_afterimage.stop()
		return
	
	var zone := _get_safe_zone()
	var outside_zone: bool = zone != null and zone.is_outside(global_position)
	
	var grounded: bool = is_on_floor()
	var speed_mult: float = zone_move_speed_multiplier if outside_zone else 1.0  # NEW
	var target_x: float = direction * speed * speed_mult  # CHANGED: was "direction * speed"
	var rate: float
	if is_zero_approx(direction):
		rate = friction if grounded else air_friction
	elif not is_zero_approx(velocity.x) and signf(direction) != signf(velocity.x):
		rate = turn_acceleration
	else:
		rate = acceleration if grounded else air_acceleration
	velocity.x = move_toward(velocity.x, target_x, rate * delta)

	if grounded and not jump_pressed:
		velocity.y = 0.0
	
	if jump_pressed:
		velocity.y = jump_velocity * (zone_jump_multiplier if outside_zone else 1.0)  # CHANGED: softened jump in the zone
		jump_pressed = false
		_play_jump_sound_net()
		_fx_jump_net()
	
	if cut_jump:
		velocity.y *= jump_cut_off
		cut_jump = false
	
	var fast_falling: bool = not grounded and _last_move_input.y > 0.5 and velocity.y > 0.0
	var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
	if fast_falling:
		gravity *= fast_fall_gravity_mult
	elif not grounded and absf(velocity.y) < apex_threshold:
		gravity *= apex_gravity_mult
	
	if outside_zone:
		gravity *= zone_gravity_multiplier  # CHANGED: was "zone.outer_gravity_multiplier", now a dedicated export instead of pulling from the zone resource
	
	velocity.y += gravity * delta
	if fast_falling:
		velocity.y = minf(velocity.y, fast_fall_max_speed)
	
	if outside_zone:  # NEW: the actual "thick resistance" feel
		velocity = velocity.move_toward(Vector2.ZERO, zone_drag * delta * velocity.length())
	
	_update_zone_timer(delta, outside_zone, zone)

func _get_dash_direction() -> Vector2:
	var raw := _last_move_input
	if raw.length() < 0.2:
		raw = Vector2.RIGHT if facing_right else Vector2.LEFT
	
	var angle := raw.angle()
	var snapped_angle: float = round(angle / (PI / 4.0)) * (PI / 4.0)
	return Vector2.RIGHT.rotated(snapped_angle)


func _start_dash() -> void:
	is_dashing = true
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown
	dash_direction = _get_dash_direction()
	dash_start_time_ms = _get_timestamp()  
	velocity = dash_direction * dash_speed
	# The hitbox itself never flips on its own -- this player uses separate
	# left/right animations rather than sprite flipping, so nothing else in this
	# script ever touches dash_hitbox's transform. Without this it stays on
	# whatever side it was placed on in the editor no matter which way you dash.
	if dash_direction.x != 0.0:
		dash_hitbox.scale.x = _dash_hitbox_base_scale_x * signf(dash_direction.x)
	dash_hitbox.monitoring = true
	_play_dash_sound_net()
	_squash(1.3, 0.75, 0.2)
	dash_afterimage.start()


func _play_dash_sound_net() -> void:
	if _is_networked():
		_play_dash_sound.rpc()
	else:
		_play_dash_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_dash_sound() -> void:
	SfxManager.play(dash_sound, -15.0)


func _end_dash_immediately() -> void:
	is_dashing = false
	dash_hitbox.monitoring = false
	velocity = dash_direction * dash_speed * dash_end_momentum_retention

func _on_dash_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if not body.is_in_group("players"):
		return
	if body.has_method("is_invulnerable") or "is_invulnerable" in body:
		if body.is_invulnerable:
			return

	if body.get("is_shielded") == true:
		# The shield blocks all stun/knockback on the defender (see _do_apply_stun's
		# is_shielded early return) -- the attacker bounces off as if they'd hit
		# something solid. No flash_dash_loss here: that cue is specifically for
		# losing your own dash to a conflict, which isn't what happened. body.apply_stun
		# still has to be called (even though it never actually stuns the shielded
		# victim) so this blocked hit reaches _do_apply_stun's single choke point and
		# consumes the shield there, same as every other source that funnels through it.
		apply_stun(-dash_direction, dash_conflict_knockback_multiplier)
		apply_hitstop(hitstop_duration)
		if body.has_method("play_shield_block_sound"):
			body.play_shield_block_sound()
		if body.has_method("apply_stun"):
			body.apply_stun(dash_direction, dash_conflict_knockback_multiplier, -1.0, name.to_int(), _current_identity_name(), _current_identity_color())
		return

	# Counter-slam clash: body counts as "recently dashed" either because it's
	# still literally mid-dash, or because its dash started within
	# counter_window_ms of now - the old behavior only ever allowed the former,
	# implicitly bounding the window to dash_duration (~150ms) with no tolerance
	# at all for a dash that had *just* finished.
	var body_dash_start: int = int(body.get("dash_start_time_ms"))
	var time_diff: int = dash_start_time_ms - body_dash_start
	var is_counter_clash: bool = body.get("is_dashing") == true or absi(time_diff) <= counter_window_ms
	if is_counter_clash:
		var i_win: bool = time_diff > 0
		if absi(time_diff) <= COUNTER_TIEBREAK_MS:
			# Close enough together that dash_start_time_ms can't be trusted to
			# resolve this alone - it may not have finished replicating to whichever
			# peer is running this check yet (see net_position's own 33ms
			# replication_interval on this same synchronizer), and both sides
			# independently reaching "I'm later" from their own stale view of the
			# other is exactly how a collision used to resolve as a mutual
			# knockback. player.name.to_int() has no replication lag at all - every
			# peer already knows it exactly - so it always picks the same single
			# winner regardless of which side evaluates it first.
			i_win = name.to_int() > body.name.to_int()
		if not i_win:
			return
		if body.has_method("apply_stun"):
			body.apply_stun(dash_direction, dash_conflict_knockback_multiplier, -1.0, name.to_int(), _current_identity_name(), _current_identity_color())
		if body.has_method("apply_hitstop"):
			body.apply_hitstop(hitstop_duration)
		if body.has_method("flash_dash_loss"):
			body.flash_dash_loss()
		return

	if body.has_method("apply_stun"):
		body.apply_stun(dash_direction, 1.0, -1.0, name.to_int(), _current_identity_name(), _current_identity_color())
	apply_hitstop(hitstop_duration)
	if body.has_method("apply_hitstop"):
		body.apply_hitstop(hitstop_duration)

## duration_override < 0 keeps the default stun_duration export (dash-collision
## behavior is untouched); callers like the lightning strike event pass an explicit
## duration instead. attacker_key/name/color are for kill-feed/stats attribution
## only - left at their defaults (-1, unset) for environmental stuns like the
## lightning strike, which have no attacking player to credit. attacker_key is the
## attacker's player.name.to_int(), the same identifier MinigameDirector's match
## stats and _alive_peer_ids already key everything by.
func apply_stun(from_direction: Vector2, knockback_multiplier: float = 1.0, duration_override: float = -1.0, attacker_key: int = -1, attacker_name: String = "", attacker_color: Color = Color.WHITE) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_stun(from_direction, knockback_multiplier, duration_override, attacker_key, attacker_name, attacker_color)
	else:
		_do_apply_stun.rpc(from_direction, knockback_multiplier, duration_override, attacker_key, attacker_name, attacker_color)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_stun(from_direction: Vector2, knockback_multiplier: float = 1.0, duration_override: float = -1.0, attacker_key: int = -1, attacker_name: String = "", attacker_color: Color = Color.WHITE) -> void:
	if is_shielded:
		# Single-use: the shield absorbs exactly one blocked stun (storm, another
		# player's dash, a hazard - anything that funnels through apply_stun) and
		# drops immediately, rather than continuing to block until its timer runs
		# out on its own. This is the one choke point every stun source goes
		# through, so consuming it here covers all of them.
		is_shielded = false
		shield_time_left = 0.0
		_set_shield_outline_active(false)
		return
	if attacker_key >= 0:
		_last_attacker_key = attacker_key
		_last_attacker_name = attacker_name
		_last_attacker_color = attacker_color
		_last_attacker_time_ms = Time.get_ticks_msec()
	var duration: float = stun_duration if duration_override < 0.0 else duration_override
	is_dashing = false
	dash_hitbox.monitoring = false
	dash_afterimage.stop()
	is_stunned = true
	stun_time_left = duration
	velocity = from_direction * knockback_speed * knockback_multiplier
	SfxManager.play(slam_sound, -10.0, 0.1)
	_tilt_on_stun(from_direction, duration)

func _tilt_on_stun(from_direction: Vector2, duration: float) -> void:
	var tilt_angle: float = deg_to_rad(stun_tilt_angle_degrees) * sign(from_direction.x if from_direction.x != 0.0 else 1.0)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "rotation", tilt_angle, 0.08)
	tween.tween_property(animated_sprite, "rotation", 0.0, duration - 0.08)

## Electrocution: the same apply_stun the hazard already used for its stun/damage,
## plus a shock jitter layered on top for exactly the same duration. Called from
## power_station.gd's electrified-platform check in place of the bare apply_stun
## call it used before.
func apply_electrocution(duration: float) -> void:
	apply_stun(Vector2.ZERO, 0.0, duration)
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_electrocution(duration)
	else:
		_do_apply_electrocution.rpc(duration)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_electrocution(duration: float) -> void:
	_start_electrocution_shake(duration)

## Loops a tween_callback + tween_interval pair rather than tween_property, since
## tween_property bakes in fixed values that would just repeat the same motion
## every loop - a callback re-rolls a fresh random offset each time it fires,
## which is what actually reads as a vibration instead of a wobble.
func _start_electrocution_shake(duration: float) -> void:
	_electrocution_shake_id += 1
	var my_id := _electrocution_shake_id
	var already_shaking: bool = _electrocution_tween != null and _electrocution_tween.is_valid()
	if already_shaking:
		_electrocution_tween.kill()
	else:
		# Only capture the resting position when actually starting from rest - a
		# re-electrocution mid-shake must keep the ORIGINAL base, not re-anchor to
		# wherever the jitter happened to be at that instant, or every subsequent
		# settle would drift to that jittered spot instead of true (0,0)-local rest.
		_electrocution_base_position = animated_sprite.position
	_electrocution_tween = create_tween()
	_electrocution_tween.set_loops()
	_electrocution_tween.tween_callback(_apply_electrocution_jitter)
	_electrocution_tween.tween_interval(ELECTROCUTION_SHAKE_INTERVAL)
	await get_tree().create_timer(duration).timeout
	# A newer shake (re-zapped mid-shake) or an explicit interrupt (death/respawn)
	# may have already taken over and stopped this one - don't stomp on whatever
	# state it left behind.
	if my_id != _electrocution_shake_id or not is_inside_tree():
		return
	_stop_electrocution_shake()

func _apply_electrocution_jitter() -> void:
	var offset := Vector2(
		randf_range(-ELECTROCUTION_SHAKE_AMPLITUDE, ELECTROCUTION_SHAKE_AMPLITUDE),
		randf_range(-ELECTROCUTION_SHAKE_AMPLITUDE, ELECTROCUTION_SHAKE_AMPLITUDE)
	)
	animated_sprite.position = _electrocution_base_position + offset

## Also used as the interrupt path (death/respawn) - eases back rather than
## snapping either way, per spec ("snap or ease"), so there's one code path for
## both the normal end-of-duration stop and an early interrupt.
func _stop_electrocution_shake() -> void:
	_electrocution_shake_id += 1  # invalidates any pending auto-stop still awaiting above
	if _electrocution_tween and _electrocution_tween.is_valid():
		_electrocution_tween.kill()
	var tween := create_tween()
	tween.tween_property(animated_sprite, "position", _electrocution_base_position, ELECTROCUTION_SETTLE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func apply_hitstop(duration: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_hitstop(duration)
	else:
		_do_apply_hitstop.rpc(duration)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_hitstop(duration: float) -> void:
	is_frozen = true
	freeze_time_left = duration
	animated_sprite.speed_scale = 0.0


func _on_animation_frame_changed() -> void:
	if animation_name != ANIM_WALK[0] and animation_name != ANIM_WALK[1]:
		return
	if animated_sprite.frame in footstep_frames:
		_play_footstep()

func _play_footstep() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_footstep_time < footstep_debounce:
		return
	_last_footstep_time = now
	if _run_dust:
		_run_dust.direction = Vector2(-1.0 if facing_right else 1.0, -0.4)
		_run_dust.restart()
	# _on_animation_frame_changed (above) is wired up for every player instance on
	# every peer, unauthority-gated, because that's what lets everyone already see
	# everyone else's run-dust kick up correctly off the *replicated* animation_name
	# -- so this whole function already runs once per peer per footstep. Only
	# broadcast the sound from the authority, or every peer watching would each
	# fire their own copy and it'd multiply by player count.
	if not _is_networked() or is_multiplayer_authority():
		_play_footstep_sound_net()


func _play_footstep_sound_net() -> void:
	if _is_networked():
		_play_footstep_sound.rpc()
	else:
		_play_footstep_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_footstep_sound() -> void:
	SfxManager.play(footstep_sound, -4.0 + randf_range(-2.0, 2.0), footstep_pitch_variance)


func _check_landing() -> void:
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		_play_land_sound_net()
		_fx_land_net(clampf(_fall_speed / land_impact_reference, 0.0, 1.0))
	_was_on_floor = on_floor_now

func respawn(invuln_duration: float) -> void:
	_death_animation_id += 1
	is_dead = false
	_last_attacker_key = -1
	_set_fall_fx(false)
	_fall_fx_last_y = global_position.y
	_fall_distance = 0.0
	velocity = Vector2.ZERO
	is_stunned = false
	is_frozen = false
	is_shielded = false
	shield_time_left = 0.0
	_set_shield_outline_active(false)
	if _electrocution_tween and _electrocution_tween.is_valid():
		_stop_electrocution_shake()
	is_dashing = false
	dash_time_left = 0.0
	dash_hitbox.monitoring = false
	dash_afterimage.stop()
	animated_sprite.speed_scale = 1.0
	animated_sprite.modulate.a = 1.0
	animated_sprite.scale = _sprite_base_scale
	visible = true
	animation_name = ANIM_IDLE[1 if facing_right else 0]
	is_invulnerable = true
	_invuln_time_left = invuln_duration
	_invuln_flash_timer = 0.0

func _get_timestamp() -> int:  
	if _is_networked():
		return Networking.get_sync_time()
	return Time.get_ticks_msec()

func flash_dash_loss() -> void:  # NEW
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_flash_dash_loss()
	else:
		_do_flash_dash_loss.rpc()

@rpc("any_peer", "call_local", "reliable")
func _do_flash_dash_loss() -> void:
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate", dash_conflict_flash_color, dash_conflict_flash_duration * 0.3)
	tween.tween_property(animated_sprite, "modulate", Color.WHITE.lerp(_current_identity_color(), 0.28), dash_conflict_flash_duration * 0.7)

## Called on the shielded player (the one dashed into), from the attacker's
## _on_dash_hitbox_body_entered - same any_peer/call_local cross-player-triggered
## pattern as apply_stun/flash_dash_loss above, so it plays once, from the
## shielded player's side, on every peer.
func play_shield_block_sound() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_play_shield_block_sound()
	else:
		_do_play_shield_block_sound.rpc()

@rpc("any_peer", "call_local", "unreliable")
func _do_play_shield_block_sound() -> void:
	SfxManager.play(shield_block_sound, shield_block_volume_db)

func _current_identity_color() -> Color:
	if bomb_controller:
		return bomb_controller.get_player_color()
	return Color.WHITE

func _current_identity_name() -> String:
	if bomb_controller:
		return bomb_controller.get_player_display_name()
	return "P?"

## Empty dict = no recent attacker, death reads as environmental (fall/explode).
## "key" is the attacker's player.name.to_int(), used to credit the kill to the
## right player in MinigameDirector's match stats (same identifier the kill feed's
## name/color already come from).
func get_kill_credit() -> Dictionary:
	if _last_attacker_key < 0:
		return {}
	if Time.get_ticks_msec() - _last_attacker_time_ms > ATTACKER_CREDIT_WINDOW_MS:
		return {}
	return {"key": _last_attacker_key, "name": _last_attacker_name, "color": _last_attacker_color}

## Refreshes/extends shield_time_left rather than stacking if already shielded. See
## _do_apply_stun for where the shield actually blocks stun/knockback.
func apply_shield(duration: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_shield(duration)
	else:
		_do_apply_shield.rpc(duration)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_shield(duration: float) -> void:
	var is_new_activation: bool = not is_shielded
	is_shielded = true
	shield_time_left = duration
	if is_new_activation:
		_set_shield_outline_active(true)

## Toggled at the same on/off points the old shield particle effect used (natural
## expiry in _process, consumed-by-block in _do_apply_stun, cleared on death in
## respawn, activation here) - just swapping what visual actually turns on, a
## silhouette outline on the sprite itself instead of an orbiting particle ring.
func _set_shield_outline_active(active: bool) -> void:
	if active:
		var mat := _shared_shield_outline_material()
		mat.set_shader_parameter("outline_color", shield_flash_color)
		animated_sprite.material = mat
	else:
		animated_sprite.material = null

const SHIELD_OUTLINE_SHADER := """
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.3216, 0.6392, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.5;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a > 0.5) {
		COLOR = tex_color;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float neighbor_alpha = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
			+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (neighbor_alpha > 0.0) {
			COLOR = outline_color;
		} else {
			COLOR = tex_color;
		}
	}
}
"""

## Built once, shared across every Player instance (same caching idiom as the
## other _shared_* materials in this project) - toggled on/off per-player by
## assigning/clearing animated_sprite.material rather than by touching any
## per-instance shader parameters, so idle (unshielded) players pay zero cost.
static var _shield_outline_material: ShaderMaterial

static func _shared_shield_outline_material() -> ShaderMaterial:
	if _shield_outline_material == null:
		var shader := Shader.new()
		shader.code = SHIELD_OUTLINE_SHADER
		_shield_outline_material = ShaderMaterial.new()
		_shield_outline_material.shader = shader
	return _shield_outline_material

func _get_safe_zone() -> Node:  
	return get_tree().get_first_node_in_group("safe_zones")

func _update_zone_timer(delta: float, outside: bool, zone: Node) -> void:
	if zone == null:
		_zone_outside_timer = 0.0
		if _danger_ring:
			_danger_ring.set_progress(0.0)  
		return
	if outside:
		_zone_outside_timer += delta
		if _danger_ring:  
			_danger_ring.set_progress(_zone_outside_timer / zone.outside_death_time)  # NEW
		if _zone_outside_timer >= zone.outside_death_time and not is_dead 				and not MinigameDirector.is_input_locked():
			bomb_controller.player_died("explode")
	else:
		_zone_outside_timer = 0.0
		if _danger_ring:  
			_danger_ring.set_progress(0.0)
