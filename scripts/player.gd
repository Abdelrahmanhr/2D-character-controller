extends CharacterBody2D
@export var speed: float = 300.0
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

@export var device_id: int = -2  #-1 = keyboard, 0+ = joypad index, -2 = unassigned
@export var keyboard_left: Key = KEY_A  
@export var keyboard_right: Key = KEY_D  
@export var keyboard_up: Key = KEY_W  
@export var keyboard_down: Key = KEY_S 
@export var keyboard_jump: Key = KEY_SPACE  
@export var keyboard_dash: Key = KEY_SHIFT  

const STICK_DEADZONE: float = 0.2

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

var is_dead := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var player_tag: Label = $PlayerTag
@onready var glow: Sprite2D = $Glow
@onready var bomb_controller: BombController = $BombController
@onready var dash_hitbox: Area2D = $DashHitbox

var _identity_slot: int = -1


func _ready() -> void:
	dash_hitbox.body_entered.connect(_on_dash_hitbox_body_entered)
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	dash_hitbox.monitoring = false
	add_to_group("players")
	_recalculate_jump_physics()
	_setup_glow_texture()
	_update_identity()
	if _is_networked() and is_multiplayer_authority() and device_id == -2:  # NEW
		device_id = -1  # NEW: default to keyboard for online play, since there's no lobby-side device picker for online yet
		if bomb_controller:  # NEW
			bomb_controller.device_id = -1  # NEW

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _is_networked() -> bool:  # NEW
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _recalculate_jump_physics() -> void:
	rise_gravity = (2.0 * jump_height) / (time_to_peak * time_to_peak)
	fall_gravity = (2.0 * jump_height) / (time_to_descent * time_to_descent)
	jump_velocity = -rise_gravity * time_to_peak


func _physics_process(delta: float) -> void:
	if is_dead:
		var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
		velocity.y += gravity * delta
		move_and_slide()
		return
	if _is_networked() and not is_multiplayer_authority():  # CHANGED: was "if not is_multiplayer_authority(): return"
		return
	
	
	if is_frozen:
		freeze_time_left -= delta
		if freeze_time_left <= 0.0:
			is_frozen = false
			animated_sprite.speed_scale = 1.0
		return
	
	
	if is_stunned:
		if is_dashing:
			_end_dash_immediately()
		_apply_stun_physics(delta)
		move_and_slide()
		_update_animation()
		return
	
	_handle_input(delta)
	_apply_movement(delta)
	move_and_slide()
	_check_landing()
	_update_animation()
	

func _apply_stun_physics(delta: float) -> void:
	stun_time_left -= delta
	if stun_time_left <= 0.0:
		is_stunned = false
	
	var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
	velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)


func _process(_delta: float) -> void:
	_update_identity()
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
	animated_sprite.modulate = Color.WHITE.lerp(color, 0.28)

func play_death_animation() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	var facing := "right" if facing_right else "left"
	animation_name = StringName("die_" + facing)
	animated_sprite.sprite_frames.set_animation_loop(animation_name, false)
	animated_sprite.play(animation_name)
	await animated_sprite.animation_finished
	animated_sprite.stop()
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count(animation_name) - 1
	var elapsed := 0.0
	while not is_on_floor() and elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()



func _update_animation() -> void:
	if direction != 0.0:
		facing_right = direction > 0.0

	var facing := "right" if facing_right else "left"
	var next_animation: StringName
	if not is_on_floor():
		next_animation = StringName("jump_" + facing)
	elif direction != 0.0:
		next_animation = StringName("walk_" + facing)
	else:
		next_animation = StringName("idle_" + facing)

	var is_walking_now := next_animation.begins_with("walk_")
	if is_walking_now and not _was_walking:
		_play_footstep()
	_was_walking = is_walking_now

	if animation_name != next_animation:
		animation_name = next_animation
		animated_sprite.play(animation_name)

