class_name CamelCarNPC
extends Node3D

@export var speed := 0.055
@export var enabled := true

func _process(delta: float) -> void:
	if not enabled or not (get_parent() is PathFollow3D):
		return
	var follower := get_parent() as PathFollow3D
	if follower.get_parent() is Path3D and ((follower.get_parent() as Path3D).curve == null or (follower.get_parent() as Path3D).curve.get_baked_length() <= 0.01):
		return
	follower.progress_ratio = fmod(follower.progress_ratio + speed * delta, 1.0)
