extends CanvasLayer

@onready var timer_block: HBoxContainer = $Header/TimerBlock
@onready var slot_template: Control = $Header/TimerBlock/TimerSlot
@onready var alive_label: Label = $Header/AliveBlock/AliveCount

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

var _slots: Array[Slot] = []
var _bombs: Array[BombController] = []
var _dirty: bool = true

func _ready() -> void:
	slot_template.visible = false
	MinigameDirector.alive_count_changed.connect(_on_alive_count_changed)
	# The roster only changes when a player registers or drops, and both paths go
	# through MinigameDirector._notify_alive_count(). Rebuild on that instead of
	# scanning the "players" group every single frame.
	MinigameDirector.alive_count_changed.connect(_mark_dirty)
	_on_alive_count_changed(MinigameDirector.get_alive_count(), MinigameDirector.get_total_players())

func _mark_dirty(_alive: int = 0, _total: int = 0) -> void:
	_dirty = true

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_collect_bombs()
		_rebuild_slots()
	for slot in _slots:
		_update_slot(slot)

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
