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
	dash_hitbox.monitoring = false
	add_to_group("players")
	_recalculate_jump_physics()
	_setup_glow_texture()
	_update_identity()

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _recalculate_jump_physics() -> void:
	rise_gravity = (2.0 * jump_height) / (time_to_peak * time_to_peak)
	fall_gravity = (2.0 * jump_height) / (time_to_descent * time_to_descent)
	jump_velocity = -rise_gravity * time_to_peak


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_multiplayer_authority():
		return
	
	
	if is_frozen:
		freeze_time_left -= delta
		if freeze_time_left <= 0.0:
			is_frozen = false
			animated_sprite.speed_scale = 1.0
		return
	
	
	if is_stunned:
		_apply_stun_physics(delta)
		move_and_slide()
		_update_animation()
		return
	
	_handle_input(delta)
	_apply_movement(delta)
	move_and_slide()
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

	if animation_name != next_animation:
		animation_name = next_animation
		animated_sprite.play(animation_name)

func _handle_input(delta: float) -> void:
	
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_left <= 0.0:
		_start_dash()
	
	direction = Input.get_axis("move_left", "move_right")
	if is_on_floor():
		coyote_time_counter = coyote_time
	else:
		coyote_time_counter -= delta
	
	if Input.is_action_just_pressed("jump"):
		jump_buffer_counter = jump_buffer_time
	else:
		jump_buffer_counter -= delta
	
	if jump_buffer_counter > 0.0 and (is_on_floor() or coyote_time_counter > 0.0):
		jump_pressed = true
		jump_buffer_counter = 0.0
		coyote_time_counter = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
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
	
	if cut_jump:
		velocity.y *= jump_cut_off
		cut_jump = false
	
	var gravity: float = rise_gravity if velocity.y < 0.0 else fall_gravity
	velocity.y += gravity * delta

func _get_dash_direction() -> Vector2:
	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
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
