extends Node
class_name BombController

signal player_finished_round
signal minigame_spawned(instance: Control, slot_index: int)

@export var bomb_time: float = 40.0
@export var device_id: int = 0  
@export var respawn_delay: float = 2.0  
@export var bonus_sounds: Array[AudioStream] = [] 
@export var bonus_pitch_variance: float = 0.15  
@export var max_lives: int = 5  
@export var respawn_invulnerability_duration: float = 1.5 
var _lives_remaining: int = 5 
@export var input_sound: AudioStream
@export var penalty_sound: AudioStream  
@export var minigame_complete_sound: AudioStream

@export var max_bomb_time: float = 60.0

@export var lethal: bool = true
const NONLETHAL_FLOOR: float = 0.4

@export_group("Tick")
@export var tick_sound: AudioStream
@export var panic_time: float = 5.0
@export var tick_interval_calm: float = 1.0
@export var tick_interval_panic: float = 0.12
@export var tick_volume_calm: float = -26.0
@export var tick_volume_panic: float = -5.0
@export var tick_pitch_calm: float = 1.0
@export var tick_pitch_panic: float = 1.0

var _time_left: float
var _active_minigame: Control = null
var _active_minigame_slot: Control = null
var _active_slot_index: int = -1
var _player: Node
var _expired := false

var _start_time_ms: int = 0
var _adjust_total: float = 0.0
var _running: bool = false
var _frozen_value: float = 0.0
## Soft pause. Offline _running is never true (start_at is only wired when
## networked), so it cannot serve as the freeze flag - this one can.
var _timer_frozen: bool = false

const STICK_THRESHOLD: float = 0.5  

var _prev_stick_direction: String = ""
var _slot_index: int = -1
var _slot_cache_population: int = -1
var _tick_timer: float = 0.0
var _tick_fallback: AudioStream

var time_left: float:
	get:
		return _compute_time_left()

@onready var _minigame_layer: Control = $Minigamelayer

func _ready() -> void:
	_player = get_parent()
	_time_left = bomb_time
	_frozen_value = bomb_time
	_lives_remaining = max_lives
	if _is_networked():
		Networking.bombs_start.connect(start_at)
	if tick_sound == null:
		_tick_fallback = load("res://resources/audio/Clock Tick OR Press .wav")
	MinigameDirector.register_player(self)


func start_at(start_time_ms: int) -> void:
	_start_time_ms = start_time_ms
	_adjust_total = 0.0
	_expired = false
	_running = true
	_timer_frozen = false
	_frozen_value = bomb_time
	set_process(true)


func _compute_time_left() -> float:
	if not _is_networked():
		return _time_left
	if not _running:
		return _frozen_value
	var elapsed: float = float(Networking.get_sync_time() - _start_time_ms) / 1000.0
	if elapsed < 0.0:
		elapsed = 0.0
	return clampf(bomb_time + _adjust_total - elapsed, 0.0, max_bomb_time)


func clamp_time_delta(seconds: float) -> float:
	var current: float = _compute_time_left()
	var target: float = minf(current + seconds, max_bomb_time)
	return target - current


func commit_time_delta(seconds: float) -> void:
	if _is_networked():
		_adjust_total += seconds
	else:
		_time_left = minf(_time_left + seconds, max_bomb_time)

func _exit_tree() -> void:
	MinigameDirector.unregister_player(self)

func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _has_authority() -> bool:
	return not _is_networked() or _player.is_multiplayer_authority()

func _process(delta: float) -> void:
	if _is_networked():
		if multiplayer.is_server() and _running and not _expired and _compute_time_left() <= 0.0:
			_running = false
			_frozen_value = 0.0
			_explode.rpc()
	elif not _expired and not _timer_frozen:
		_time_left -= delta
		if _time_left <= 0.0:
			if lethal:
				player_died("explode")
			else:
				_time_left = NONLETHAL_FLOOR
	if _minigame_layer:
		_minigame_layer.global_position = _player.global_position + Vector2(-100, -150)
	if not _timer_frozen:
		_update_tick(delta)
	_poll_right_stick()

