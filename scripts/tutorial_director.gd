extends Node
class_name TutorialDirector

const MG_MATH := 0
const MG_INPUT_SEQUENCE := 1
const MG_MASH := 2
const MG_COLOR_MATCH := 3

const DRAMATIC_BOMB_TIME: float = 12.0

const MOVE_TRAVEL_TO_PASS: float = 60.0
const MOVE_STEP_GUARD: float = 40.0
const ZONE_DWELL_TO_PASS: float = 2.0
const PUPPET_DASH_RETRY: float = 2.5
const PUPPET_STAGE_DISTANCE: float = 130.0

var _arena: Node2D
var _overlay: TutorialOverlay
var _player: CharacterBody2D
var _bomb: BombController
var _puppets: Array[CharacterBody2D] = []

var _frozen: bool = false
var _skipped: bool = false
var _finished: bool = false
var _held_bombs: Array[BombController] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_arena = get_parent() as Node2D
	_overlay = TutorialOverlay.new()
	_overlay.name = "TutorialOverlay"
	_arena.add_child(_overlay)
	_overlay.skip_requested.connect(_on_skip_requested)
	_overlay.practice_requested.connect(_on_practice_requested)
	_overlay.replay_requested.connect(_on_replay_requested)
	_overlay.quit_requested.connect(_on_quit_requested)
	_run()


func _freeze() -> void:
	if _frozen:
		return
	_frozen = true
	MinigameDirector.lock_input(MinigameDirector.LOCK_TUTORIAL)
	_hold_bomb(_bomb, true)


func _unfreeze() -> void:
	if not _frozen:
		return
	_frozen = false
	MinigameDirector.unlock_input(MinigameDirector.LOCK_TUTORIAL)
	_hold_bomb(_bomb, false)


func _hold_bomb(bomb: BombController, held: bool) -> void:
	if bomb == null:
		return
	if held:
		if not _held_bombs.has(bomb):
			_held_bombs.append(bomb)
		bomb.stop_timer()
	else:
		_held_bombs.erase(bomb)
		bomb.resume_timer()


func _process(_delta: float) -> void:
	for bomb in _held_bombs:
		if is_instance_valid(bomb):
			bomb.stop_timer()

	if not _finished and _bomb != null and is_instance_valid(_bomb):
		_bomb.set_lives(_bomb.max_lives)


func _card(title: String, body: String, targets: Array = [], caps: Array = []) -> void:
	if _skipped:
		return
	_freeze()
	_overlay.set_spotlight(targets)
	_overlay.set_objectives([])
	_overlay.show_card(title, body, caps, _overlay.continue_hint_text())
	await _overlay.await_continue()
	_overlay.hide_card()


func _task(body: String, predicate: Callable, caps: Array = [], objectives: Array = []) -> void:
	if _skipped:
		return
	_unfreeze()
	_overlay.clear_spotlight()
	_overlay.set_objectives(objectives)
	_overlay.show_card("", body, caps, "")
	await _until(predicate)
	_overlay.set_objectives([])
	_overlay.hide_card()


## is_inside_tree() guards both loops the same way tutorial_overlay.gd's own
## post-await checks already do: the pause menu's Restart button reloads the
## scene directly (Networking.restart_game -> get_tree().reload_current_scene),
## with no signal to this director first, unlike _on_skip_requested's _skipped
## flag. That tears this node out of the tree mid-await, and the next loop
## iteration's get_tree() call - still reachable for a beat, briefly detached -
## returned null instead of the SceneTree, which is what crashed here.
func _until(predicate: Callable) -> void:
	while not _skipped and is_inside_tree():
		if bool(predicate.call()):
			return
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0 and not _skipped and is_inside_tree():
		await get_tree().process_frame
		left -= get_process_delta_time()


func _teach_minigame(index: int, target: int, title: String, body: String, caps: Array) -> void:
	if _skipped:
		return
	_freeze()
	var instance: Control = MinigameDirector.minigame_order[index].instantiate()
	_tune_minigame(instance, target)
	_overlay.host_minigame(instance)
	_relabel_mash(instance)
	instance.setup(_player, randi())
	instance.bomb_time_delta.connect(_on_taught_time_delta)

	var done: Array[bool] = [false]
	instance.round_finished.connect(func() -> void: done[0] = true)

	_overlay.set_spotlight([])
	_overlay.show_card(title, body, caps, "")
	_overlay.pump_minigame(instance)
	await _until(func() -> bool: return done[0])
	_overlay.release_minigame()
	_overlay.hide_card()
	instance.queue_free()


