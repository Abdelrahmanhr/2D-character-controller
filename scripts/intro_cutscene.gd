extends Node2D

## Cutscene hooks for sending Player and the Mushroom explosion behind the Sky
## CanvasLayer's "Front" layer for parts of the cutscene, so they read as falling/
## erupting far into the background rather than staying in the normal foreground
## layer.
##
## CanvasLayers render as their own independent pass, in ascending `layer` order,
## completely separate from the default canvas' node-tree/z-index ordering - so
## neither reparenting under IntroCutscene nor changing z_index would ever put
## something behind anything inside Sky (layer -5). The only way to interleave
## draw order between Sky's own children (Closer/Front) is to make the node an
## actual sibling inside that same CanvasLayer, ordered before Front.
##
## The complication: a CanvasLayer's content ignores the active Camera2D by
## design (that's what makes it useful for parallax/UI that shouldn't move with
## the camera) - Player and Mushroom, everywhere else, render through the camera.
## Moving either into Sky verbatim would pop it to the wrong screen position the
## instant it switches, and every following frame Player is still moving, since
## its position keeps being driven by the untouched AnimationPlayer track
## underneath. BehindSkyAnchor absorbs exactly that difference: its own transform
## is kept in lock-step with the camera every frame while either is parked under
## it, so their existing position/rotation/scale animation keeps rendering in the
## same place it always would have, just one canvas layer further back. Shared by
## both since neither's own local offset relative to the anchor is affected by
## the other also being parked there.

@onready var player: AnimatedSprite2D = $Player
@onready var mushroom: AnimatedSprite2D = $World/Mushroom
@onready var camera: Camera2D = $Camera2D
@onready var behind_sky_anchor: Node2D = $Sky/BehindSkyAnchor

var _player_original_parent: Node = null
var _player_original_index: int = -1
var _player_original_position: Vector2 = Vector2.ZERO
var _player_original_rotation: float = 0.0
var _player_original_scale: Vector2 = Vector2.ONE
var _player_original_z_index: int = 0
var _is_player_behind_sky: bool = false

var _mushroom_original_parent: Node = null
var _mushroom_original_index: int = -1
var _mushroom_original_position: Vector2 = Vector2.ZERO
var _mushroom_original_rotation: float = 0.0
var _mushroom_original_scale: Vector2 = Vector2.ONE
var _mushroom_original_z_index: int = 0
var _is_mushroom_behind_sky: bool = false


func _process(_delta: float) -> void:
	if _is_player_behind_sky or _is_mushroom_behind_sky:
		_update_behind_sky_anchor()


func _update_behind_sky_anchor() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	behind_sky_anchor.position = viewport_size * 0.5 - camera.global_position * camera.zoom
	behind_sky_anchor.scale = camera.zoom


## Cutscene hook, called from the "intro" animation at t=4.4 - the beat an audio
## track on a local AudioStreamPlayer used to start the song on instead.
##
## It goes through MusicManager so the song survives the change into the main menu.
## A player living in this scene is freed by change_scene_to_file, which is exactly
## what used to cut the music dead the moment PLAY was pressed. This is the menu's
## own track, just run louder here; intro_end_card settles it down to the menu's
## level on the way out. See MusicManager.play_id.
func start_music() -> void:
	MusicManager.play_id(&"menu", 0.6, MusicManager.CUTSCENE_DB)


## Cutscene hook, called from the "intro" animation's method track the instant
## Player:position:y reaches -360 (partway down from the explosion launch arc).
## A no-op if already switched, so scrubbing the timeline back and forth can't
## reparent Player onto itself.
func send_player_behind_sky() -> void:
	if _is_player_behind_sky:
		return
	_is_player_behind_sky = true
	_player_original_parent = player.get_parent()
	_player_original_index = player.get_index()
	_player_original_position = player.position
	_player_original_rotation = player.rotation
	_player_original_scale = player.scale
	_player_original_z_index = player.z_index
	_update_behind_sky_anchor()
	player.reparent(behind_sky_anchor, true)


## Cutscene hook, called once the mushroom cloud has fully faded. Restores
## Player's exact original parent, sibling index, local transform and z_index -
## this sprite keeps appearing for the rest of the cutscene, so anything less
## than an exact restore would leave it rendering wrong from here on.
func restore_player_layering() -> void:
	if not _is_player_behind_sky:
		return
	_is_player_behind_sky = false
	player.reparent(_player_original_parent, false)
	_player_original_parent.move_child(player, _player_original_index)
	player.position = _player_original_position
	player.rotation = _player_original_rotation
	player.scale = _player_original_scale
	player.z_index = _player_original_z_index


## Cutscene hook, called the instant the mushroom becomes visible (the explosion
## itself), same reparent-behind-Front treatment as the player.
func send_mushroom_behind_sky() -> void:
	if _is_mushroom_behind_sky:
		return
	_is_mushroom_behind_sky = true
	_mushroom_original_parent = mushroom.get_parent()
	_mushroom_original_index = mushroom.get_index()
	_mushroom_original_position = mushroom.position
	_mushroom_original_rotation = mushroom.rotation
	_mushroom_original_scale = mushroom.scale
	_mushroom_original_z_index = mushroom.z_index
	_update_behind_sky_anchor()
	mushroom.reparent(behind_sky_anchor, true)
	# Mushroom's authored z_index (-1) was calibrated for its original spot in
	# World, to sit behind other default-canvas elements there - carried over
	# as-is into Sky, it sinks below every sky layer (all z_index 0), not just
	# Front, since z_index compares across the whole canvas layer regardless of
	# tree position. Neutralize it here so sibling order (this anchor sits right
	# before Front) is what decides the stacking instead; restored below.
	mushroom.z_index = 0


## Cutscene hook, called once the mushroom cloud has fully faded - restores its
## exact original parent/index/transform/z_index.
func restore_mushroom_layering() -> void:
	if not _is_mushroom_behind_sky:
		return
	_is_mushroom_behind_sky = false
	mushroom.reparent(_mushroom_original_parent, false)
	_mushroom_original_parent.move_child(mushroom, _mushroom_original_index)
	mushroom.position = _mushroom_original_position
	mushroom.rotation = _mushroom_original_rotation
	mushroom.scale = _mushroom_original_scale
	mushroom.z_index = _mushroom_original_z_index
