extends Control

## Pixel-art title sting: "BON VOYAGE" gets blown apart into "BOMB VOYAGE".
##
## Two rules keep this from reading like a web tween:
##   * every pose is held on a discrete key (see _add_step_track) so the logo
##     animates "on twos" the way hand-drawn pixel VFX do, instead of easing
##     between poses;
##   * the burst is rasterised onto a fat-pixel grid and the fire is the same
##     sprite sheet the players explode with, so nothing has a smooth vector edge.

const LOGO_FONT := preload("res://resources/fonts/boldpixels.ttf")
const BLAST_FRAMES := [
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame1.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame2.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame3.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame4.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame5.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame6.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame7.png"),
	preload("res://resources/Explode Frames/FireExplosion_VFX1_frame8.png"),
]

# blk-nx64 entries. The lettering borrows the city's own sign colours (cyan
# tube, magenta bleed, indigo night) while the fireball stays warm so it reads
# as fire and the cool text separates from it.
const INK := Color("#12173d")
const NEON := Color("#8cdaff")
const MAGENTA := Color("#ff6eaf")
const BLAZE := Color("#ffaa6e")
const FLARE := Color("#ffe091")
const EMBER := Color("#e54286")
# Pre-blast palette. The sign before it is a sign: bone-grey on indigo, no
# magenta bleed and no neon, so the sting's jump to full colour actually lands.
const MUTED := Color("#b9bcd4")
const MUTED_SHADOW := Color("#2a2f5c")
# Burst ramp steps down in luminance (flare 78 -> blaze 71 -> ember 57) so the
# shading reads; MAGENTA is kept brighter for the sign glow under the letters.
const TONE_COLORS := [Color(0.0, 0.0, 0.0, 0.0), INK, BLAZE, FLARE, EMBER]

# Word boxes. The badge and the impact point are both derived from these rather
# than hardcoded, so they stay locked to the lettering if it ever moves.
const WORD_BOX := Vector2(640.0, 92.0)
const BOMB_TOP := 24.0
const VOYAGE_TOP := 76.0
const BOMB_FONT := 92
const VOYAGE_FONT := 72
## boldpixels draws caps at ~0.49 of the nominal size; the rest of the line box is
## ascender/descender room these all-caps words never touch. Measured off a render.
const CAP_RATIO := 0.49

const PIXEL := 6.0
const BURST_RX := 208.0
const BURST_RY := 108.0
const BURST_SPIKES := 11.0
const BURST_INNER := 0.58

const FLASH_RX := 160.0
const FLASH_RY := 96.0
const FLASH_BAND := PIXEL * 2.0

const SHARD_COUNT := 32
const SHARD_PIXEL := 4.0
const SHARD_GRAVITY := 700.0
const BLAST_FPS := 14.0
const HOLD := 0.004

## In-game this cue plays at 0 dB; here it is pitched down and pushed well
## under the menu track so it reads as a distant thump, not a hit.
@export var blast_sound: AudioStream = preload("res://resources/audio/Explode.wav")
@export var blast_volume_db: float = -20.0
@export var blast_pitch_shift: float = 0.8
## Holds the sting on "BON VOYAGE" until fire() is called, so a cutscene can detonate
## it on cue. Defaults false, so the main menu keeps auto-playing exactly as before.
@export var armed: bool = false
@export var blast_pitch_variance: float = 0.05

var burst_scale := 0.0:
	set(value):
		burst_scale = value
		queue_redraw()

var flash_alpha := 0.0:
	set(value):
		flash_alpha = value
		if _overlay != null:
			_overlay.queue_redraw()

var blast_time := 0.0:
	set(value):
		blast_time = value
		if _overlay != null:
			_overlay.queue_redraw()

var shake_offset := Vector2.ZERO:
	set(value):
		shake_offset = value.round()
		_apply_shake()
		queue_redraw()

