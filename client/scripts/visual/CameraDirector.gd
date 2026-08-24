class_name CamelCameraDirector
extends Node

var camera: Camera3D
var _follow_tween: Tween


func setup(target_camera: Camera3D) -> void:
	camera = target_camera
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_board_pose()


func show_board(duration: float = 0.55) -> void:
	camera.fov = 72.0 if _is_portrait() else 88.0
	var pose := _board_pose()
	await _move_to(pose[0], pose[1], duration)


func _board_pose() -> Array:
	if _is_portrait():
		# Portrait UI occupies the top/bottom edges. Aim toward the near half of
		# the table so the board is framed in the large playable middle area.
		return [Vector3(0, 13.8, 6.5), Vector3(0, 0, 1.5)]
	return [Vector3(0, 12.2, 14.2), Vector3(0, 0, -0.35)]


func _apply_board_pose() -> void:
	if camera == null:
		return
	var pose := _board_pose()
	camera.fov = 72.0 if _is_portrait() else 88.0
	camera.global_transform = Transform3D(Basis.IDENTITY, pose[0]).looking_at(pose[1], Vector3.UP)


func _is_portrait() -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	return viewport_size.y > viewport_size.x


func _on_viewport_size_changed() -> void:
	# Orientation changes must only reframe the camera; game state is untouched.
	_apply_board_pose()


func show_dice(dice_position: Vector3, duration: float = 0.55) -> void:
	await _move_to(dice_position + Vector3(5.4, 5.6, 7.4), dice_position + Vector3(0, 2.0, 0), duration)


func focus_space(space_position: Vector3, duration: float = 0.48) -> void:
	await _move_to(space_position + Vector3(4.2, 4.0, 5.8), space_position + Vector3(0, 0.7, 0), duration)


func show_result(space_position: Vector3) -> void:
	await focus_space(space_position, 0.28)
	await get_tree().create_timer(0.65).timeout


func focus_component(component_position: Vector3, duration: float = 0.42) -> void:
	await _move_to(component_position + Vector3(3.2, 3.6, 5.0), component_position + Vector3(0, 0.3, 0), duration)


func show_history(history_position: Vector3) -> void:
	await _move_to(history_position + Vector3(3.8, 4.2, 5.2), history_position, 0.4)


func follow_space(space_position: Vector3) -> void:
	if camera == null:
		return
	if _follow_tween != null and _follow_tween.is_valid():
		_follow_tween.kill()
	var camera_position := space_position + Vector3(4.2, 4.0, 5.8)
	var target_transform := Transform3D(Basis.IDENTITY, camera_position).looking_at(space_position + Vector3(0, 0.7, 0), Vector3.UP)
	_follow_tween = create_tween()
	_follow_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_follow_tween.tween_property(camera, "global_transform", target_transform, 0.24)


func _move_to(camera_position: Vector3, look_target: Vector3, duration: float) -> void:
	if camera == null:
		return
	if _follow_tween != null and _follow_tween.is_valid():
		_follow_tween.kill()
	var target_transform := Transform3D(Basis.IDENTITY, camera_position).looking_at(look_target, Vector3.UP)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "global_transform", target_transform, duration)
	await tween.finished
