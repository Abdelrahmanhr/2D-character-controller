extends Node2D
class_name LightningEmitter


const BOLT := preload("res://scenes/lightning_bolt.tscn")

@export var interval_min: float = 0.06
@export var interval_max: float = 0.18
@export var bolt_sound: AudioStream
@export var sound_volume_db: float = -18.0
@export var sound_chance: float = 0.04

@export_group("Towers")
@export var tower_base_y: float = 736.0

@export_group("Rail")
@export var rail_mode: bool = false
@export var rail_x_min: float = 40.0
@export var rail_x_max: float = 1700.0
@export var rail_post_count: int = 6
@export var rail_density: float = 0.85

var _anchors: PackedVector2Array = PackedVector2Array()
var _timer: Timer

# Bolts are spawned ~20 times a second for the whole match. Recycling them avoids
# that many instantiate/queue_free cycles (and the node churn behind them).
var _pool: Array[LightningBolt] = []


func _ready() -> void:
	add_to_group("lightning_emitters")
	_collect_anchors()
	if _anchors.is_empty():
		push_warning("LightningEmitter '%s' found no anchors — disabled." % name)
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_fire)
	add_child(_timer)
	_restart_timer()


func _collect_anchors() -> void:
	_anchors.clear()
	if rail_mode:
		var steps: int = maxi(rail_post_count - 1, 1)
		var span: float = rail_x_max - rail_x_min
		for i in rail_post_count:
			_anchors.append(Vector2(rail_x_min + span * (float(i) / float(steps)), 0.0))
		return
	for child in get_children():
		if child is Marker2D:
			_anchors.append(child.position)


func _restart_timer() -> void:
	_timer.start(randf_range(interval_min, interval_max))


func _fire() -> void:
	if rail_mode:
		for i in _anchors.size() - 1:
			if randf() <= rail_density:
				_spawn(_anchors[i], _anchors[i + 1])
	else:
		var top: Vector2 = _anchors[randi() % _anchors.size()]
		_spawn(top, Vector2(top.x, tower_base_y))
	if bolt_sound and randf() <= sound_chance:
		SfxManager.play(bolt_sound, sound_volume_db, 0.15)
	_restart_timer()


func strike_global(from_global: Vector2, to_global: Vector2) -> void:
	_spawn(to_local(from_global), to_local(to_global))


func _spawn(from: Vector2, to: Vector2) -> void:
	var bolt: LightningBolt = _acquire()
	var from_to: Vector2 = to - from
	if rail_mode:
		var seg: float = from_to.length()
		bolt.divider = maxf(seg / 8.0, 4.0)
		bolt.sway_divider = maxf(seg / 12.0, 2.0)
	bolt.set_start(from)
	bolt.set_end(to)
	bolt.segmentize(from_to, from)
	bolt.sway(Vector2(from_to.y, -from_to.x).normalized())
	bolt.visible = true
	bolt.play_fade()


func _acquire() -> LightningBolt:
	while not _pool.is_empty():
		var reused: LightningBolt = _pool.pop_back()
		if is_instance_valid(reused):
			reused.reset()
			return reused
	var bolt := BOLT.instantiate() as LightningBolt
	add_child(bolt)
	bolt.fade_finished.connect(_on_bolt_finished)
	bolt.reset()
	return bolt


func _on_bolt_finished(bolt: LightningBolt) -> void:
	bolt.visible = false
	bolt.reset()
	_pool.append(bolt)
