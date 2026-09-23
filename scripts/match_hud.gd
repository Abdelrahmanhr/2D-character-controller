extends CanvasLayer

@onready var timer_block: HBoxContainer = $Header/TimerBlock
@onready var slot_template: Control = $Header/TimerBlock/TimerSlot
@onready var alive_label: Label = $Header/AliveBlock/AliveCount
@onready var kill_feed_container: VBoxContainer = $KillFeed
@onready var kill_feed_line_template: RichTextLabel = $KillFeed/LineTemplate

## One stacked kill-feed line with its own independent fade timer.
class KillFeedLine:
	var label: RichTextLabel
	var time_left: float

# Per-slot cache. Everything that does not change frame to frame - the styleboxes,
# the label theme overrides, the player colour - is built once here, at rebuild
# time. _process then only touches text and the two values that actually move.
class Slot:
	var root: Control
	var caption: Label
	var bar: ProgressBar
	var time: Label
	var lives: Label
	var bomb: BombController
	var player: Node
	var color: Color
	var fill_style: StyleBoxFlat
	var last_time_text: String = ""
	var last_lives: int = -1
	var last_urgency_band: int = -1
	var last_eliminated: bool = false
	var last_display_name: String = ""

## A quiet tick as a slot dims - it layers under the louder popup sting the
## eliminated player themselves hears, rather than reading as a second event.
@export var eliminated_sound: AudioStream = preload("res://resources/audio/Stunned.wav")
@export var eliminated_volume_db: float = -18.0
@export var eliminated_pitch: float = 0.8

const ELIMINATED_MODULATE := Color(0.5961, 0.5608, 0.3922, 0.75)
const URGENT_COLOR := Color(0.8667, 0.2157, 0.2706, 1.0)
const WARN_COLOR := Color(1, 0.4118, 0.3529, 1.0)

## Player-vs-player kills. %s/%s are killer, then victim.
const DUEL_PHRASES: Array[String] = [
	"%s yeeted %s into next week",
	"%s sent %s into orbit",
	"%s absolutely clotheslined %s",
	"%s turned %s into a frisbee",
	"%s gave %s a one-way ticket off the map",
	"%s punted %s clean off the stage",
	"%s introduced %s to the void",
	"%s bodied %s off the edge",
	"%s launched %s like a rocket",
	"%s said \"not today\" to %s",
	"%s sent %s to go touch grass. permanently",
	"%s dashed %s straight into retirement",
	"%s slam-dunked %s off the arena",
	"%s made %s do an unscheduled backflip into the abyss",
]

## Bomb-timer/safezone deaths with no recent attacker to credit. %s is the victim.
const SOLO_EXPLODE_PHRASES: Array[String] = [
	"%s went out with a bang",
	"%s forgot to defuse in time",
	"%s turned into confetti a little early",
	"%s got way too attached to that bomb",
	"%s discovered the bomb was not a toy",
	"%s learned fireworks hurt up close",
	"%s had an explosive personality today",
	"%s took the countdown personally",
	"%s became a cautionary tale about timers",
	"%s went out in a blaze of glory",
	"%s got the loudest wake-up call ever",
	"%s ended their run with a big finish",
]

## Falls/edge deaths with no recent attacker to credit. %s is the victim.
const SOLO_FALL_PHRASES: Array[String] = [
	"%s took an unscheduled dive",
	"%s forgot the floor was optional",
	"%s discovered gravity the hard way",
	"%s went for a swim in the void",
	"%s missed the landing entirely",
	"%s took the scenic route down",
	"%s decided the edge looked comfy",
	"%s just kept walking",
	"%s wandered off the map like it owed them money",
	"%s trusted the ground a little too much",
	"%s tripped into the abyss",
	"%s took the long way out",
]

const KILL_FEED_DURATION := 3.5
const KILL_FEED_MAX_LINES := 5

var _slots: Array[Slot] = []
var _bombs: Array[BombController] = []
var _dirty: bool = true
var _kill_feed_lines: Array[KillFeedLine] = []

