extends BotController
class_name TutorialPuppet

signal command_finished

enum Mode { IDLE, WALK, DASH }

const DASH_HOLD_FRAMES: int = 4
const DASH_RANGE: float = 120.0
const ARRIVE_EPSILON: float = 12.0

var solving: bool = true

var _mode: Mode = Mode.IDLE
var _goal_x: float = 0.0
var _dash_target: Node2D = null
var _dash_frames: int = 0
var _dashed: bool = false


func _ready() -> void:
	super()
	_goal_x = _player.global_position.x


func _physics_process(delta: float) -> void:
	if solving:
		_think_minigame(delta)

	move_x = 0.0
	move_y = 0.0
	jump_held = false
	dash_held = false

	if _player.is_dead or _player.is_stunned or MinigameDirector.is_match_finished():
		return

	match _mode:
		Mode.WALK:
			_drive_walk()
		Mode.DASH:
			_drive_dash()
		_:
			pass


func stand_still() -> void:
	_mode = Mode.IDLE
	_dash_target = null


func walk_to(world_x: float) -> void:
	_mode = Mode.WALK
	_goal_x = world_x


func dash_at(target: Node2D) -> void:
	_mode = Mode.DASH
	_dash_target = target
	_dash_frames = 0
	_dashed = false


func is_idle() -> bool:
	return _mode == Mode.IDLE


func _drive_walk() -> void:
	var dx: float = _goal_x - _player.global_position.x
	if absf(dx) <= ARRIVE_EPSILON:
		_mode = Mode.IDLE
		command_finished.emit()
		return
	move_x = signf(dx)


func _drive_dash() -> void:
	if not is_instance_valid(_dash_target):
		stand_still()
		return

	var dx: float = _dash_target.global_position.x - _player.global_position.x
	var direction: float = signf(dx) if absf(dx) > 1.0 else 1.0

	if _dashed:
		_dash_frames -= 1
		move_x = direction
		dash_held = _dash_frames > 0
		if _dash_frames <= 0:
			_mode = Mode.IDLE
			command_finished.emit()
		return

	if absf(dx) > DASH_RANGE:
		move_x = direction
		return

	_dashed = true
	_dash_frames = DASH_HOLD_FRAMES
	move_x = direction
	dash_held = true