func _handle_input(delta: float) -> void:  # CHANGED: full per-device rewrite, see below
	var is_keyboard: bool = device_id == LocalPlayers.KEYBOARD_DEVICE_ID  # NEW
	
	var move_x: float  # NEW
	var move_y: float  # NEW
	var jump_held: bool  # NEW
	var dash_held: bool  # NEW
	
	if is_keyboard:  # NEW
		move_x = float(Input.is_physical_key_pressed(keyboard_right)) - float(Input.is_physical_key_pressed(keyboard_left))
		move_y = float(Input.is_physical_key_pressed(keyboard_down)) - float(Input.is_physical_key_pressed(keyboard_up))
		jump_held = Input.is_physical_key_pressed(keyboard_jump)
		dash_held = Input.is_physical_key_pressed(keyboard_dash)
	else:  
		move_x = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
		move_y = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		if abs(move_x) < STICK_DEADZONE:  
			move_x = 0.0  
		if abs(move_y) < STICK_DEADZONE:  # NEW
			move_y = 0.0  # NEW
		jump_held = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
		dash_held = Input.is_joy_button_pressed(device_id, JOY_BUTTON_X)
	
	direction = move_x  # CHANGED: was Input.get_axis("move_left", "move_right")
	_last_move_input = Vector2(move_x, move_y)  # NEW
	
	var jump_just_pressed: bool = jump_held and not _prev_jump_held  # NEW
	var jump_just_released: bool = not jump_held and _prev_jump_held  # NEW
	var dash_just_pressed: bool = dash_held and not _prev_dash_held  # NEW
	_prev_jump_held = jump_held  
	_prev_dash_held = dash_held 
	
	if dash_just_pressed and not is_dashing and dash_cooldown_left <= 0.0:  # CHANGED: was Input.is_action_just_pressed("dash")
		_start_dash()
	
	if is_on_floor():
		coyote_time_counter = coyote_time
	else:
		coyote_time_counter -= delta
	
	if jump_just_pressed:  # CHANGED: was Input.is_action_just_pressed("jump")
		jump_buffer_counter = jump_buffer_time
	else:
		jump_buffer_counter -= delta
	
	if jump_buffer_counter > 0.0 and (is_on_floor() or coyote_time_counter > 0.0):
		jump_pressed = true
		jump_buffer_counter = 0.0
		coyote_time_counter = 0.0

	if jump_just_released and velocity.y < 0.0:  # CHANGED: was Input.is_action_just_released("jump")
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
		return
	
	velocity.x = direction * speed
	if is_on_floor() and not jump_pressed:
		velocity.y = 0.0
	
	if jump_pressed:
		velocity.y = jump_velocity
		jump_pressed = false
		SfxManager.play(jump_sound,-10.0,0.1) 
	
	if cut_jump:
		velocity.y *= jump_cut_off
		cut_jump = false
	
	var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
	velocity.y += gravity * delta

func _get_dash_direction() -> Vector2:
	var raw := _last_move_input  # CHANGED: was Input.get_axis(...) x2
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
	velocity = dash_direction * dash_speed
	dash_hitbox.monitoring = true
	SfxManager.play(dash_sound,-15.0)

func _end_dash_immediately() -> void:
	is_dashing = false
	dash_hitbox.monitoring = false
	velocity = dash_direction * dash_speed * dash_end_momentum_retention

func _on_dash_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if not body.is_in_group("players"):
		return
	if body.has_method("apply_stun"):
		body.apply_stun(dash_direction)
	apply_hitstop(hitstop_duration)
	if body.has_method("apply_hitstop"):
		body.apply_hitstop(hitstop_duration)


func apply_stun(from_direction: Vector2) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_do_apply_stun(from_direction)
	else:
		_do_apply_stun.rpc(from_direction)

@rpc("any_peer", "call_local", "reliable")
func _do_apply_stun(from_direction: Vector2) -> void:
	is_stunned = true
	stun_time_left = stun_duration
	velocity = from_direction * knockback_speed
	SfxManager.play(slam_sound, -10.0, 0.1)
	

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
	if not animation_name.begins_with("walk_"):
		return
	if animated_sprite.frame in footstep_frames:
		_play_footstep()

func _play_footstep() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_footstep_time < footstep_debounce:
		return
	_last_footstep_time = now
	SfxManager.play(footstep_sound, -4.0 + randf_range(-2.0, 2.0), footstep_pitch_variance)


func _check_landing() -> void:
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		SfxManager.play(land_sound,-20.0,0.2)
	_was_on_floor = on_floor_now
