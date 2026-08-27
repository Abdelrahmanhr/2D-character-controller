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


func _ready() -> void:
	_recalculate_jump_physics()


func _recalculate_jump_physics() -> void:
	rise_gravity = (2.0 * jump_height) / (time_to_peak * time_to_peak)
	fall_gravity = (2.0 * jump_height) / (time_to_descent * time_to_descent)
	jump_velocity = -rise_gravity * time_to_peak


func _physics_process(delta: float) -> void:
	_handle_input(delta)
	_apply_movement(delta)
	move_and_slide()


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