func _practice_minigame(index: int, target: int, body: String, caps: Array) -> void:
	if _skipped:
		return
	_unfreeze()

	var done: Array[bool] = [false]
	var tune := func(instance: Control, _slot: int) -> void:
		_tune_minigame(instance, target)
		_relabel_mash(instance)
		instance.round_finished.connect(func() -> void: done[0] = true)
	var serve := func() -> void:
		_bomb.minigame_spawned.connect(tune, CONNECT_ONE_SHOT)
		_bomb.play_minigame(MinigameDirector.minigame_order[index], _bomb.get_slot_index())
	serve.call()

	var slot := _arena.get_node_or_null("MinigameLayout/Layout/Slot%d" % _bomb.get_slot_index()) as Control
	_overlay.set_spotlight([{"control": slot, "pad": 16.0}] if slot else [])
	_overlay.show_card("", body, caps, "")
	await _until(func() -> bool:
		if done[0]:
			return true
		if not _player.is_dead and not _bomb.has_active_minigame():
			serve.call()
		return false)
	_overlay.clear_spotlight()
	_overlay.hide_card()
	_bomb.stop_minigame()


func _tune_minigame(instance: Control, target: int) -> void:
	if instance is MashMinigame:
		instance.max_presses = target
	elif "target_correct" in instance:
		instance.target_correct = target


func _relabel_mash(instance: Control) -> void:
	if not (instance is MashMinigame):
		return
	var label := instance.get_node_or_null("MashLabel") as Label
	if label:
		label.text = "MASH %s" % TutorialKeycap.key_text(&"mash")


func _on_taught_time_delta(seconds: float) -> void:
	if _bomb == null:
		return
	_bomb.commit_time_delta(_bomb.clamp_time_delta(seconds))
	if seconds > 0.0 and not _bomb.bonus_sounds.is_empty():
		SfxManager.play(_bomb.bonus_sounds.pick_random(), 0.0, _bomb.bonus_pitch_variance)
	elif seconds < 0.0 and _bomb.penalty_sound:
		SfxManager.play(_bomb.penalty_sound)


func _run() -> void:
	await _bind_players()
	if _skipped:
		return
	_freeze()
	if not MinigameDirector.is_match_finished():
		await MinigameDirector.match_started
	await _wait(0.8)

	await _beat_move()
	await _beat_bomb()
	await _beat_minigames()
	await _beat_dash()
	await _beat_hazards()
	await _beat_shield()
	await _beat_last_standing()


func _bind_players() -> void:
	await _until(func() -> bool: return _arena.players.size() >= 1)
	_player = _arena.players[0]
	_bomb = _player.get_node("BombController") as BombController
	for i in range(1, _arena.players.size()):
		var puppet: CharacterBody2D = _arena.players[i]
		_puppets.append(puppet)
		_park(puppet)


func _park(puppet: CharacterBody2D) -> void:
	puppet.visible = false
	puppet.set_physics_process(false)
	var bomb := puppet.get_node("BombController") as BombController
	_hold_bomb(bomb, true)


func _reveal(puppet: CharacterBody2D, distance: float) -> void:
	_stage(puppet, distance)
	puppet.visible = true
	puppet.set_physics_process(true)
	if puppet.bot is TutorialPuppet:
		puppet.bot.solving = false
		puppet.bot.stand_still()


func _stage(puppet: CharacterBody2D, distance: float) -> void:
	puppet.global_position = _arena.ground_spot_beside(_player.global_position, distance)
	puppet.velocity = Vector2.ZERO


func _beat_move() -> void:
	await _card(
		"MOVE",
		"Get your footing first.",
		[{"node": _player, "radius": 110.0}],
		[["move_left", "left"], ["move_right", "right"], ["jump", "jump"]],
	)

	var moved: Array[bool] = [false, false, false]
	var travelled: Array[float] = [0.0, 0.0]
	var last_x: Array[float] = [_player.global_position.x]
	await _task(
		"Move, and jump once.",
		func() -> bool:
			var step: float = _player.global_position.x - last_x[0]
			last_x[0] = _player.global_position.x
			if _player.is_dead or absf(step) > MOVE_STEP_GUARD:
				step = 0.0
			if step < 0.0:
				travelled[0] -= step
			elif step > 0.0:
				travelled[1] += step
			if travelled[0] >= MOVE_TRAVEL_TO_PASS and not moved[0]:
				moved[0] = true
				_overlay.mark_objective(0, true)
			if travelled[1] >= MOVE_TRAVEL_TO_PASS and not moved[1]:
				moved[1] = true
				_overlay.mark_objective(1, true)
			if not _player.is_on_floor() and _player.velocity.y < -10.0 and not moved[2]:
				moved[2] = true
				_overlay.mark_objective(2, true)
			return moved[0] and moved[1] and moved[2],
		[["move_left", "left"], ["move_right", "right"], ["jump", "jump"]],
		["move left", "move right", "jump"],
	)


