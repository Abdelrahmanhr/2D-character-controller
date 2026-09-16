extends Area2D
class_name ShieldPickup

## Overridden by whoever spawns this (see power_station.gd) -- defaults to matching
## player.gd's own shield_duration export.
@export var shield_duration: float = 10.0
## Auto-expires if uncollected, same "don't wait forever" convention SafeZone already
## follows (it expires on its own timer regardless of whether anyone interacted with
## it) rather than sitting in the arena indefinitely.
@export var lifetime: float = 20.0

const BOB_AMPLITUDE: float = 4.0
const BOB_HALF_DURATION: float = 1.2  ## one direction of the ping-pong; a full up-down-up cycle is ~2x this
const COLLECT_FLOURISH_DURATION: float = 0.25

var _consumed: bool = false
var _sprite: AnimatedSprite2D
var _bob_tween: Tween


func _ready() -> void:
	_sprite = $AnimatedSprite2D
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_despawn)
	_start_bob()


func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


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
	_despawn(true)


## animated=true (collected) plays a flourish before freeing; animated=false (the
## lifetime timeout, nobody collected it) frees immediately as before. Either way this
## stays the single despawn RPC -- call_local so every peer plays the same sequence
## (flourish or not) instead of only the peer that detected the collision seeing it.
func _despawn(animated: bool = false) -> void:
	if not is_inside_tree():
		return
	if not _is_networked():
		_do_despawn(animated)
	else:
		_do_despawn.rpc(animated)


@rpc("any_peer", "call_local", "reliable")
func _do_despawn(animated: bool = false) -> void:
	monitoring = false
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	if animated:
		await _play_collect_flourish()
	queue_free()


## Fast scale-up + fade, same tween-and-await shape used elsewhere in this project for
## a "play then remove" sequence.
func _play_collect_flourish() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", _sprite.scale * 1.6, COLLECT_FLOURISH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "modulate:a", 0.0, COLLECT_FLOURISH_DURATION)
	await tween.finished