func _update_tick(delta: float) -> void:
	if _expired or _timer_frozen:
		return
	if _is_networked() and not _running:
		return
	var left: float = _compute_time_left()
	if left <= 0.0:
		return
	# Count down first and bail early: the urgency/ramp math and the stream lookup
	# below only matter on the frame a tick actually fires.
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	var sfx: AudioStream = tick_sound if tick_sound else _tick_fallback
	if sfx == null:
		return
	var urgency: float = 1.0 - clampf(left / maxf(panic_time, 0.01), 0.0, 1.0)
	var ramp: float = sqrt(urgency)
	_tick_timer = lerpf(tick_interval_calm, tick_interval_panic, ramp)
	SfxManager.play(
		sfx,
		lerpf(tick_volume_calm, tick_volume_panic, ramp),
		0.0,
		lerpf(tick_pitch_calm, tick_pitch_panic, ramp),
	)


func bot_submit() -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:
		return
	if MinigameDirector.is_input_locked() or MinigameDirector.is_match_finished():
		return
	if not _active_minigame.has_method("bot_action"):
		return
	var action: StringName = _active_minigame.bot_action()
	if action == &"":
		return
	var key: Key = Settings.get_key(action)
	if key == KEY_NONE:
		return
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key
	if _active_minigame._handle_input(event):
		_play_input_sound_net()


func _input(event: InputEvent) -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:
		return
	# A bot's minigame is driven solely by bot_submit(); no real device input may
	# reach it. Offline _has_authority() is true for every controller, and the
	# singleplayer branches below deliberately ignore device_id, so without this
	# a bot's controller would answer the human's presses as its own.
	if _player.bot != null:
		return
	if MinigameDirector.is_input_locked():
		return
	# LocalPlayers.singleplayer covers both singleplayer and tutorial: the one
	# real player there isn't locked to a specific device the way couch play's
	# device_id assignment locks each player, so it accepts a joypad button or a
	# keyboard key the same way online play does, regardless of which device_id
	# LocalPlayers.try_join happened to hand out for roster bookkeeping.
	if event is InputEventJoypadButton and (_is_networked() or LocalPlayers.singleplayer or event.device == device_id):
		var handled: bool = _active_minigame._handle_input(event)
		if handled:
			get_viewport().set_input_as_handled()
			_play_input_sound_net()
		_try_replicate_input(false, event.button_index)
	elif event is InputEventKey and (_is_networked() or LocalPlayers.singleplayer or _player.device_id == LocalPlayers.KEYBOARD_DEVICE_ID):
		var handled: bool = _active_minigame._handle_input(event)
		if event.pressed and not event.echo:
			if handled:
				get_viewport().set_input_as_handled()
				_play_input_sound_net()
			# Peers do not share bindings, so send the key this action *ships*
			# with and let the far side translate it back into its own.
			var raw_key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			var action := Settings.action_for_key(raw_key)
			var key: int = Settings.default_key(action) if action != &"" else raw_key
			_try_replicate_input(true, key)


func _poll_right_stick() -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:
		return
	# A bot's minigame is driven solely by bot_submit(); no real device input may
	# reach it. Offline _has_authority() is true for every controller, and the
	# singleplayer branches below deliberately ignore device_id, so without this
	# a bot's controller would answer the human's presses as its own.
	if _player.bot != null:
		return
	if MinigameDirector.is_input_locked():
		return
	
	var poll_device: int = device_id
	if _is_networked() or LocalPlayers.singleplayer:
		# CHANGED: was Input.get_connected_joypads()[0] - see PadState.active_device
		# for why that never adapted to switching controllers mid-session.
		poll_device = PadState.active_device()
		if poll_device < 0:
			_prev_stick_direction = ""
			return
	elif device_id < 0:
		_prev_stick_direction = ""
		return
	
	var stick_x: float = PadState.get_axis(poll_device, JOY_AXIS_RIGHT_X)
	var stick_y: float = PadState.get_axis(poll_device, JOY_AXIS_RIGHT_Y)
	
	var current_direction: String = ""
	if abs(stick_x) > abs(stick_y):
		if stick_x > STICK_THRESHOLD:
			current_direction = "right"
		elif stick_x < -STICK_THRESHOLD:
			current_direction = "left"
	else:
		if stick_y > STICK_THRESHOLD:
			current_direction = "down"
		elif stick_y < -STICK_THRESHOLD:
			current_direction = "up"
	
	if current_direction != "" and current_direction != _prev_stick_direction:
		_submit_stick_direction(current_direction, poll_device)
	
	if current_direction == "":
		_prev_stick_direction = ""
	else:
		_prev_stick_direction = current_direction


