extends CanvasLayer

enum Outcome { WIN, LOSE, DRAW }

## Result stings. These reuse in-match cues pitched down, so the result reads as
## a heavier version of a sound the player already knows. Deliberately mixed
## below the action (the loud one-shots in this game sit at -10 to -6) and with
## no pitch variance - a result should sound identical every time.
@export var win_sound: AudioStream = preload("res://resources/audio/Minigame Complete .wav")
@export var lose_sound: AudioStream = preload("res://resources/audio/Time Penalty.wav")
@export var draw_sound: AudioStream = preload("res://resources/audio/Bonus Time.wav")
@export var win_volume_db: float = -12.0
@export var lose_volume_db: float = -12.0
@export var draw_volume_db: float = -13.0
@export var win_pitch: float = 0.9
@export var lose_pitch: float = 0.75
@export var draw_pitch: float = 0.85

@onready var title_label: Label = $Panel/Box/Title
@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Panel
@onready var stats_panel: Panel = $StatsPanel
@onready var stats_rows: Array[HBoxContainer] = [$StatsPanel/StatsBox/StatRow1, $StatsPanel/StatsBox/StatRow2, $StatsPanel/StatsBox/StatRow3, $StatsPanel/StatsBox/StatRow4]

## One row per tracked player: display name/color from the same source every other
## per-player UI (kill feed, scoreboard, lobby) already uses, kills/survival time
## from MinigameDirector's match stats, which are themselves only ever written from
## BombController._report_kill - the exact call the kill feed reads from - so this
## can't drift from what the kill feed showed during the match.
class StatEntry:
	var display_name: String
	var color: Color
	var kills: int
	var survival: float

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Panel/Box/RestartButton.pressed.connect(_on_restart)
	$Panel/Box/MainMenuButton.pressed.connect(_on_main_menu)
	$Panel/Box/ExitButton.pressed.connect(_on_exit)

## The results own the escape key, so the pause menu cannot stack on top of them
## now that the tree is no longer paused underneath.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

func set_result(title: String, color: Color, outcome: int = Outcome.WIN) -> void:
	title_label.text = title
	title_label.add_theme_color_override("font_color", color)
	_populate_stats()
	_play_entrance(outcome)

func _play_entrance(outcome: int) -> void:
	var elements: Array[Control] = [
		$Panel/TitleBar, title_label,
		$Panel/Box/RestartButton, $Panel/Box/MainMenuButton, $Panel/Box/ExitButton,
		$StatsPanel/StatsTitle,
	]
	for row in stats_rows:
		if row.visible:
			elements.append(row)
	UICascade.reset(elements)
	dim.modulate.a = 0.0
	# One frame so the VBoxContainer has sized its children; scaling around a
	# pivot of (0,0) would otherwise grow each row out of its top-left corner.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	create_tween().tween_property(dim, "modulate:a", 1.0, 0.18)
	UICascade.slam_panel(panel)
	UICascade.slam_panel(stats_panel)
	_shake_camera()
	_spawn_result_fx(outcome)
	UICascade.play(elements, UICascade.PANEL_SLAM * 0.55)

	await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		$Panel/Box/RestartButton.grab_focus()

## Sorted highest-survival-time first (kills as a tiebreak): in this last-man-
## standing mode the winner (or every survivor in a draw) always has the longest
## survival time by definition, so this reads winner-first without needing
## winner_peer_id threaded in here separately.
func _populate_stats() -> void:
	var entries: Array[StatEntry] = []
	for key in MinigameDirector.get_tracked_player_keys():
		var entry := StatEntry.new()
		var info := _resolve_player_info(int(key))
		entry.display_name = info["name"]
		entry.color = info["color"]
		entry.kills = MinigameDirector.get_kill_count(int(key))
		entry.survival = MinigameDirector.get_survival_seconds(int(key))
		entries.append(entry)
	entries.sort_custom(_compare_stat_entries)

	for i in stats_rows.size():
		var row := stats_rows[i]
		if i >= entries.size():
			row.visible = false
			continue
		row.visible = true
		var entry := entries[i]
		var name_label: Label = row.get_node("Name")
		var kills_label: Label = row.get_node("Kills")
		var time_label: Label = row.get_node("Time")
		name_label.text = entry.display_name
		name_label.add_theme_color_override("font_color", entry.color)
		kills_label.text = str(entry.kills)
		time_label.text = _format_survival(entry.survival)


func _compare_stat_entries(a: StatEntry, b: StatEntry) -> bool:
	if a.survival != b.survival:
		return a.survival > b.survival
	return a.kills > b.kills


func _format_survival(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


## Player nodes stay in the tree (faded, not freed) through the outro (see
## arena_base.gd's _send_off_the_fallen), so their name/color -- the same
## BombController getters the kill feed, scoreboard and lobby all already use --
## are still resolvable live here rather than needing a separate snapshot.
func _resolve_player_info(key: int) -> Dictionary:
	for node in get_tree().get_nodes_in_group("players"):
		if node.name.to_int() != key:
			continue
		var bomb := node.get_node_or_null("BombController") as BombController
		if bomb:
			return {"name": bomb.get_player_display_name(), "color": bomb.get_player_color()}
	return {"name": "P?", "color": Color.WHITE}

func _shake_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.18)

func _spawn_result_fx(outcome: int) -> void:
	var rect := panel.get_global_rect()
	match outcome:
		Outcome.WIN:
			UIParticles.win(self, rect)
			SfxManager.play(win_sound, win_volume_db, 0.0, win_pitch)
		Outcome.DRAW:
			UIParticles.lose(self, rect, UIParticles.FLARE)
			SfxManager.play(draw_sound, draw_volume_db, 0.0, draw_pitch)
		_:
			UIParticles.lose(self, rect)
			SfxManager.play(lose_sound, lose_volume_db, 0.0, lose_pitch)

func _on_restart() -> void:
	get_tree().paused = false
	Networking.restart_game()

func _on_main_menu() -> void:
	Networking.leave_lobby()
	get_tree().paused = false
	SceneTransition.circle_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	Networking.leave_lobby()
	get_tree().quit()