func _ready() -> void:
	slot_template.visible = false
	kill_feed_line_template.visible = false
	MinigameDirector.alive_count_changed.connect(_on_alive_count_changed)
	# The roster only changes when a player registers or drops, and both paths go
	# through MinigameDirector._notify_alive_count(). Rebuild on that instead of
	# scanning the "players" group every single frame.
	MinigameDirector.alive_count_changed.connect(_mark_dirty)
	_on_alive_count_changed(MinigameDirector.get_alive_count(), MinigameDirector.get_total_players())

func _mark_dirty(_alive: int = 0, _total: int = 0) -> void:
	_dirty = true

func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_collect_bombs()
		_rebuild_slots()
	for slot in _slots:
		_update_slot(slot)
	_update_kill_feed(delta)

## Called by BombController._report_kill, already running identically on every
## peer since it rides the existing _do_player_died any_peer/call_local/reliable
## broadcast - no RPC of its own needed here. credit is {} for an environmental
## death (bomb timer, safe zone, unattributed fall) or {"name","color"} of
## whoever last stunned this player within the attribution window.
func report_kill(victim_name: String, victim_color: Color, cause: String, credit: Dictionary = {}) -> void:
	var victim_tag := _color_tag(victim_name, victim_color)
	var line: String
	if not credit.is_empty():
		var killer_tag := _color_tag(credit.get("name", "?"), credit.get("color", Color.WHITE))
		var phrase: String = DUEL_PHRASES[randi() % DUEL_PHRASES.size()]
		line = phrase % [killer_tag, victim_tag]
	else:
		var pool: Array[String] = SOLO_EXPLODE_PHRASES if cause == "explode" else SOLO_FALL_PHRASES
		var phrase: String = pool[randi() % pool.size()]
		line = phrase % [victim_tag]
	_push_kill_feed_line(line)

func _color_tag(display_name: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), display_name]

## New lines append at the end of KillFeed, closest to the bottom-left anchor (the
## container's alignment=END keeps a partial stack hugging that corner); older
## lines sit above. Each line tracks its own fade timer independently of the
## others, so a burst of kills stacks and each entry drops off on its own clock
## rather than the whole stack resetting or clearing together.
func _push_kill_feed_line(text: String) -> void:
	if _kill_feed_lines.size() >= KILL_FEED_MAX_LINES:
		_pop_oldest_kill_feed_line()
	var label := kill_feed_line_template.duplicate() as RichTextLabel
	label.visible = true
	label.text = text
	kill_feed_container.add_child(label)
	var entry := KillFeedLine.new()
	entry.label = label
	entry.time_left = KILL_FEED_DURATION
	_kill_feed_lines.append(entry)

func _pop_oldest_kill_feed_line() -> void:
	if _kill_feed_lines.is_empty():
		return
	var oldest: KillFeedLine = _kill_feed_lines.pop_front()
	if is_instance_valid(oldest.label):
		oldest.label.queue_free()

func _update_kill_feed(delta: float) -> void:
	if _kill_feed_lines.is_empty():
		return
	var expired: Array[KillFeedLine] = []
	for entry in _kill_feed_lines:
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			expired.append(entry)
	for entry in expired:
		_kill_feed_lines.erase(entry)
		if is_instance_valid(entry.label):
			entry.label.queue_free()

func _collect_bombs() -> void:
	_bombs.clear()
	for node in get_tree().get_nodes_in_group("players"):
		var bomb := node.get_node_or_null("BombController") as BombController
		if bomb:
			_bombs.append(bomb)
	_bombs.sort_custom(_compare_by_player_name)

func _compare_by_player_name(a: BombController, b: BombController) -> bool:
	return a.get_parent().name.to_int() < b.get_parent().name.to_int()