var _center := Vector2.ZERO
var _badge := Vector2.ZERO
var _words: Array[Control] = []
var _shards: Array = []
var _burst_cache := {}
var _overlay: Node2D
var _fire: AnimatedSprite2D
var _anim: AnimationPlayer

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_center = _impact_center()
	_badge = _badge_center()

	var left := roundf((size.x - WORD_BOX.x) * 0.5)

	var bon := _make_word("BON", BOMB_FONT, NEON, MAGENTA)
	_style_quiet(bon)
	bon.position = Vector2(left, BOMB_TOP)
	bon.z_index = -1
	_register_word(bon)

	var bomb := _make_word("BOMB", BOMB_FONT, NEON, INK)
	bomb.name = "BombWord"
	bomb.position = Vector2(left, BOMB_TOP)
	bomb.modulate.a = 0.0
	bomb.scale = Vector2.ZERO
	_register_word(bomb)

	var voyage := _make_word("VOYAGE", VOYAGE_FONT, NEON, MAGENTA)
	voyage.name = "VoyageWord"
	voyage.position = Vector2(left, VOYAGE_TOP)
	voyage.add_theme_color_override("font_outline_color", INK)
	_style_quiet(voyage)
	_register_word(voyage)

	_fire = _make_fire()
	_fire.position = _center
	add_child(_fire)

	_overlay = Node2D.new()
	_overlay.name = "BlastOverlay"
	_overlay.z_index = 4
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_seed_shards()
	_relayout()
	_build_animation()

## Anchored Controls get their real width after _ready, so the words and the
## burst centre are re-derived whenever the node is laid out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()

func _relayout() -> void:
	if _words.is_empty():
		return
	pivot_offset = size * 0.5
	_center = _impact_center()
	_badge = _badge_center()
	var left := roundf((size.x - WORD_BOX.x) * 0.5)
	for word in _words:
		var home: Vector2 = word.get_meta("home")
		word.set_meta("home", Vector2(left, home.y))
	_apply_shake()
	queue_redraw()

## Vertical span of a word's actual ink, as opposed to its line box.
func _ink_span(top: float, font_size: int) -> Vector2:
	var half := font_size * CAP_RATIO * 0.5
	var middle := top + WORD_BOX.y * 0.5
	return Vector2(middle - half, middle + half)

## Where BOMB lands - the fire, flash and debris fire from here.
func _impact_center() -> Vector2:
	return Vector2(roundf(size.x * 0.5), BOMB_TOP + WORD_BOX.y * 0.5)

## The badge sits behind the whole BOMB VOYAGE lockup, so it centres on the
## combined ink of both words rather than on BOMB alone.
func _badge_center() -> Vector2:
	var bomb_ink := _ink_span(BOMB_TOP, BOMB_FONT)
	var voyage_ink := _ink_span(VOYAGE_TOP, VOYAGE_FONT)
	return Vector2(roundf(size.x * 0.5), roundf((bomb_ink.x + voyage_ink.y) * 0.5))

func _register_word(word: Label) -> void:
	word.set_meta("home", word.position)
	_words.append(word)
	add_child(word)

func _make_word(value: String, font_size: int, face_color: Color, shadow_color: Color) -> Label:
	var word := Label.new()
	word.text = value
	word.size = WORD_BOX
	word.pivot_offset = WORD_BOX * 0.5
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.add_theme_font_override("font", LOGO_FONT)
	word.add_theme_font_size_override("font_size", font_size)
	word.add_theme_color_override("font_color", face_color)
	word.add_theme_color_override("font_shadow_color", shadow_color)
	word.add_theme_color_override("font_outline_color", INK)
	word.add_theme_constant_override("shadow_offset_x", 0)
	word.add_theme_constant_override("shadow_offset_y", 3)
	word.add_theme_constant_override("shadow_outline_size", 4)
	word.add_theme_constant_override("outline_size", 5)
	return word

## Same pixel face, letterspaced and stripped of its glow - reads as a quiet
## engraved plaque rather than the arcade lockup. Spacing is a whole number of
## pixels, so nothing here softens the edges.
func _quiet_font() -> FontVariation:
	var face := FontVariation.new()
	face.base_font = LOGO_FONT
	face.spacing_glyph = 6
	return face

## The "BON VOYAGE" state: demure face, flat colour, thin outline, no shadow.
func _style_quiet(word: Label) -> void:
	word.add_theme_font_override("font", _quiet_font())
	word.add_theme_color_override("font_color", MUTED)
	word.add_theme_color_override("font_shadow_color", MUTED_SHADOW)
	word.add_theme_constant_override("shadow_offset_y", 0)
	word.add_theme_constant_override("shadow_outline_size", 0)
	word.add_theme_constant_override("outline_size", 3)

## Snapped on at the blast, so VOYAGE detonates into the same lockup as BOMB.
func _style_loud(word: Label) -> void:
	word.add_theme_font_override("font", LOGO_FONT)
	word.add_theme_color_override("font_color", NEON)
	word.add_theme_color_override("font_shadow_color", MAGENTA)
	word.add_theme_constant_override("shadow_offset_y", 5)
	word.add_theme_constant_override("shadow_outline_size", 4)
	word.add_theme_constant_override("outline_size", 5)