func _beat_bomb() -> void:
	await _card(
		"THE BOMB",
		"There is a bomb strapped to you. At zero it goes off and costs you a life.",
		[{"node": _player, "radius": 100.0}],
	)
	await _card(
		"YOUR TIMER",
		"This is how long you have left. It is already counting down.",
		[{"control": _hud_slot(), "pad": 14.0}],
	)

	_bomb.commit_time_delta(-(_bomb.time_left - DRAMATIC_BOMB_TIME))
	_unfreeze()
	_overlay.set_spotlight([{"control": _hud_slot(), "pad": 14.0}])
	_overlay.show_card("", "Watch it drain.", [], "")
	await _wait(3.5)
	_overlay.clear_spotlight()
	_overlay.hide_card()


func _beat_minigames() -> void:
	await _card(
		"MINIGAMES",
		"Minigames are the only way to buy time back. Solve one and your timer goes up.",
		[{"control": _slot_control(), "pad": 16.0}],
	)

	await _teach_minigame(
		MG_MATH, 3,
		"MATH",
		"Pick the correct answer.",
		[["mg_left", "left arrow key"], ["mg_right", "right arrow key"]],
	)
	await _practice_minigame(
		MG_MATH, 2,
		"Same game, real size. That is where it appears in a match.",
		[["mg_left", "left arrow key"], ["mg_right", "right arrow key"]],
	)

	await _teach_minigame(
		MG_MASH, 15,
		"MASH",
		"Some of them just want speed. Hammer the key.",
		[["mash", "mash"]],
	)
	await _practice_minigame(
		MG_MASH, 10,
		"Ten presses buys you time. Go.",
		[["mash", "mash"]],
	)


func _beat_dash() -> void:
	if _puppets.is_empty():
		return
	var target: CharacterBody2D = _puppets[0]
	_reveal(target, 220.0)

	await _card(
		"SABOTAGE",
		"Everyone else has a bomb too. Dash into a player to stun them and knock them away - away from safety, or off the edge entirely.",
		[{"node": target, "radius": 110.0}],
		[["dash", "dash"], ["dash_alt", "or"]],
	)
	await _task(
		"Dash into them.",
		func() -> bool: return target.is_stunned,
		[["dash", "dash"], ["dash_alt", "or"]],
	)
	await _card(
		"STUNNED",
		"A stunned player cannot move and cannot answer their screen. Their timer keeps falling.",
		[{"node": target, "radius": 110.0}],
	)


func _beat_hazards() -> void:
	await _beat_lightning()
	await _beat_safe_zone()


func _beat_lightning() -> void:
	if _skipped:
		return
	_unfreeze()
	var index: int = _arena.pick_lightning_platform_away_from(_player.global_position)
	if index < 0:
		return
	_arena.fire_lightning(index)
	await _wait(0.2)
	await _card(
		"LIGHTNING",
		"When you see the warning, that platform is about to be struck. Get off it.",
		[{"node": _arena_marker(index), "radius": 120.0}],
	)
	_unfreeze()
	_overlay.show_card("", "Stay clear.", [], "")
	await _wait(_arena.lightning_warning_lead_time + 1.2)
	_overlay.hide_card()


## Only counts as passed once the storm itself has fully closed and faded out
## (the zone's own natural end of life, not just a couple seconds of standing
## inside partway through) with the player still alive at that moment. Dying to
## it mid-shrink dismisses the failed zone and repeats the whole beat - a fresh
## card and a fresh full-duration zone - rather than moving on regardless.
func _beat_safe_zone() -> void:
	if _skipped:
		return
	_unfreeze()
	while true:
		var index: int = _arena.nearest_spawn_index(_player.global_position)
		_arena.start_safe_zone(index)
		await _until(func() -> bool: return _arena.get_active_safe_zone() != null)
		if _skipped:
			return
		var zone: SafeZone = _arena.get_active_safe_zone()

		await _card(
			"THE SAFE ZONE",
			"Sometimes only one patch of the arena is safe. Outside it you move like you are wading, and the ring over your head fills up. When it fills, you die.",
			[{"node": zone, "radius": zone.get_radius()}],
		)
		if _skipped:
			return

		var died: Array[bool] = [false]
		await _task(
			"Get inside the circle and stay there until the storm fully closes.",
			func() -> bool:
				if _player.is_dead:
					died[0] = true
					return true
				return not is_instance_valid(zone),
		)
		if _skipped:
			return
		if not died[0]:
			return
		_arena.dismiss_safe_zone()
		await _until(func() -> bool: return not _player.is_dead)