func _rebuild_slots() -> void:
	for child in timer_block.get_children():
		if child != slot_template:
			child.queue_free()
	_slots.clear()
	for bomb in _bombs:
		var root := slot_template.duplicate() as Control
		root.visible = true
		timer_block.add_child(root)

		var slot := Slot.new()
		slot.root = root
		slot.caption = root.get_node("BombCaption") as Label
		slot.bar = root.get_node("BombBar") as ProgressBar
		slot.time = root.get_node("BombTime") as Label
		slot.lives = root.get_node("LivesLabel") as Label
		slot.bomb = bomb
		slot.player = bomb.get_parent()
		slot.color = bomb.get_player_color()

		# Static styling, applied once -- the caption text itself isn't, though (see
		# _update_slot): a Steam name can arrive a beat after this rebuild via
		# Networking's synced RPC, so it starts on the P<n> fallback and gets
		# corrected in place once/if the real name shows up.
		slot.last_display_name = bomb.get_player_display_name()
		slot.caption.text = slot.last_display_name
		_apply_neon_label(slot.caption, slot.color)
		_apply_neon_label(slot.time, slot.color)
		_apply_neon_label(slot.lives, slot.color)

		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0, 0, 0, 0.95)
		bg_style.set_border_width_all(1)
		bg_style.border_color = Color(slot.color.r, slot.color.g, slot.color.b, 0.55)
		bg_style.set_corner_radius_all(2)
		slot.bar.add_theme_stylebox_override("background", bg_style)

		# One fill stylebox per slot, recoloured in place when the urgency band changes.
		slot.fill_style = StyleBoxFlat.new()
		slot.fill_style.set_corner_radius_all(1)
		slot.fill_style.shadow_size = 2
		slot.bar.add_theme_stylebox_override("fill", slot.fill_style)
		slot.bar.max_value = maxf(bomb.bomb_time, 0.001)

		_slots.append(slot)

func _update_slot(slot: Slot) -> void:
	var bomb := slot.bomb
	if bomb == null or not is_instance_valid(bomb):
		return
	var display_name := bomb.get_player_display_name()
	if display_name != slot.last_display_name:
		slot.last_display_name = display_name
		slot.caption.text = display_name

	var max_time: float = maxf(bomb.bomb_time, 0.001)
	var time_left: float = clampf(bomb.time_left, 0.0, max_time)
	slot.bar.value = time_left

	var time_text := "%.1f" % time_left
	if time_text != slot.last_time_text:
		slot.last_time_text = time_text
		slot.time.text = time_text

	var lives: int = bomb.get_lives_remaining()
	if lives != slot.last_lives:
		slot.last_lives = lives
		slot.lives.text = "x%d" % lives

	# The bar only has three colour states, so only repaint when it crosses a band.
	var urgency: float = clampf(time_left / max_time, 0.0, 1.0)
	var band: int = 0 if urgency < 0.25 else (1 if urgency < 0.5 else 2)
	if band != slot.last_urgency_band:
		slot.last_urgency_band = band
		var bar_color := slot.color
		if band == 0:
			bar_color = slot.color.lerp(URGENT_COLOR, 0.65)
		elif band == 1:
			bar_color = slot.color.lerp(WARN_COLOR, 0.4)
		slot.fill_style.bg_color = bar_color
		slot.fill_style.shadow_color = Color(bar_color.r, bar_color.g, bar_color.b, 0.35)

	var eliminated := false
	if is_instance_valid(slot.player) and slot.player is CharacterBody2D:
		eliminated = slot.player.is_dead
	if eliminated != slot.last_eliminated:
		slot.last_eliminated = eliminated
		slot.root.modulate = ELIMINATED_MODULATE if eliminated else Color.WHITE
		# Only on the way out - this flag also flips back on a roster rebuild,
		# which has to stay silent.
		if eliminated:
			SfxManager.play(eliminated_sound, eliminated_volume_db, 0.0, eliminated_pitch)

func _apply_neon_label(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 3)

func _on_alive_count_changed(alive: int, total: int) -> void:
	var shown_total: int = maxi(total, alive)
	alive_label.text = "%d / %d" % [alive, shown_total]
