extends Node
class_name BotController
## Drives one player in singleplayer. Attached as a child of the player by
## ArenaBase._spawn_local_players when its device id is a bot id.
##
## Two jobs, and they are independent: keep the body moving somewhere sensible,
## and keep the bomb alive by actually playing the minigame on screen. The second
## is the one that matters - a bot that only walks around runs out of bomb time in
## forty seconds and eliminates itself.
##
## Deliberately no pathfinding. Walk-toward-an-x and jump-when-stuck is enough on
## these arenas, and it is the reason this file is short.

## How long after a prompt appears before the bot answers it. Set per bot at spawn
## so the three of them do not all solve in lockstep and die together - the player
## needs a weakest one to outlast. Must stay above the minigames' correct/wrong
## highlight tween (~0.2s), or the bot re-reads the prompt before it has advanced
## and answers the same one twice.
## The player reads jump as a rising edge, so a one-frame pulse can be missed
## between physics ticks. Held for a few instead.
const JUMP_HOLD_FRAMES := 4
## How far above the bot the zone has to be before it counts as "climb to it".
const CLIMB_THRESHOLD := 48.0
const STUCK_TIMEOUT := 8.0
const ESCAPE_FRAMES := 14

@export var reaction_time: float = 0.45
@export var reaction_jitter: float = 0.12

@export_group("Movement")
@export var wander_range: float = 260.0
## Standing still between wander legs. Bots should read as idle by default and
## only move with a reason, so the dwell is deliberately longer than the walk.
@export var idle_dwell_min: float = 2.5
@export var idle_dwell_max: float = 6.0
## Hysteresis, and the whole reason bots no longer vibrate on the spot. Stop
## inside arrive_threshold, and do not start again until the goal is further off
## than resume_threshold. With one threshold the bot overshoots it, flips sign,
## overshoots back, and player.gd flips the sprite on every one of those frames.
@export var arrive_threshold: float = 28.0
@export var resume_threshold: float = 96.0
## How close a telegraphed strike has to be before the bot walks off it.
@export var danger_radius: float = 90.0
## Fraction of the zone radius a bot is happy to sit at. Anywhere inside this it
## idles instead of creeping toward the exact centre - chasing the centre every
## frame was the other half of the jitter.
@export var zone_comfort: float = 0.55
## Rolled per physics frame, so this is ~60x per second - 0.012 was almost one
## jump a second and read as constant hopping.
@export var idle_jump_chance: float = 0.0015
## After a ledge veto, stop trying that direction at all for a moment. Otherwise
## a bot with a goal across a gap re-tries and brakes every frame, which is the
## same twitch by another route.
@export var ledge_block_time: float = 1.5
## Ledge probing. Without this bots walk straight off the arena into the DeathBox
## and burn all five lives in under half a minute - it was the single biggest
## thing keeping them alive in testing.
@export var ledge_look_ahead: float = 42.0
@export var ledge_probe_depth: float = 60.0
## How far off the zone centre each bot parks, so they do not all stack up.
@export var zone_spread: float = 70.0

var move_x: float = 0.0
var move_y: float = 0.0
var jump_held: bool = false
var dash_held: bool = false

var _player: CharacterBody2D
var _bomb: BombController
var _rng := RandomNumberGenerator.new()
var _solve_timer: float = 0.0
var _target_x: float = 0.0
## Latched arrival, cleared only once the goal is resume_threshold away again.
var _arrived: bool = true
var _dwell_timer: float = 0.0
var _ledge_block_dir: float = 0.0
var _ledge_block_timer: float = 0.0
var _jump_frames: int = 0
var _stuck_timer: float = 0.0
var _escape_frames: int = 0
var _stuck_anchor_x: float = 0.0
## Set by _pick_goal_x. Zone-seeking overrides the ledge veto and climbs, because
## standing safely still outside a closing zone kills you just as dead.
var _seeking_zone: bool = false
var _zone_above: bool = false
## Cached from the arena once - spawn points do not move.
var _bounds := Vector2(-INF, INF)
var _zone_offset: float = 0.0
## When a zone is up and the bot is already inside it, wandering is leashed to
## this band so it cannot amble back out of the zone it just reached.
var _leash_x: float = 0.0
var _leash_radius: float = 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_bomb = _player.get_node_or_null("BombController") as BombController
	_rng.randomize()
	_target_x = _player.global_position.x
	_stuck_anchor_x = _player.global_position.x
	var arena := get_tree().current_scene
	if arena != null and arena.has_method("get_play_bounds_x"):
		_bounds = arena.get_play_bounds_x()
	_zone_offset = _rng.randf_range(-zone_spread, zone_spread)
	_dwell_timer = _rng.randf_range(idle_dwell_min, idle_dwell_max)
	_reset_solve_timer()


