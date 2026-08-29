extends CharacterBody2D
@export var speed: float = 300.0
@export var jump_height: float = 64.0
@export var time_to_peak: float = 0.35
@export var time_to_descent: float = 0.28
@export var jump_cut_off: float = 0.5
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.1

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

var _identity_slot: int = -1


func _ready() -> void:
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
	_handle_input(delta)
	_apply_movement(delta)
	move_and_slide()
	_update_animation()


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