extends Node
## Autoload as "MusicManager". One track at a time, crossfaded between scenes.
##
## Two players rather than one, because a single AudioStreamPlayer cannot fade
## out the old track and in the new one at the same time - swapping .stream cuts
## the old one dead. They alternate: whichever is idle becomes the next track.
##
## Call sites name a track id, not a file. TRACKS owns the paths, so adding or
## replacing music is an edit in one place and the arenas do not carry preloads.

## id -> where to find it and how loud to play it.
##
## "paths" is a preference list: the first file that actually exists wins. That
## is what lets the new per-arena tracks be dropped into resources/audio/ later
## without touching code - until then each id falls back to the track the game
## shipped with, so nothing is ever silent.
##
## Godot only sees a new audio file once it has been imported (open the project
## in the editor once after adding it), which is also when its .import is made.
const TRACKS := {
	&"menu": {
		"paths": [
			"res://resources/audio/menu_theme.ogg",
			"res://resources/audio/MAINMENUSOUNDTRACK.ogg",
		],
		"volume_db": -20.0,
	},
	&"arena_power_station": {
		"paths": [
			"res://resources/audio/arena_power_station.ogg",
			"res://resources/audio/ARENA SOUNDTRACK.ogg",
		],
		"volume_db": -25.0,
	},
	&"arena_residential": {
		"paths": [
			"res://resources/audio/arena_residential.ogg",
			"res://resources/audio/ARENA SOUNDTRACK.ogg",
		],
		"volume_db": -25.0,
	},
	## What ArenaBase plays when a subclass has not named a track of its own, so
	## a new arena scene gets music before anyone writes one for it.
	&"arena_default": {
		"paths": ["res://resources/audio/ARENA SOUNDTRACK.ogg"],
		"volume_db": -25.0,
	},
}

const SILENT_DB := -80.0

@export var crossfade_duration: float = 1.2
## Boot has nothing to fade out of, so it uses a shorter lead-in.
@export var fade_in_duration: float = 0.5
## How far the music drops while the pause menu is open.
@export var duck_db: float = -12.0
@export var duck_duration: float = 0.35

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _current_id: StringName = &""
## Track volume and duck offset are kept apart so they can change independently -
## pausing mid-crossfade must not strand the new track at the old track's level.
var _base_db: float = 0.0
var _duck_offset: float = 0.0
var _fade_tween: Tween
var _duck_tween: Tween
var _stream_cache: Dictionary = {}


func _ready() -> void:
	# Menus run under a paused tree, and the pause menu ducks from there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)


## The one call sites use. Re-requesting the track that is already playing does
## nothing, so walking main menu -> arena select -> lobby never restarts it.
func play_id(id: StringName, duration: float = -1.0) -> void:
	if not TRACKS.has(id):
		push_warning("MusicManager: unknown track id '%s'" % id)
		return
	if id == _current_id and _players[_active].playing:
		return
	var stream := _resolve(id)
	if stream == null:
		push_warning("MusicManager: no file found for track '%s'" % id)
		return
	_current_id = id
	_base_db = float(TRACKS[id]["volume_db"])
	var fade: float = duration
	if fade < 0.0:
		# Nothing to cross with on the first track of the session.
		fade = crossfade_duration if _players[_active].playing else fade_in_duration
	_crossfade(stream, fade)


func stop(fade_out: float = 0.6) -> void:
	_current_id = &""
	var outgoing := _players[_active]
	_kill_tweens()
	if not outgoing.playing:
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade_out)
	_fade_tween.tween_callback(outgoing.stop)


## Pull the music down without stopping it - the pause menu wants the match
## still audible underneath. Idempotent, so repeated pauses do not stack.
func duck(enable: bool) -> void:
	var offset: float = duck_db if enable else 0.0
	if is_equal_approx(offset, _duck_offset):
		return
	_duck_offset = offset
	_apply_volume()


## Tween the active player to whatever the track volume plus the duck offset
## currently is. Split out because pausing during a scene change has to wait for
## the crossfade rather than fight it for the same volume_db.
func _apply_volume() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	if not _players[_active].playing:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		await _fade_tween.finished
		if not _players[_active].playing:
			return
	_duck_tween = create_tween()
	# _active may have flipped while awaiting, so read it now, not before.
	_duck_tween.tween_property(_players[_active], "volume_db",
		_base_db + _duck_offset, duck_duration)


func _crossfade(stream: AudioStream, duration: float) -> void:
	_kill_tweens()
	var outgoing := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]

	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", _base_db + _duck_offset, duration)
	if outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", SILENT_DB, duration)
		# Chained off the parallel block so it only fires once both fades land.
		_fade_tween.chain().tween_callback(outgoing.stop)


func _kill_tweens() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()


## First existing path wins. Cached because ResourceLoader.exists hits the disk
## and this runs on every scene change.
func _resolve(id: StringName) -> AudioStream:
	if _stream_cache.has(id):
		return _stream_cache[id]
	var stream: AudioStream = null
	for path in TRACKS[id]["paths"]:
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			if stream != null:
				break
	if stream != null:
		_set_looping(stream)
	_stream_cache[id] = stream
	return stream


## Both shipped tracks were imported with loop=false, so they played once and
## left the arena silent. Set it here rather than in the .import files so a
## track dropped in later loops too, without anyone remembering an import flag.
func _set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