func _physics_process(delta: float) -> void:
	_think_minigame(delta)
	_think_movement(delta)


# --- minigames --------------------------------------------------------------

func _think_minigame(delta: float) -> void:
	if _bomb == null or MinigameDirector.is_match_finished():
		return
	_solve_timer -= delta
	if _solve_timer > 0.0:
		return
	_reset_solve_timer()
	_bomb.bot_submit()


func _reset_solve_timer() -> void:
	_solve_timer = maxf(0.05, reaction_time + _rng.randf_range(-reaction_jitter, reaction_jitter))


# --- movement ---------------------------------------------------------------

func _think_movement(delta: float) -> void:
	move_x = 0.0
	move_y = 0.0
	dash_held = false

	if _player.is_dead or _player.is_stunned or MinigameDirector.is_match_finished():
		jump_held = false
		_jump_frames = 0
		_stuck_timer = 0.0
		_escape_frames = 0
		return

	var here := _player.global_position
	var goal_x: float = _pick_goal_x(here, delta)
	var dx: float = goal_x - here.x

	# Latch, do not compare against one threshold every frame.
	if _arrived:
		if absf(dx) > resume_threshold:
			_arrived = false
	elif absf(dx) <= arrive_threshold:
		_arrived = true

	if not _arrived:
		move_x = signf(dx)

	if _ledge_block_timer > 0.0:
		_ledge_block_timer -= delta
		if is_equal_approx(signf(move_x), _ledge_block_dir):
			# Nothing that way. Stand still rather than shuffle into the lip.
			move_x = 0.0

	# Refuse to step into thin air. Airborne bots keep their input so a jump or a
	# knockback still carries them; only a grounded bot gets vetoed.
	var at_ledge: bool = not is_zero_approx(move_x) and _player.is_on_floor() 		and not _has_ground_ahead(here, move_x)

	if _escape_frames > 0:
		_escape_frames -= 1
		at_ledge = false

	if at_ledge:
		# Never overridden, not even to chase the zone. Letting a bot jump a gap
		# toward the zone reads well and kills it fast - the DeathBox takes a
		# whole life, where being outside the zone only starts a 3s timer that
		# often never finishes.
		_ledge_block_dir = signf(move_x)
		_ledge_block_timer = ledge_block_time
		_target_x = _clamp_to_bounds(here.x - signf(move_x) * wander_range * 0.5)
		_arrived = false
		# Brake only while still sliding at the lip - at full speed the bot
		# carries ~15px of momentum past it. Reversing unconditionally was a
		# one-frame sprite flip every time.
		var sliding: bool = is_equal_approx(signf(_player.velocity.x), signf(move_x)) 			and absf(_player.velocity.x) > 20.0
		move_x = -signf(move_x) if sliding else 0.0

	if _player.is_on_floor() and not at_ledge:
		if _player.is_on_wall():
			_jump_frames = JUMP_HOLD_FRAMES
		elif _seeking_zone and _zone_above:
			# The zone is up there and there is floor ahead - climb toward it.
			_jump_frames = JUMP_HOLD_FRAMES
		elif _rng.randf() < idle_jump_chance:
			_jump_frames = JUMP_HOLD_FRAMES

	if absf(here.x - _stuck_anchor_x) > arrive_threshold:
		_stuck_anchor_x = here.x
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta

	if _stuck_timer > STUCK_TIMEOUT:
		_stuck_timer = 0.0
		_ledge_block_timer = 0.0
		_ledge_block_dir = 0.0
		_dwell_timer = _rng.randf_range(idle_dwell_min, idle_dwell_max)
		var centre: float = (_bounds.x + _bounds.y) * 0.5 if not is_inf(_bounds.x) else here.x
		var toward: float = signf(centre - here.x)
		if is_zero_approx(toward):
			toward = 1.0 if _rng.randf() < 0.5 else -1.0
		_target_x = _clamp_to_bounds(here.x + toward * _rng.randf_range(resume_threshold, wander_range))
		_arrived = false
		_jump_frames = JUMP_HOLD_FRAMES
		_escape_frames = ESCAPE_FRAMES
		_stuck_anchor_x = here.x

	if _jump_frames > 0:
		_jump_frames -= 1
		jump_held = true
	else:
		jump_held = false