func _beat_shield() -> void:
	if _skipped or _puppets.is_empty():
		return
	_unfreeze()
	var attacker: CharacterBody2D = _puppets[0]
	_arena.spawn_shield_at(_arena.shield_position_near(_player.global_position))
	await _until(func() -> bool: return _arena.get_node_or_null("ShieldPickup") != null)
	var pickup: Node2D = _arena.get_node("ShieldPickup")

	await _card(
		"THE SHIELD",
		"That is a SHIELD.",
		[{"node": pickup, "radius": 90.0}],
	)
	await _task(
		"Pick it up.",
		func() -> bool: return _player.is_shielded,
	)

	_player.apply_shield(30.0)
	_freeze()
	_reveal(attacker, PUPPET_STAGE_DISTANCE)
	await _card(
		"BACKFIRE",
		"While the shield is up nothing can stun you - and anyone who dashes into you is thrown back hard enough to kill them.",
		[{"node": _player, "radius": 110.0}],
	)

	_unfreeze()
	if attacker.bot is TutorialPuppet:
		attacker.bot.dash_at(_player)
	_overlay.show_card("", "Let them try it.", [], "")
	var elapsed: Array[float] = [0.0]
	await _until(func() -> bool:
		elapsed[0] += get_process_delta_time()
		if elapsed[0] > PUPPET_DASH_RETRY and attacker.bot is TutorialPuppet and attacker.bot.is_idle() and not attacker.is_dead:
			elapsed[0] = 0.0
			_stage(attacker, PUPPET_STAGE_DISTANCE)
			attacker.bot.dash_at(_player)
		return attacker.is_stunned or attacker.is_dead)
	_overlay.hide_card()

	await _card(
		"THAT IS THE POINT",
		"They bounced off, and it cost them. Shields run out - use them while they last.",
		[{"node": _player, "radius": 110.0}],
	)
	if attacker.bot is TutorialPuppet:
		attacker.bot.stand_still()


func _beat_last_standing() -> void:
	if _skipped:
		return
	for i in _puppets.size():
		_reveal(_puppets[i], 180.0 * float(i + 1))

	await _card(
		"LAST ONE STANDING",
		"You have five lives. Everyone does. The last player with any left wins the match.",
		[{"control": _alive_block(), "pad": 14.0}],
	)

	_unfreeze()
	_overlay.show_card("", "Watch what happens when a timer runs out.", [], "")
	for i in _puppets.size():
		var bomb := _puppets[i].get_node("BombController") as BombController
		bomb.lethal = true
		bomb.set_lives(1)
		bomb.bomb_time = 2.5 + 2.5 * float(i)
		bomb.reset_for_respawn()
		_hold_bomb(bomb, false)

	await _until(func() -> bool: return MinigameDirector.is_match_finished())
	_overlay.hide_card()
	_overlay.clear_spotlight()
	_finished = true


func _hud_slot() -> Control:
	var block := _arena.get_node_or_null("MatchHUD/Header/TimerBlock") as Control
	if block == null:
		return null
	for child in block.get_children():
		if child is Control and child.visible:
			return child
	return block


func _alive_block() -> Control:
	return _arena.get_node_or_null("MatchHUD/Header/AliveBlock") as Control


func _slot_control() -> Control:
	return _arena.get_node_or_null("MinigameLayout/Layout/Slot%d" % _bomb.get_slot_index()) as Control


func _arena_marker(index: int) -> Node2D:
	var group := _arena.get_node_or_null("LightningPlatforms")
	if group == null or index < 0 or index >= group.get_child_count():
		return _player
	return group.get_child(index) as Node2D


func _on_skip_requested() -> void:
	if _finished:
		return
	_skipped = true
	_release_everything()
	_overlay.show_completion()


func _release_everything() -> void:
	_overlay.hide_card()
	_overlay.release_minigame()
	_overlay.clear_spotlight()
	_arena.dismiss_safe_zone()
	MinigameDirector.unlock_input(MinigameDirector.LOCK_TUTORIAL)
	_frozen = false
	_held_bombs.clear()
	for player in _arena.players:
		if is_instance_valid(player):
			player.set_physics_process(true)


func show_completion() -> void:
	_overlay.show_completion()


func _on_practice_requested() -> void:
	LocalPlayers.reset()
	LocalPlayers.singleplayer = true
	LocalPlayers.tutorial_practice = true
	LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
	LocalPlayers.add_bots(3)
	SceneTransition.circle_to("res://scenes/tutorial_arena.tscn")


func _on_replay_requested() -> void:
	LocalPlayers.reset()
	LocalPlayers.singleplayer = true
	LocalPlayers.tutorial_practice = false
	LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
	LocalPlayers.add_bots(2)
	SceneTransition.circle_to("res://scenes/tutorial_arena.tscn")


func _on_quit_requested() -> void:
	LocalPlayers.reset()
	LocalPlayers.singleplayer = false
	LocalPlayers.tutorial_practice = false
	MinigameDirector.reset_match()
	SceneTransition.circle_to("res://scenes/main_menu.tscn")
