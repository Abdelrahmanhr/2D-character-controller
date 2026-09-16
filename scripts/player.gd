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
@export var dash_conflict_knockback_multiplier: float = 2.0
@export var dash_conflict_flash_color: Color = Color(0.8667, 0.2157, 0.2706, 1.0) 
@export var dash_conflict_flash_duration: float = 0.25 
@export var explode_sound: AudioStream  
@export var explode_pitch_variance: float = 0.1  

@export var stun_tilt_angle_degrees: float = 25.0  
@export var stun_tilt_speed: float = 10.0  

@export var device_id: int = -2
@export var keyboard_left: Key = KEY_A  
@export var keyboard_right: Key = KEY_D  
@export var keyboard_up: Key = KEY_W  
@export var keyboard_down: Key = KEY_S 
@export var keyboard_jump: Key = KEY_SPACE  
@export var keyboard_dash: Key = KEY_SHIFT  
@export var keyboard_dash_alt: Key = KEY_F  # NEW: the itch page advertised F but nothing read it

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
var _sprite_base_scale: Vector2 = Vector2.ONE
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
	add_to_group("players")
	_recalculate_jump_physics()
	_setup_glow_texture()
	_update_identity()
	_setup_life_hearts()
	_setup_danger_ring()  # NEW
	_sprite_base_scale = animated_sprite.scale
	_setup_dust()
	_setup_fall_fx()
	_net_position = global_position  # so the first sync carries the spawn point, not (0, 0)
	if _is_networked() and is_multiplayer_authority() and device_id == -2:
		device_id = -1
		if bomb_controller:
			bomb_controller.device_id = device_id

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
	_squash(0.78, 1.28, 0.18)
	if _jump_dust:
		_jump_dust.restart()


func _fx_land_net(impact: float) -> void:
	if _is_networked():
		_fx_land.rpc(impact)
	else:
		_fx_land(impact)


@rpc("any_peer", "call_local", "reliable")
func _fx_land(impact: float) -> void:
	_squash(lerpf(1.0, 1.38, impact), lerpf(1.0, 0.66, impact), 0.22)
	if _land_dust and impact > 0.08:
		_land_dust.amount = int(lerpf(4.0, 14.0, impact))
		_land_dust.initial_velocity_max = lerpf(80.0, 190.0, impact)
		_land_dust.restart()


func _setup_life_hearts() -> void:
	var hearts := LifeHearts.new()
	hearts.name = "LifeHearts"
	hearts.setup(self, bomb_controller)
	add_child(hearts)


func _update_identity() -> void:
	if bomb_controller == null:
		return
	var slot := bomb_controller.get_slot_index()
	if slot == _identity_slot:
		return
	_identity_slot = slot
	var color := bomb_controller.get_player_color()
	player_tag.text = "P%d" % (slot + 1)
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
	SfxManager.play(jump_sound, -12.0, 0.18)
	_fx_jump_net()


func _update_animation() -> void:
	if is_dead:  
		return  
	if direction != 0.0:
		facing_right = direction > 0.0

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
	
	if _is_networked():  # NEW: online players merge keyboard + first controller
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
		SfxManager.play(jump_sound,-10.0,0.1) 
		SfxManager.play(jump_grunt_sound, jump_grunt_volume_db, 0.12)
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
	dash_hitbox.monitoring = true
	SfxManager.play(dash_sound,-15.0)
	_squash(1.3, 0.75, 0.2)
	dash_afterimage.start()
	
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
	
	if body.get("is_dashing") == true:
		if dash_start_time_ms <= body.dash_start_time_ms:
			return
		if body.has_method("apply_stun"):
			body.apply_stun(dash_direction, dash_conflict_knockback_multiplier)
		if body.has_method("apply_hitstop"):
			body.apply_hitstop(hitstop_duration)
		if body.has_method("flash_dash_loss"): 
			body.flash_dash_loss()  
		return
	
	if body.has_method("apply_stun"):
		body.apply_stun(dash_direction)
	apply_hitstop(hitstop_duration)
	if body.has_method("apply_hitstop"):
		body.apply_hitstop(hitstop_duration)
		
func apply_stun(from_direction: Vector2, knockback_multiplier: float = 1.0) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_stun(from_direction, knockback_multiplier)
	else:
		_do_apply_stun.rpc(from_direction, knockback_multiplier)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_stun(from_direction: Vector2, knockback_multiplier: float = 1.0) -> void:
	is_dashing = false
	dash_hitbox.monitoring = false
	dash_afterimage.stop()
	is_stunned = true
	stun_time_left = stun_duration
	velocity = from_direction * knockback_speed * knockback_multiplier
	SfxManager.play(slam_sound, -10.0, 0.1)
	_tilt_on_stun(from_direction)  

func _tilt_on_stun(from_direction: Vector2) -> void:  
	var tilt_angle: float = deg_to_rad(stun_tilt_angle_degrees) * sign(from_direction.x if from_direction.x != 0.0 else 1.0)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "rotation", tilt_angle, 0.08)
	tween.tween_property(animated_sprite, "rotation", 0.0, stun_duration - 0.08)

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
	SfxManager.play(footstep_sound, -4.0 + randf_range(-2.0, 2.0), footstep_pitch_variance)
	if _run_dust:
		_run_dust.direction = Vector2(-1.0 if facing_right else 1.0, -0.4)
		_run_dust.restart()


func _check_landing() -> void:
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		SfxManager.play(land_sound,-20.0,0.2)
		_fx_land_net(clampf(_fall_speed / land_impact_reference, 0.0, 1.0))
	_was_on_floor = on_floor_now

func respawn(invuln_duration: float) -> void:
	_death_animation_id += 1
	is_dead = false
	_set_fall_fx(false)
	_fall_fx_last_y = global_position.y
	_fall_distance = 0.0
	velocity = Vector2.ZERO
	is_stunned = false
	is_frozen = false
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
	
func _current_identity_color() -> Color:  
	if bomb_controller:
		return bomb_controller.get_player_color()
	return Color.WHITE

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