## Priority order: get off a spot about to be struck, then get inside the safe
## zone, then wander.
func _pick_goal_x(here: Vector2, delta: float) -> float:
	_seeking_zone = false
	_zone_above = false

	var danger_x: float = _danger_escape_x(here)
	if not is_nan(danger_x):
		return danger_x

	if _ledge_block_timer > 0.0:
		_leash_radius = 0.0
		return _target_x

	# While a zone is up the bot heads for it whether or not it is currently
	# outside. Only steering when already outside was the single worst bug here:
	# a bot that made it in went straight back to random wandering and walked out
	# of a 220px circle within a second or two, over and over.
	_leash_radius = 0.0

	var zone := get_tree().get_first_node_in_group("safe_zones")
	if zone != null:
		var comfort: float = zone.get_radius() * zone_comfort
		if zone.is_outside(here) or here.distance_to(zone.global_position) > comfort:
			_seeking_zone = true
			# Only climb when actually outside; inside, jumping invites trouble.
			_zone_above = zone.is_outside(here) 				and zone.global_position.y < here.y - CLIMB_THRESHOLD
			# A fixed per-bot offset so three bots do not converge on one pixel
			# and shove each other back out.
			return zone.global_position.x + _zone_offset
		# Comfortably inside. Keep wandering rather than freezing on the spot -
		# a zone is up most of the match, so "stand still inside it" meant the
		# bots barely moved all game - but on a leash, so wandering never walks
		# them back out of the thing they just walked into.
		_leash_x = zone.global_position.x + _zone_offset * 0.5
		_leash_radius = comfort * 0.7

	# Wander is dwell-driven: walk one leg, then stand there a while. Retargeting
	# on a timer regardless of arrival meant a bot could be handed a new goal
	# mid-stride and turn on the spot.
	if _arrived:
		_dwell_timer -= delta
		if _dwell_timer <= 0.0:
			_dwell_timer = _rng.randf_range(idle_dwell_min, idle_dwell_max)
			var pick: float = here.x + _rng.randf_range(-wander_range, wander_range)
			if _leash_radius > 0.0:
				pick = clampf(pick, _leash_x - _leash_radius, _leash_x + _leash_radius)
			_target_x = _clamp_to_bounds(pick)
			if absf(_target_x - here.x) <= arrive_threshold:
				var away: float = -signf(_target_x - here.x)
				if is_zero_approx(away):
					away = 1.0 if _rng.randf() < 0.5 else -1.0
				_target_x = _clamp_to_bounds(here.x + away * _rng.randf_range(resume_threshold, wander_range))
			_arrived = false
	return _target_x


## Keeps wandering inside the outermost spawn points. Bots have no map knowledge,
## so without this they eventually pick a target past the edge and walk into the
## DeathBox, which costs a whole life where most hazards only cost a stun.
func _clamp_to_bounds(x: float) -> float:
	if is_inf(_bounds.x):
		return x
	return clampf(x, _bounds.x, _bounds.y)


## NAN means "nothing to run from" - a sentinel rather than a second return value,
## since every real answer is a world x.
func _danger_escape_x(here: Vector2) -> float:
	var arena := get_tree().current_scene
	if arena == null or not arena.has_method("get_danger_positions"):
		return NAN
	var nearest_dx: float = 0.0
	var found := false
	for spot in arena.get_danger_positions():
		if absf(spot.x - here.x) > danger_radius:
			continue
		if not found or absf(spot.x - here.x) < absf(nearest_dx):
			nearest_dx = spot.x - here.x
			found = true
	if not found:
		return NAN
	# Walk directly away from it, far enough to clear the radius.
	var away: float = -signf(nearest_dx) if not is_zero_approx(nearest_dx) else 1.0
	return here.x + away * danger_radius * 1.5


## Is there floor just ahead in this direction? A short ray down from a point in
## front of the bot, against whatever the player itself collides with.
func _has_ground_ahead(here: Vector2, dir: float) -> bool:
	var space := _player.get_world_2d().direct_space_state
	var from := here + Vector2(ledge_look_ahead * signf(dir), 0.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, ledge_probe_depth))
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	return not space.intersect_ray(query).is_empty()
