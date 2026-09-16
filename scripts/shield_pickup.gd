extends Area2D
class_name ShieldPickup

## Overridden by whoever spawns this (see power_station.gd) -- defaults to matching
## player.gd's own shield_duration export.
@export var shield_duration: float = 10.0
## Auto-expires if uncollected, same "don't wait forever" convention SafeZone already
## follows (it expires on its own timer regardless of whether anyone interacted with
## it) rather than sitting in the arena indefinitely.
@export var lifetime: float = 20.0

@export_group("Audio")
@export var spawn_sound_volume_db: float = -6.0
@export var collect_sound_volume_db: float = -4.0

@export_group("Glow")
## Same blue as player.gd's shield_flash_color, so the pickup's glow reads as a
## preview of the aura you get from collecting it.
@export var glow_color: Color = Color(0.3216, 0.6392, 1.0, 1.0)
@export var glow_idle_alpha_min: float = 0.35
@export var glow_idle_alpha_max: float = 0.85
@export var glow_breathe_half_duration: float = 1.1  ## one direction of the pulse ping-pong
@export var glow_punch_alpha: float = 1.0
@export var glow_punch_sprite_brightness: float = 2.4  ## sprite modulate multiplier at the punch's peak
@export var glow_punch_duration: float = 0.07

const SPAWN_SOUND := preload("res://resources/audio/Pickup Spawn.wav")
const COLLECT_SOUND := preload("res://resources/audio/Pickup.wav")

const BOB_AMPLITUDE: float = 4.0
const BOB_HALF_DURATION: float = 1.2  ## one direction of the ping-pong; a full up-down-up cycle is ~2x this
const COLLECT_FLOURISH_DURATION: float = 0.25

var _consumed: bool = false
var _sprite: AnimatedSprite2D
var _glow: Sprite2D
var _spawn_sound_player: AudioStreamPlayer2D
var _collect_sound_player: AudioStreamPlayer2D
var _bob_tween: Tween
var _glow_tween: Tween
var _expire_time_ms: int = -1


func _ready() -> void:
	_sprite = $AnimatedSprite2D
	_glow = $Glow
	_spawn_sound_player = $SpawnSound
	_collect_sound_player = $CollectSound
	body_entered.connect(_on_body_entered)
	_expire_time_ms = _get_timestamp() + int(lifetime * 1000.0)
	_start_bob()
	_start_glow_breathe()
	_play_spawn_sound()
	MinigameDirector.input_locked_changed.connect(_on_input_locked_changed)


## Every peer instantiates its own local ShieldPickup when the authority's spawn RPC
## runs (see power_station.gd's _spawn_shield_pickup, call_local), so _ready firing
## once per peer already means this plays exactly once per peer -- no extra gating
## needed, same as the pickup becoming visible for everyone simultaneously.
func _play_spawn_sound() -> void:
	_spawn_sound_player.stream = SPAWN_SOUND
	_spawn_sound_player.volume_db = spawn_sound_volume_db
	_spawn_sound_player.play()


## Polled instead of a get_tree().create_timer(lifetime) so the pickup's own
## uncollected-expiry doesn't keep counting down in real time behind a couch
## pause -- same pause-aware clock SafeZone/PowerStation hazards use.
func _process(_delta: float) -> void:
	if _consumed or _expire_time_ms < 0:
		return
	if _get_timestamp() >= _expire_time_ms:
		_despawn()


func _on_input_locked_changed(locked: bool) -> void:
	for tween in [_bob_tween, _glow_tween]:
		if not is_instance_valid(tween) or not tween.is_valid():
			continue
		if locked:
			tween.pause()
		else:
			tween.play()


func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _get_timestamp() -> int:
	return MinigameDirector.get_hazard_time_ms()


