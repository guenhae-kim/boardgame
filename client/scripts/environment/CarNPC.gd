class_name CamelCarNPC
extends Node3D

@export var speed := 0.055
@export var enabled := true
@export_range(0.0, 1.0, 0.01) var start_progress_ratio := 0.0


func _ready() -> void:
	# PathFollow3D rejects progress changes while an inherited scene is still
	# being instantiated. Deferring keeps the editor-authored start offset while
	# ensuring the follower is already inside the live tree.
	call_deferred("_apply_start_progress")


func _apply_start_progress() -> void:
	if get_parent() is PathFollow3D:
		(get_parent() as PathFollow3D).progress_ratio = start_progress_ratio

func _process(delta: float) -> void:
	if not enabled or not (get_parent() is PathFollow3D):
		return
	var follower := get_parent() as PathFollow3D
	if follower.get_parent() is Path3D and ((follower.get_parent() as Path3D).curve == null or (follower.get_parent() as Path3D).curve.get_baked_length() <= 0.01):
		return
	follower.progress_ratio = fmod(follower.progress_ratio + speed * delta, 1.0)