func _make_fire() -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.add_animation("blast")
	frames.set_animation_loop("blast", false)
	frames.set_animation_speed("blast", 18.0)
	for texture in BLAST_FRAMES:
		frames.add_frame("blast", texture)
	frames.remove_animation("default")

	var sprite := AnimatedSprite2D.new()
	sprite.name = "FireBlast"
	sprite.sprite_frames = frames
	sprite.animation = "blast"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * 2.0
	sprite.z_index = 3
	sprite.visible = false
	sprite.animation_finished.connect(_on_fire_finished)
	return sprite

func _on_fire_finished() -> void:
	_fire.visible = false

func _apply_shake() -> void:
	for word in _words:
		word.position = word.get_meta("home") + shake_offset
	if _fire != null:
		_fire.position = _center + shake_offset
	if _overlay != null:
		_overlay.queue_redraw()

## Fired from a method track so the sprite restarts exactly on the impact frame.
func _fire_blast() -> void:
	if _fire == null:
		return
	_fire.visible = true
	_fire.frame = 0
	_fire.play("blast")
	var voyage := get_node_or_null("VoyageWord") as Label
	if voyage != null:
		_style_loud(voyage)
	SfxManager.play(blast_sound, blast_volume_db, blast_pitch_variance, blast_pitch_shift)

# --- timeline -----------------------------------------------------------------

func _build_animation() -> void:
	var player := AnimationPlayer.new()
	add_child(player)

	var animation := Animation.new()
	# Ends on its own last key. The debris clock is the longest track and the
	# final shard dies at blast_time 0.62 (~t=0.92), so anything past 0.95 was
	# the logo sitting dead still waiting for the queued idle loop to start.
	animation.length = 0.95
	animation.loop_mode = Animation.LOOP_NONE

	# Crouch, snap to the hit, then rattle out in shrinking whole-pixel steps.
	_add_step_track(animation, ".:shake_offset",
		[0.00, 0.14, 0.22, 0.27, 0.30, 0.35, 0.40, 0.45, 0.50, 0.56, 0.62],
		[Vector2.ZERO, Vector2(0.0, 3.0), Vector2(0.0, 5.0), Vector2(0.0, -3.0),
		Vector2(8.0, -5.0), Vector2(-7.0, 4.0), Vector2(5.0, -3.0), Vector2(-4.0, 2.0),
		Vector2(2.0, -1.0), Vector2(-1.0, 1.0), Vector2.ZERO])

	# No grow-in: the badge is simply absent, then oversized, then settled - and
	# from 0.58 it picks up the idle breath early, so the logo is never holding
	# still while the debris is still in the air.
	_add_step_track(animation, ".:burst_scale",
		[0.00, 0.28, 0.30, 0.36, 0.42, 0.58, 0.74, 0.90],
		[0.0, 0.0, 1.28, 1.05, 1.0, 1.03, 1.05, 1.03])

	# A real blow-out: one opaque frame, one dirty frame, gone.
	_add_step_track(animation, ".:flash_alpha",
		[0.00, 0.28, 0.30, 0.335, 0.37],
		[0.0, 0.0, 1.0, 0.4, 0.0])

	_add_step_track(animation, "BombWord:modulate:a", [0.00, 0.29, 0.30], [0.0, 0.0, 1.0])

	# Squash wide on contact, overshoot tall, then two corrective steps.
	_add_step_track(animation, "BombWord:scale",
		[0.00, 0.29, 0.30, 0.35, 0.40, 0.45, 0.50, 0.58, 0.74, 0.90],
		[Vector2.ZERO, Vector2.ZERO, Vector2(1.45, 0.55), Vector2(0.84, 1.24),
		Vector2(1.10, 0.92), Vector2(0.97, 1.04), Vector2.ONE,
		Vector2(1.02, 0.98), Vector2(1.03, 1.02), Vector2(1.01, 1.01)])

	_add_step_track(animation, "VoyageWord:scale",
		[0.00, 0.29, 0.30, 0.36, 0.42, 0.48, 0.56, 0.72, 0.88],
		[Vector2.ONE, Vector2.ONE, Vector2(1.12, 0.86), Vector2(0.94, 1.07),
		Vector2(1.03, 0.98), Vector2.ONE,
		Vector2(0.98, 1.01), Vector2.ONE, Vector2(1.02, 0.98)])

	_add_step_track(animation, "FireBlast:modulate:a",
		[0.30, 0.46, 0.52, 0.58, 0.64],
		[1.0, 1.0, 0.7, 0.35, 0.0])

	# Debris clock runs in real seconds; _draw_shards quantises it to frames.
	var debris := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(debris, NodePath(".:blast_time"))
	animation.track_set_interpolation_type(debris, Animation.INTERPOLATION_LINEAR)
	animation.track_insert_key(debris, 0.00, 0.0)
	animation.track_insert_key(debris, 0.30, 0.0)
	animation.track_insert_key(debris, 0.95, 0.65)

	var method_track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(method_track, NodePath("."))
	animation.track_insert_key(method_track, 0.30, {"method": "_fire_blast", "args": []})

	var library := AnimationLibrary.new()
	library.add_animation("explosion", animation)
	library.add_animation("idle", _build_idle_animation())
	player.add_animation_library("", library)
	_anim = player
	if armed:
		return
	player.play("explosion")
	# The sting used to settle on a frozen badge; this picks up where it lands.
	player.queue("idle")