func _submit_stick_direction(direction: String, source_device: int) -> void:
	var button: JoyButton
	match direction:
		"up": button = JOY_BUTTON_DPAD_UP
		"down": button = JOY_BUTTON_DPAD_DOWN
		"left": button = JOY_BUTTON_DPAD_LEFT
		"right": button = JOY_BUTTON_DPAD_RIGHT
		_: return
	
	var synthetic_event := InputEventJoypadButton.new()
	synthetic_event.device = source_device
	synthetic_event.button_index = button
	synthetic_event.pressed = true
	
	var handled: bool = _active_minigame._handle_input(synthetic_event)
	if handled:
		_play_input_sound_net()
	_try_replicate_input(false, button)


## Minigame input feedback (the little "beep" on every accepted press) used to be
## a bare local SfxManager.play, reached only through the _has_authority() gate
## above -- meaning only the player actually providing input ever heard it.
## Routed any_peer/call_local like apply_stun/apply_hitstop, unreliable since a
## missed input blip on one peer is a non-issue.
func _play_input_sound_net() -> void:
	if _is_networked():
		_play_input_sound.rpc()
	else:
		_play_input_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_input_sound() -> void:
	SfxManager.play(input_sound, -13.0, 0.1)


@rpc("any_peer", "call_local", "reliable")
func _explode() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_running = false
	_frozen_value = 0.0
	_do_player_died("explode")  


func detach_from_match() -> void:
	_running = false
	_frozen_value = _compute_time_left()
	if _is_networked() and Networking.bombs_start.is_connected(start_at):
		Networking.bombs_start.disconnect(start_at)


func reset_for_respawn() -> void:
	_expired = false
	_running = false
	_timer_frozen = false
	_adjust_total = 0.0
	_time_left = bomb_time
	_frozen_value = bomb_time
	set_process(true)

func set_lives(count: int) -> void:
	_lives_remaining = maxi(count, 0)


func stop_timer() -> void:
	_frozen_value = _compute_time_left()
	_running = false
	# Deliberately keeps _process alive: the world is no longer paused around us,
	# so the minigame layer still has to follow the player.
	_timer_frozen = true


func resume_timer() -> void:
	if _expired:
		return
	_timer_frozen = false



const PLAYER_COLORS: Array[Color] = [
	Color(1, 0.4118, 0.3529, 1),
	Color(1, 0.8784, 0.5686, 1),
	Color(0.3137, 0.7255, 0.9216, 1),
	Color(0.549, 1, 0.6078, 1),
]

# The slot is derived from the sorted peer/player ids, which only change when a
# player joins or leaves. Recomputing it scanned and sorted the whole "players"
# group, and it was called ~3x per player per frame (match_hud, player identity),
# so the result is cached and only rebuilt when the group size changes.
func get_slot_index() -> int:
	var count: int = get_tree().get_node_count_in_group("players")
	if _slot_index >= 0 and count == _slot_cache_population:
		return _slot_index
	var ids: Array[int] = []
	for node in get_tree().get_nodes_in_group("players"):
		ids.append(node.name.to_int())
	ids.sort()
	_slot_index = clampi(ids.find(_player.name.to_int()), 0, 3)
	_slot_cache_population = count
	return _slot_index

func get_player_color() -> Color:
	return PLAYER_COLORS[get_slot_index()]


## The color stays keyed to slot no matter what -- this only decides the text.
## Online: server-synced Steam persona name (Networking.get_player_name), falling
## back to P<slot> if it hasn't arrived yet. Couch: whatever was typed into that
## device's lobby slot (LocalPlayers.get_display_name), falling back the same way.
func get_player_display_name() -> String:
	var slot := get_slot_index()
	if _is_networked():
		return Networking.get_player_name(_player.name.to_int(), slot)
	return LocalPlayers.get_display_name(device_id, slot)


func play_minigame(scene: PackedScene, slot_index: int) -> void:
	if _expired or not _has_authority():
		return
	var scene_index: int = MinigameDirector.minigame_order.find(scene)
	if scene_index < 0:
		return
	var rng_seed: int = randi()
	if rng_seed == 0:
		rng_seed = 1
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_show_minigame(slot_index, scene_index, rng_seed)
	else:
		_show_minigame.rpc(slot_index, scene_index, rng_seed)

func has_active_minigame() -> bool:
	return _active_minigame != null


func stop_minigame() -> void:
	if _has_authority() and _is_networked():
		_clear_minigame.rpc()
	else:
		_clear_minigame()


func finish_minigame() -> void:
	if _has_authority() and _is_networked():
		_power_off_minigame.rpc()
	else:
		_power_off_minigame()

