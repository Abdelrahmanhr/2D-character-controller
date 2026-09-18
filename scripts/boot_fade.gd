extends Control

## The very first thing the game shows (see project.godot's run/main_scene):
## starts on a solid black screen, holds a "made with Godot" credit for a few
## seconds, fades it back out to black, then hands off to the intro cutscene.
## The handoff reuses SceneTransition, the same system every other scene change
## in the project already goes through, rather than a bare change_scene_to_file.

const INTRO_SCENE := "res://scenes/intro_cutscene.tscn"

@export var initial_delay: float = 0.6
@export var fade_in_duration: float = 0.8
@export var hold_duration: float = 3.0
@export var fade_out_duration: float = 0.6

@onready var godot_label: Label = $GodotLabel


func _ready() -> void:
	godot_label.modulate.a = 0.0
	await get_tree().create_timer(initial_delay).timeout
	var fade_in := create_tween()
	fade_in.tween_property(godot_label, "modulate:a", 1.0, fade_in_duration)
	await fade_in.finished
	await get_tree().create_timer(hold_duration).timeout
	var fade_out := create_tween()
	fade_out.tween_property(godot_label, "modulate:a", 0.0, fade_out_duration)
	await fade_out.finished
	SceneTransition.circle_to(INTRO_SCENE)