## Idle bob, started once and left running for as long as the pickup sits uncollected
## -- killed in _do_despawn rather than left to fight the collect flourish over the
## same sprite.
func _start_bob() -> void:
	var base_y: float = _sprite.position.y
	_bob_tween = create_tween()
	_bob_tween.set_loops()
	_bob_tween.tween_property(_sprite, "position:y", base_y - BOB_AMPLITUDE, BOB_HALF_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_sprite, "position:y", base_y + BOB_AMPLITUDE, BOB_HALF_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Idle "breathing" glow so the pickup reads as noticeable/grabbable from a
## distance instead of the flat static card -- a soft additive halo (same
## light_glow.tres + additive-unshaded material convention as mash_minigame.gd's
## screen glow) pulsing alpha, plus the sprite's own brightness riding along with
## it via modulate values above 1 (the same overbright trick power_station.gd's
## platform lift and MinigameScreens' flash_color already use). Killed in
## _do_despawn the same way _bob_tween is, so the collect punch doesn't fight it.
func _start_glow_breathe() -> void:
	_glow.material = _shared_glow_material()
	_glow_tween = create_tween()
	_glow_tween.set_loops()
	_glow_tween.set_parallel(true)
	_glow_tween.tween_method(_set_glow_alpha, glow_idle_alpha_min, glow_idle_alpha_max, glow_breathe_half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(_sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), glow_breathe_half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.chain().set_parallel(true)
	_glow_tween.tween_method(_set_glow_alpha, glow_idle_alpha_max, glow_idle_alpha_min, glow_breathe_half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), glow_breathe_half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_glow_alpha(alpha: float) -> void:
	_glow.modulate = Color(glow_color.r, glow_color.g, glow_color.b, alpha)


static var _glow_shared_material: CanvasItemMaterial

## Mirrors MinigameScreens._glow_material(): one additive+unshaded material shared
## across every pickup instance rather than a fresh one per spawn.
static func _shared_glow_material() -> CanvasItemMaterial:
	if _glow_shared_material == null:
		_glow_shared_material = CanvasItemMaterial.new()
		_glow_shared_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow_shared_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _glow_shared_material


func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	if not (body is CharacterBody2D) or not body.is_in_group("players"):
		return
	# Same authority pattern _on_death_zone_body_entered already uses: every peer's
	# Area2D fires locally (bodies still register collision shapes at their current
	# position whether they're locally simulated or just interpolated), but only the
	# peer that owns the body that touched it actually acts -- apply_shield's own
	# any_peer/call_local RPC then syncs the resulting shield state to everyone else.
	if _is_networked() and not body.is_multiplayer_authority():
		return
	_consumed = true
	if body.has_method("apply_shield"):
		body.apply_shield(shield_duration)
	# Local-only: this whole function already returned above for every peer except
	# the one whose body triggered the collision, so nothing here needs its own
	# authority gate or RPC -- calling .play() directly is already exactly as local
	# as the shield application above it. _despawn(true) right after runs
	# synchronously in the same frame (call_local RPCs invoke locally immediately),
	# so the sound and the flourish's glow punch land together, not staggered.
	_play_collect_sound()
	_despawn(true)


## animated=true (collected) plays a flourish before freeing; animated=false (the
## lifetime timeout, nobody collected it) frees immediately as before. Either way this
## stays the single despawn RPC -- call_local so every peer plays the same sequence
## (flourish or not) instead of only the peer that detected the collision seeing it.
func _despawn(animated: bool = false) -> void:
	if not is_inside_tree():
		return
	# Guards the lifetime-expiry poll in _process from re-firing every frame while
	# the freed node is still finishing its exit (queue_free/RPC round trip isn't
	# instant), the same way _on_body_entered already guards collection.
	_consumed = true
	if not _is_networked():
		_do_despawn(animated)
	else:
		_do_despawn.rpc(animated)


## Local-only, per the same reasoning as the call site in _on_body_entered: detached
## from this node instead of left as its child, so it keeps playing to completion
## even though _do_despawn frees the pickup ~COLLECT_FLOURISH_DURATION later
## regardless of how long the sound clip actually runs. Self-frees on `finished`.
func _play_collect_sound() -> void:
	_collect_sound_player.stream = COLLECT_SOUND
	_collect_sound_player.volume_db = collect_sound_volume_db
	var scene := get_tree().current_scene
	if scene == null:
		_collect_sound_player.play()
		return
	var pos := global_position
	remove_child(_collect_sound_player)
	scene.add_child(_collect_sound_player)
	_collect_sound_player.global_position = pos
	_collect_sound_player.finished.connect(_collect_sound_player.queue_free)
	_collect_sound_player.play()


@rpc("any_peer", "call_local", "reliable")
func _do_despawn(animated: bool = false) -> void:
	monitoring = false
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	if animated:
		await _play_collect_flourish()
	queue_free()


## Punches the glow brighter first (same frame the collect sound plays, since this
## whole await chain starts synchronously off _on_body_entered's call), then eases
## into the existing scale-up + fade -- "punch before it fades," per spec. Same
## tween-and-await shape used elsewhere in this project for a "play then remove"
## sequence.
func _play_collect_flourish() -> void:
	var punch := create_tween()
	punch.set_parallel(true)
	punch.tween_method(_set_glow_alpha, _glow.modulate.a, glow_punch_alpha, glow_punch_duration)
	punch.tween_property(_sprite, "modulate", Color(glow_punch_sprite_brightness, glow_punch_sprite_brightness, glow_punch_sprite_brightness, 1.0), glow_punch_duration)
	await punch.finished

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", _sprite.scale * 1.6, COLLECT_FLOURISH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "modulate:a", 0.0, COLLECT_FLOURISH_DURATION)
	tween.tween_property(_glow, "modulate:a", 0.0, COLLECT_FLOURISH_DURATION)
	await tween.finished