@rpc("any_peer", "call_local", "reliable")
func _show_minigame(slot_index: int, scene_index: int, rng_seed: int = 0) -> void:
	_clear_minigame()
	if _expired or scene_index < 0 or scene_index >= MinigameDirector.minigame_order.size():
		return
	var slot := get_tree().current_scene.get_node_or_null("MinigameLayout/Layout/Slot%d" % slot_index)
	if slot == null:
		return
	var scene: PackedScene = MinigameDirector.minigame_order[scene_index]
	_active_minigame = scene.instantiate()
	minigame_spawned.emit(_active_minigame, slot_index)
	_active_minigame_slot = slot
	_active_slot_index = slot_index
	slot.add_child(_active_minigame)
	var screens := _minigame_screens()
	if screens:
		screens.fit_content(slot_index, _active_minigame)
		screens.power_on(slot_index)
	else:
		_active_minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.visible = true
	_active_minigame.setup(_player, rng_seed)
	if _has_authority():
		_active_minigame.bomb_time_delta.connect(_on_bomb_time_delta)
		_active_minigame.round_finished.connect(_on_minigame_finished)

func _try_replicate_input(is_key: bool, code: int) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_replicate_minigame_input.rpc(is_key, code)

@rpc("any_peer", "reliable")
func _replicate_minigame_input(is_key: bool, code: int) -> void:
	if multiplayer.get_remote_sender_id() != _player.name.to_int():
		return
	if _active_minigame == null or _has_authority() or _player.is_stunned:
		return
	if is_key:
		var key_event := InputEventKey.new()
		key_event.pressed = true
		# The sender normalized to the canonical key; map it onto ours. Set the
		# physical code, which is what the minigames and player.gd look at.
		var action := Settings.action_for_default_key(code)
		key_event.physical_keycode = Settings.get_key(action) if action != &"" else code as Key
		_active_minigame._handle_input(key_event)
	else:
		var pad_event := InputEventJoypadButton.new()
		pad_event.pressed = true
		pad_event.button_index = code as JoyButton
		_active_minigame._handle_input(pad_event)

func _minigame_screens() -> Node:
	return get_tree().get_first_node_in_group("minigame_screens")


@rpc("any_peer", "call_local", "reliable")
func _clear_minigame() -> void:
	var screens := _minigame_screens()
	if screens and _active_slot_index >= 0:
		screens.snap_off(_active_slot_index)
	if _active_minigame:
		_active_minigame.queue_free()
		_active_minigame = null
	if _active_minigame_slot:
		_active_minigame_slot.visible = false
		_active_minigame_slot = null
	_active_slot_index = -1


@rpc("any_peer", "call_local", "reliable")
func _power_off_minigame() -> void:
	var dying := _active_minigame
	var slot_index := _active_slot_index
	_active_minigame = null
	_active_minigame_slot = null
	_active_slot_index = -1
	var screens := _minigame_screens()
	if screens and slot_index >= 0:
		await screens.power_off(slot_index)
	if is_instance_valid(dying):
		dying.queue_free()


func _on_minigame_finished() -> void:
	if _active_minigame == null:
		return
	_play_minigame_complete_sound_net()
	finish_minigame()
	player_finished_round.emit()


## _on_minigame_finished and _on_bomb_time_delta are only ever connected for the
## authority peer (see _show_minigame), so these were bare local calls nobody else
## ever heard. Routed the same any_peer/call_local/unreliable way as the input
## sound above -- state-changing parts of _on_bomb_time_delta below (commit_time_delta
## / Networking.apply_time_delta / report_time_delta) are untouched, only the sound.
func _play_minigame_complete_sound_net() -> void:
	if _is_networked():
		_play_minigame_complete_sound.rpc()
	else:
		_play_minigame_complete_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_minigame_complete_sound() -> void:
	SfxManager.play(minigame_complete_sound, -10.0, 0.2)


func _play_penalty_sound_net() -> void:
	if _is_networked():
		_play_penalty_sound.rpc()
	else:
		_play_penalty_sound()


@rpc("any_peer", "call_local", "unreliable")
func _play_penalty_sound() -> void:
	SfxManager.play(penalty_sound, -15.0, 0.2)


func _on_bomb_time_delta(seconds: float) -> void:
	if seconds > 0.0:
		_play_bonus_sound()
	elif seconds < 0.0:
		_play_penalty_sound_net()
	if not _is_networked():
		commit_time_delta(seconds)
	elif multiplayer.is_server():
		Networking.apply_time_delta(_player.name.to_int(), seconds)
	else:
		Networking.report_time_delta(_player.name.to_int(), seconds)

