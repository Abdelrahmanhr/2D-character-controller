extends CanvasLayer

@onready var timer_block: HBoxContainer = $Header/TimerBlock
@onready var slot_template: Control = $Header/TimerBlock/TimerSlot
@onready var alive_label: Label = $Header/AliveBlock/AliveCount

var _slots: Array[Dictionary] = []

func _ready() -> void:
	slot_template.visible = false
	MinigameDirector.alive_count_changed.connect(_on_alive_count_changed)
	_on_alive_count_changed(MinigameDirector.get_alive_count(), MinigameDirector.get_total_players())

func _process(_delta: float) -> void:
	var bombs := _collect_bombs()
	if _needs_rebuild(bombs):
		_rebuild_slots(bombs)
	for i in _slots.size():
		_update_slot(_slots[i], bombs[i])

func _collect_bombs() -> Array[BombController]:
	var bombs: Array[BombController] = []
	for node in get_tree().get_nodes_in_group("players"):
		var bomb := node.get_node_or_null("BombController") as BombController
		if bomb:
			bombs.append(bomb)
	bombs.sort_custom(func(a: BombController, b: BombController) -> bool:
		return a.get_parent().name.to_int() < b.get_parent().name.to_int()
	)
	return bombs

func _needs_rebuild(bombs: Array[BombController]) -> bool:
	if bombs.size() != _slots.size():
		return true
	for i in bombs.size():
		if _slots[i].get("bomb") != bombs[i]:
			return true
	return false

func _rebuild_slots(bombs: Array[BombController]) -> void:
	for child in timer_block.get_children():
		if child != slot_template:
			child.queue_free()
	_slots.clear()
	for bomb in bombs:
		var slot := slot_template.duplicate() as Control
		slot.visible = true
		timer_block.add_child(slot)
		_slots.append({
			"root": slot,
			"caption": slot.get_node("BombCaption") as Label,
			"bar": slot.get_node("BombBar") as ProgressBar,
			"time": slot.get_node("BombTime") as Label,
			"bomb": bomb,
		})

func _update_slot(slot: Dictionary, bomb: BombController) -> void:
	if bomb == null or not is_instance_valid(bomb):
		return
	var color := bomb.get_player_color()
	var max_time: float = maxf(bomb.bomb_time, 0.001)
	var time_left: float = clampf(bomb.time_left, 0.0, max_time)
	var caption := slot.caption as Label
	var bar := slot.bar as ProgressBar
	var time_label := slot.time as Label
	var root := slot.root as Control
	caption.text = "P%d" % (bomb.get_slot_index() + 1)
	_apply_neon_label(caption, color)
	bar.max_value = max_time
	bar.value = time_left
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.05, 0.95)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color(color.r, color.g, color.b, 0.55)
	bg_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_style)
	time_label.text = "%.1f" % time_left
	_apply_neon_label(time_label, color)
	var urgency := clampf(time_left / max_time, 0.0, 1.0)
	var bar_color := color
	if urgency < 0.25:
		bar_color = color.lerp(Color(1.0, 0.25, 0.08, 1.0), 0.65)
	elif urgency < 0.5:
		bar_color = color.lerp(Color(1.0, 0.55, 0.1, 1.0), 0.4)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = bar_color
	fill_style.set_corner_radius_all(1)
	fill_style.shadow_color = Color(bar_color.r, bar_color.g, bar_color.b, 0.35)
	fill_style.shadow_size = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	var player := bomb.get_parent()
	var eliminated := false
	if player is CharacterBody2D:
		eliminated = player.is_dead
	root.modulate = Color(0.55, 0.55, 0.55, 0.75) if eliminated else Color.WHITE

func _apply_neon_label(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 3)

func _on_alive_count_changed(alive: int, total: int) -> void:
	var shown_total: int = maxi(total, alive)
	alive_label.text = "%d / %d" % [alive, shown_total]
