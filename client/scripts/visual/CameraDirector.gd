class_name CamelCameraDirector
extends Node

enum CameraState { BOARD_OVERVIEW, DICE_FOCUS, PIECE_FOCUS, COMPONENT_FOCUS }

var camera: Camera3D
var _follow_tween: Tween
var state := CameraState.BOARD_OVERVIEW
var _dragging := false
var _overview_offset := Vector3.ZERO
var _overview_zoom := 1.0


func setup(target_camera: Camera3D) -> void:
	camera = target_camera
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_board_pose()


func show_board(duration: float = 0.55) -> void:
	state = CameraState.BOARD_OVERVIEW
	camera.fov = 60.0 if _is_portrait() else 88.0
	var pose := _board_pose()
	var target := (pose[1] as Vector3) + _overview_offset
	var position := target + ((pose[0] as Vector3) - (pose[1] as Vector3)) * _overview_zoom
	await _move_to(position, target, duration)


func _board_pose() -> Array:
	if _is_portrait():
		# A slight diagonal top-down view turns the wide tabletop footprint into
		# an almost square silhouette, using the tall mobile play area without
		# cropping the prediction and betting zones at either side.
		return [Vector3(3.0, 18.0, 3.0), Vector3(0, 0, 0.3)]
	return [Vector3(0, 12.2, 14.2), Vector3(0, 0, -0.35)]


func _apply_board_pose() -> void:
	if camera == null:
		return
	var pose := _board_pose()
	camera.fov = 60.0 if _is_portrait() else 88.0
	camera.global_transform = Transform3D(Basis.IDENTITY, pose[0]).looking_at(pose[1], Vector3.UP)


func _is_portrait() -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	return viewport_size.y > viewport_size.x


func _on_viewport_size_changed() -> void:
	# Orientation changes must only reframe the camera; game state is untouched.
	_apply_board_pose()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or state != CameraState.BOARD_OVERVIEW:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
		elif mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_overview_zoom = clampf(_overview_zoom + (-0.08 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 0.08), 0.72, 1.35)
			_apply_manual_overview()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_overview_offset += Vector3(-motion.relative.x, 0, -motion.relative.y) * 0.006 * _overview_zoom
		_overview_offset.x = clampf(_overview_offset.x, -3.0, 3.0)
		_overview_offset.z = clampf(_overview_offset.z, -3.0, 3.0)
		_apply_manual_overview()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_overview_offset += Vector3(-drag.relative.x, 0, -drag.relative.y) * 0.006 * _overview_zoom
		_apply_manual_overview()
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_overview_zoom = clampf(_overview_zoom / magnify.factor, 0.72, 1.35)
		_apply_manual_overview()


func _apply_manual_overview() -> void:
	var pose := _board_pose()
	var target := (pose[1] as Vector3) + _overview_offset
	var position := target + ((pose[0] as Vector3) - (pose[1] as Vector3)) * _overview_zoom
	camera.global_transform = Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)


func show_dice(dice_position: Vector3, duration: float = 0.55) -> void:
	state = CameraState.DICE_FOCUS
	await _move_to(dice_position + Vector3(5.4, 5.6, 7.4), dice_position + Vector3(0, 2.0, 0), duration)


func focus_space(space_position: Vector3, duration: float = 0.48) -> void:
	state = CameraState.PIECE_FOCUS
	await _move_to(space_position + Vector3(4.2, 4.0, 5.8), space_position + Vector3(0, 0.7, 0), duration)


func show_result(space_position: Vector3) -> void:
	await focus_space(space_position, 0.28)
	await get_tree().create_timer(0.65).timeout


func focus_component(component_position: Vector3, duration: float = 0.42) -> void:
	state = CameraState.COMPONENT_FOCUS
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