## Keeps the burst breathing once the sting is over, on the same "on twos" clock
## as everything else here. Stepped between a handful of held values rather than
## eased on purpose: _burst_runs rasterises and caches per quantised scale, so a
## smooth sine would build a fresh rasterisation almost every frame, while these
## four distinct values cost four cache entries for the life of the scene.
func _build_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.20
	animation.loop_mode = Animation.LOOP_LINEAR
	_add_step_track(animation, ".:burst_scale",
		[0.00, 0.20, 0.40, 0.60, 0.80, 1.00, 1.20],
		[1.0, 1.03, 1.05, 1.03, 1.0, 0.98, 1.0])

	# The words breathe with the burst, squashing wide as it expands. Kept to
	# ~3% so the lettering stays readable - this is idle life, not a sting.
	_add_step_track(animation, "BombWord:scale",
		[0.00, 0.20, 0.40, 0.60, 0.80, 1.00, 1.20],
		[Vector2.ONE, Vector2(1.02, 0.98), Vector2(1.03, 1.02), Vector2(1.01, 1.01),
		Vector2.ONE, Vector2(0.98, 1.01), Vector2.ONE])

	# VOYAGE runs the same cycle one step behind BOMB. Overlapping action: the
	# two words moving in lockstep would read as one rigid block sliding.
	_add_step_track(animation, "VoyageWord:scale",
		[0.00, 0.20, 0.40, 0.60, 0.80, 1.00, 1.20],
		[Vector2(0.98, 1.01), Vector2.ONE, Vector2(1.02, 0.98), Vector2(1.03, 1.02),
		Vector2(1.01, 1.01), Vector2.ONE, Vector2(0.98, 1.01)])

	# Only scale is animated. Position belongs to _apply_shake, and an overbright
	# modulate would do nothing here - this project is GL Compatibility with no
	# HDR 2D, so anything above 1.0 just clamps.
	return animation

## Inserts each pose twice - once holding the previous value right up to the
## change - so values snap between keys instead of easing through them.
func _add_step_track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for index in times.size():
		if index > 0:
			animation.track_insert_key(track, maxf(times[index] - HOLD, times[index - 1]), values[index - 1])
		animation.track_insert_key(track, times[index], values[index])

# --- pixel rasteriser ---------------------------------------------------------

func _star_limit(angle: float) -> float:
	var wave := 0.5 + 0.5 * cos(angle * BURST_SPIKES + 0.35)
	return lerpf(BURST_INNER, 1.0, pow(wave, 1.5))

## Burst scale only ever takes a handful of held values, so each rasterisation
## is built once and replayed as run-length rectangles.
func _burst_runs(value: float) -> Array:
	var key := int(roundf(value * 200.0))
	if not _burst_cache.has(key):
		_burst_cache[key] = _build_burst_runs(float(key) / 200.0)
	return _burst_cache[key]