func _play_bonus_sound() -> void:
	if bonus_sounds.is_empty():
		return
	if _is_networked():
		_do_play_bonus_sound.rpc()
	else:
		_do_play_bonus_sound()


## Which specific bonus_sounds entry plays is cosmetic variety, not something that
## needs to match across peers -- each peer rolls its own pick locally, same as
## _play_footstep_sound's pitch jitter does.
@rpc("any_peer", "call_local", "unreliable")
func _do_play_bonus_sound() -> void:
	var sound: AudioStream = bonus_sounds[randi() % bonus_sounds.size()]
	SfxManager.play(sound, -10.0, bonus_pitch_variance)


func player_died(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	if not _is_networked():
		_do_player_died(cause)
	else:
		_do_player_died.rpc(cause)

@rpc("any_peer", "call_local", "reliable")
func _do_player_died(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	_report_kill(cause)
	# Opens the dead window here rather than in each branch below, so the death
	# animation is excluded from time-alive whether this life was the last one.
	MinigameDirector.record_death_start(_player.name.to_int() if _player else -1)
	_lives_remaining -= 1
	if _lives_remaining <= 0:
		eliminate_player(cause)  # CHANGED: pass cause through
	else:
		_respawn(cause)  # CHANGED: pass cause through

## Kill feed and match stats are both purely reactive to this one already-networked
## event - _do_player_died is already the any_peer/call_local/reliable broadcast
## that runs identically on every peer, so both the HUD's kill feed and
## MinigameDirector's per-player survival/kill tracking stay in sync for free off
## this single call, with no stats-specific RPC of their own.
func _report_kill(cause: String) -> void:
	var credit: Dictionary = {}
	if _player and _player.has_method("get_kill_credit"):
		credit = _player.get_kill_credit()
	var hud := get_tree().current_scene.get_node_or_null("MatchHUD")
	if hud and hud.has_method("report_kill"):
		hud.report_kill(get_player_display_name(), get_player_color(), cause, credit)
	var victim_key: int = _player.name.to_int() if _player else -1
	MinigameDirector.record_match_stats(victim_key, int(credit.get("key", -1)))

func eliminate_player(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	_expired = true
	_running = false
	_frozen_value = 0.0
	set_process(false)
	stop_minigame()
	# Stamped before the death animation is awaited: eliminate_player only runs
	# once a player is out of lives, so this is match-start to full elimination
	# rather than to whichever life they happened to lose first - but the seconds
	# spent playing out the death are not time alive, so they must not land
	# inside the stamp.
	MinigameDirector.record_elimination(_player.name.to_int())
	await _player.play_death_animation(cause)  # CHANGED: pass cause through
	MinigameDirector.player_eliminated(_player.name.to_int())
	# The node can be freed mid-await (round end, arena unload, peer disconnect) -
	# same situation player.gd's own play_death_animation already guards against
	# for itself - at which point _has_authority()'s multiplayer.multiplayer_peer
	# read below errors on a null multiplayer instead of just being false.
	if not is_inside_tree():
		return
	if _has_authority() and _player.bot == null:
		var scene := get_tree().current_scene
		if scene.has_method("show_lose_popup"):
			scene.show_lose_popup()

func _respawn(cause: String = "fall") -> void:  # CHANGED: added cause param
	set_process(false)
	_player.play_death_animation(cause)  # CHANGED: pass cause through
	stop_minigame()
	MinigameDirector.schedule_next_round(self)
	await get_tree().create_timer(respawn_delay).timeout
	if _expired:
		return
	# Same node-freed-mid-await risk as eliminate_player() above (round end,
	# arena unload, peer disconnect) - get_tree()/_is_networked() below would
	# error on a detached node instead of just resolving false/null.
	if not is_inside_tree():
		return
	if _is_networked():
		_start_time_ms = Networking.get_sync_time()
		_adjust_total = 0.0
		_running = true
		_frozen_value = bomb_time
	else:
		_time_left = bomb_time
	set_process(true)
	var scene := get_tree().current_scene
	if scene.has_method("respawn_player"):
		scene.respawn_player(_player)
	MinigameDirector.record_respawn(_player.name.to_int())
	_player.respawn(respawn_invulnerability_duration)
	


func get_lives_remaining() -> int:  
	return _lives_remaining