func _build_burst_runs(value: float) -> Array:
	var runs: Array = []
	if value <= 0.01:
		return runs

	var rx := BURST_RX * value
	var ry := BURST_RY * value
	var cols := int(ceil(rx / PIXEL)) + 2
	var rows := int(ceil(ry / PIXEL)) + 2
	var width := cols * 2 + 1
	var height := rows * 2 + 1

	var tone := PackedByteArray()
	tone.resize(width * height)
	for j in height:
		var y := float(j - rows) * PIXEL
		for i in width:
			var x := float(i - cols) * PIXEL
			var u := x / rx
			var v := y / ry
			var radius := sqrt(u * u + v * v)
			if radius > 1.05:
				continue
			var limit := _star_limit(atan2(v, u))
			if radius > limit:
				continue
			var ratio := radius / limit
			if ratio < 0.5:
				tone[j * width + i] = 3
			elif ratio < 0.86:
				tone[j * width + i] = 2
			else:
				tone[j * width + i] = 4

	# One cell of ink around the silhouette keeps the chunky outline square.
	var shaded := tone.duplicate()
	for j in height:
		for i in width:
			if tone[j * width + i] != 0:
				continue
			if _is_filled(tone, width, height, i - 1, j) or _is_filled(tone, width, height, i + 1, j) \
					or _is_filled(tone, width, height, i, j - 1) or _is_filled(tone, width, height, i, j + 1):
				shaded[j * width + i] = 1

	for j in height:
		var start := 0
		var current := 0
		for i in range(width + 1):
			var cell := 0 if i == width else shaded[j * width + i]
			if cell == current:
				continue
			if current != 0:
				runs.append([
					Vector2(float(start - cols) * PIXEL - PIXEL * 0.5, float(j - rows) * PIXEL - PIXEL * 0.5),
					Vector2(float(i - start) * PIXEL, PIXEL),
					current,
				])
			start = i
			current = cell
	return runs

func _is_filled(tone: PackedByteArray, width: int, height: int, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= width or j >= height:
		return false
	return tone[j * width + i] != 0

func _seed_shards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x50FA
	_shards.clear()
	for index in SHARD_COUNT:
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(330.0, 640.0)
		_shards.append({
			"velocity": Vector2(cos(angle) * 1.5, sin(angle) * 0.95) * speed,
			"cells": 1 if rng.randf() < 0.72 else 2,
			"life": rng.randf_range(0.38, 0.62),
		})

# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if burst_scale <= 0.0:
		return
	var origin := _badge + shake_offset
	for run in _burst_runs(burst_scale):
		draw_rect(Rect2(origin + run[0], run[1]), TONE_COLORS[run[2]])

func _draw_overlay() -> void:
	var origin := _center + shake_offset
	if flash_alpha > 0.0:
		_draw_flash(_overlay, origin)
	if blast_time > 0.0:
		_draw_shards(_overlay, origin)

## Hard-edged blown-out ellipse, stepped on a double-width grid so the rim
## stays obviously blocky instead of curving.
func _draw_flash(canvas: CanvasItem, origin: Vector2) -> void:
	var rx := FLASH_RX * flash_alpha
	var ry := FLASH_RY * flash_alpha
	if ry < FLASH_BAND:
		return
	var color := Color(1.0, 1.0, 1.0, minf(1.0, flash_alpha))
	var rows := int(ceil(ry / FLASH_BAND))
	for j in range(-rows, rows + 1):
		var y := float(j) * FLASH_BAND
		var span := clampf(1.0 - pow(y / ry, 2.0), 0.0, 1.0)
		var cells := int(roundf(rx * sqrt(span) / FLASH_BAND))
		if cells <= 0:
			continue
		canvas.draw_rect(Rect2(
			origin.x - float(cells) * FLASH_BAND - FLASH_BAND * 0.5,
			origin.y + y - FLASH_BAND * 0.5,
			float(cells * 2 + 1) * FLASH_BAND,
			FLASH_BAND), color)

## Debris steps along on BLAST_FPS and lands on its own finer grid, so it pops
## from cell to cell instead of gliding.
func _draw_shards(canvas: CanvasItem, origin: Vector2) -> void:
	var elapsed := floorf(blast_time * BLAST_FPS) / BLAST_FPS
	for shard in _shards:
		var life: float = shard["life"]
		if elapsed >= life:
			continue
		var phase := elapsed / life
		var drag := 1.0 - 0.42 * phase
		var velocity: Vector2 = shard["velocity"]
		var spot := origin + velocity * elapsed * drag
		spot.y += SHARD_GRAVITY * elapsed * elapsed * 0.5
		spot = (spot / SHARD_PIXEL).floor() * SHARD_PIXEL
		var color := FLARE
		if phase > 0.6:
			color = MAGENTA
		elif phase > 0.25:
			color = BLAZE
		var extent := SHARD_PIXEL * float(shard["cells"])
		canvas.draw_rect(Rect2(spot, Vector2(extent, extent)), color)


## Cutscene hook: detonates BON -> BOMB on cue. A no-op once it is already running,
## so retriggering from a timeline cannot restart it mid-blast.
func fire() -> void:
	if _anim == null or _anim.is_playing():
		return
	_anim.play("explosion")
	_anim.queue("idle")
