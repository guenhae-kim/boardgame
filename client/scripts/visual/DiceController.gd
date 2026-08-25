class_name CamelDiceController
extends Node3D

signal pyramid_gesture_started
signal pyramid_gesture_released(throw_strength: float)
signal collision_sound_requested(strength: float)

const FACE_NORMALS := {
	1: [Vector3.UP, Vector3.DOWN],
	2: [Vector3.RIGHT, Vector3.LEFT],
	3: [Vector3.FORWARD, Vector3.BACK],
}

var die: RigidBody3D
var _rng := RandomNumberGenerator.new()
var _die_material: StandardMaterial3D
var _pyramid: Node3D
var _hatch: MeshInstance3D
var _pyramid_hit_area: Area3D
var gesture_enabled := false
var _gesture_holding := false
var _gesture_start := Vector2.ZERO
var _gesture_last := Vector2.ZERO
var _shake_distance := 0.0
var _last_collision_msec := 0


func _ready() -> void:
	_rng.randomize()
	_build_arena()
	_build_pyramid()
	_build_die()


func play_roll(die_id: String, forced_result: int = 0, throw_strength: float = 1.0) -> int:
	throw_strength = clampf(throw_strength, 1.0, 3.4)
	_set_die_color(die_id)
	die.freeze = true
	die.visible = false
	die.position = Vector3(0, 2.72, 0)
	die.rotation = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	await _release_from_pyramid(throw_strength)
	die.visible = true
	die.freeze = false
	# The die drops through the pyramid hatch; lateral force and torque make it
	# bounce and roll while the tall arena walls keep it contained.
	var lateral_scale := 1.35 + (throw_strength - 1.0) * 0.72
	die.apply_central_impulse(Vector3(
		_rng.randf_range(-2.4, 2.4) * lateral_scale,
		_rng.randf_range(1.2, 2.4) - (throw_strength - 1.0) * 0.4,
		_rng.randf_range(-2.0, 2.0) * lateral_scale
	))
	die.apply_torque_impulse(Vector3(
		_rng.randf_range(9.0, 14.0),
		_rng.randf_range(8.0, 13.0),
		_rng.randf_range(9.0, 14.0)
	) * throw_strength)

	var elapsed := 0.0
	var stable := 0.0
	# Always show a readable tumble. Previously a lucky early collision could end
	# the loop almost immediately, while a fast die was snapped to the server
	# result at the timeout. Both cases made the visible roll feel unrelated.
	while elapsed < 1.05 and (elapsed < 0.72 or stable < 0.14):
		await get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		elapsed += delta
		if die.position.y < -0.7 or absf(die.position.x) > 3.75 or absf(die.position.z) > 2.75:
			_recover_inside_arena()
		if die.linear_velocity.length() < 0.12 and die.angular_velocity.length() < 0.16:
			stable += delta
		else:
			stable = 0.0
	_hatch.scale.x = 1.0
	var result := _read_top_face()
	if forced_result in [1, 2, 3]:
		result = forced_result
	await _settle_to_result(result)
	await get_tree().create_timer(0.06).timeout
	return result


func hide_result_die() -> void:
	die.visible = false


func _read_top_face() -> int:
	var best_result := 1
	var best_dot := -INF
	for result in FACE_NORMALS:
		for local_normal in FACE_NORMALS[result]:
			var world_normal: Vector3 = die.global_basis * local_normal
			if world_normal.dot(Vector3.UP) > best_dot:
				best_dot = world_normal.dot(Vector3.UP)
				best_result = int(result)
	return best_result


func _orient_top(result: int) -> void:
	die.rotation = _target_rotation(result)


func _target_rotation(result: int) -> Vector3:
	match result:
		2:
			return Vector3(0, 0, -PI * 0.5)
		3:
			return Vector3(PI * 0.5, 0, 0)
		_:
			return Vector3.ZERO


func _settle_to_result(result: int) -> void:
	# The authority already chose the result so every phone must show the same
	# value. Continue the visible angular motion into a short final hop and land
	# on that exact face instead of teleporting the rotation.
	var current_rotation := die.rotation
	var spin_direction := -1.0 if _rng.randi() % 2 == 0 else 1.0
	var target_rotation := _target_rotation(result)
	var animated_target := target_rotation + Vector3(TAU * spin_direction, TAU, TAU * -spin_direction)
	var floor_y := maxf(0.53, die.position.y)
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	die.freeze = true
	die.rotation = current_rotation
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(die, "position:y", floor_y + 0.20, 0.11)
	tween.parallel().tween_property(die, "rotation", current_rotation.lerp(animated_target, 0.58), 0.11)
	tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(die, "position:y", 0.53, 0.17)
	tween.parallel().tween_property(die, "rotation", animated_target, 0.17)
	await tween.finished
	die.rotation = target_rotation
	die.position.y = 0.53


func _build_arena() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.input_ray_pickable = false
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.25, 6.0)
	floor_mesh.mesh = mesh
	floor_mesh.position.y = -0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e7d6ae")
	material.roughness = 0.92
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	collision.position.y = -0.12
	floor_body.add_child(collision)
	add_child(floor_body)
	for wall_data in [
		[Vector3(0, 1.65, -3.0), Vector3(8.0, 3.3, 0.25)],
		[Vector3(0, 1.65, 3.0), Vector3(8.0, 3.3, 0.25)],
		[Vector3(-4.0, 1.65, 0), Vector3(0.25, 3.3, 6.0)],
		[Vector3(4.0, 1.65, 0), Vector3(0.25, 3.3, 6.0)],
	]:
		var wall := StaticBody3D.new()
		wall.input_ray_pickable = false
		var wall_collision := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = wall_data[1]
		wall_collision.shape = wall_shape
		wall.position = wall_data[0]
		wall.add_child(wall_collision)
		# Keep the full-height collision, but render it as an opaque low rail plus
		# a transparent acrylic upper guard so the rolling die stays visible.
		var full_size := wall_data[1] as Vector3
		var lower_mesh := MeshInstance3D.new()
		var lower_box := BoxMesh.new()
		lower_box.size = Vector3(full_size.x, 0.46, full_size.z)
		lower_mesh.mesh = lower_box
		lower_mesh.position.y = -1.42
		var lower_material := StandardMaterial3D.new()
		lower_material.albedo_color = Color("72513b")
		lower_mesh.material_override = lower_material
		lower_mesh.visible = false
		wall.add_child(lower_mesh)
		var upper_mesh := MeshInstance3D.new()
		var upper_box := BoxMesh.new()
		upper_box.size = Vector3(full_size.x, 2.84, full_size.z)
		upper_mesh.mesh = upper_box
		upper_mesh.position.y = 0.23
		var acrylic := StandardMaterial3D.new()
		acrylic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		acrylic.albedo_color = Color(0.58, 0.84, 0.94, 0.18)
		acrylic.metallic = 0.05
		acrylic.roughness = 0.18
		acrylic.cull_mode = BaseMaterial3D.CULL_DISABLED
		upper_mesh.material_override = acrylic
		upper_mesh.visible = false
		wall.add_child(upper_mesh)
		add_child(wall)
	# Invisible ceiling is only a last safety net for extreme torque.
	var ceiling := StaticBody3D.new()
	ceiling.input_ray_pickable = false
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(8.0, 0.2, 6.0)
	ceiling_collision.shape = ceiling_shape
	ceiling.position.y = 6.2
	ceiling.add_child(ceiling_collision)
	add_child(ceiling)
	_build_bumpers()


func _build_pyramid() -> void:
	_pyramid = Node3D.new()
	_pyramid.position.y = 4.25
	var shell := MeshInstance3D.new()
	var pyramid_mesh := CylinderMesh.new()
	pyramid_mesh.radial_segments = 4
	pyramid_mesh.rings = 1
	pyramid_mesh.top_radius = 2.15
	pyramid_mesh.bottom_radius = 0.68
	pyramid_mesh.height = 3.0
	shell.mesh = pyramid_mesh
	shell.rotation.y = PI * 0.25
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color("d8a441")
	shell_material.metallic = 0.18
	shell_material.roughness = 0.48
	shell.material_override = shell_material
	_pyramid.add_child(shell)
	_hatch = MeshInstance3D.new()
	var hatch_mesh := BoxMesh.new()
	hatch_mesh.size = Vector3(1.15, 0.12, 1.15)
	_hatch.mesh = hatch_mesh
	_hatch.position.y = -1.53
	var hatch_material := StandardMaterial3D.new()
	hatch_material.albedo_color = Color("72512a")
	_hatch.material_override = hatch_material
	_pyramid.add_child(_hatch)
	var instruction := Label3D.new()
	instruction.text = "잡고 흔들기 ↓"
	instruction.font_size = 44
	instruction.outline_size = 10
	instruction.position = Vector3(0, 1.85, 0)
	instruction.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pyramid.add_child(instruction)
	# Online play now uses the tactile lower-right ROLL control. Keep these
	# internal nodes only so the dice-release API stays compatible; the former
	# giant machine must never cover the board plaza.
	_pyramid.visible = false
	add_child(_pyramid)
	_pyramid_hit_area = Area3D.new()
	_pyramid_hit_area.input_ray_pickable = false
	_pyramid_hit_area.collision_layer = 2
	_pyramid_hit_area.collision_mask = 0
	_pyramid_hit_area.position.y = 4.25
	var hit_shape_node := CollisionShape3D.new()
	var hit_shape := CylinderShape3D.new()
	hit_shape.radius = 2.35
	hit_shape.height = 3.25
	hit_shape_node.shape = hit_shape
	_pyramid_hit_area.add_child(hit_shape_node)
	_pyramid_hit_area.input_event.connect(_on_pyramid_input_event)
	_pyramid_hit_area.mouse_entered.connect(_on_pyramid_mouse_entered)
	_pyramid_hit_area.mouse_exited.connect(_on_pyramid_mouse_exited)
	add_child(_pyramid_hit_area)


func _release_from_pyramid(throw_strength: float) -> void:
	_hatch.scale.x = 1.0
	_pyramid.scale = Vector3.ONE
	# A very short hidden shuffle leaves Random Dice Selection independent from
	# whichever visible machine model replaces this presentation in the future.
	await get_tree().create_timer(0.08 / sqrt(throw_strength)).timeout
	_hatch.scale.x = 0.05


func _on_pyramid_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not gesture_enabled or _gesture_holding:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_gesture(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		_begin_gesture(event.position)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _gesture_holding and gesture_enabled:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _screen_hits_pyramid(event.position):
				_begin_gesture(event.position)
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventScreenTouch and event.pressed:
			if _screen_hits_pyramid(event.position):
				_begin_gesture(event.position)
				get_viewport().set_input_as_handled()
				return
	if not _gesture_holding:
		return
	if event is InputEventMouseMotion:
		_update_gesture(event.position, event.relative)
	elif event is InputEventScreenDrag:
		_update_gesture(event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_gesture(event.position)
	elif event is InputEventScreenTouch and not event.pressed:
		_finish_gesture(event.position)


func _begin_gesture(screen_position: Vector2) -> void:
	_gesture_holding = true
	_gesture_start = screen_position
	_gesture_last = screen_position
	_shake_distance = 0.0
	pyramid_gesture_started.emit()


func _update_gesture(screen_position: Vector2, relative: Vector2) -> void:
	_shake_distance += relative.length()
	_gesture_last = screen_position
	_pyramid.rotation.z = clampf(_pyramid.rotation.z - relative.x * 0.0025, -0.22, 0.22)
	_pyramid.rotation.x = clampf(_pyramid.rotation.x + relative.y * 0.0018, -0.16, 0.16)


func _finish_gesture(screen_position: Vector2) -> void:
	_gesture_holding = false
	_gesture_last = screen_position
	var downward_drag := maxf(0.0, screen_position.y - _gesture_start.y)
	var shake_bonus := minf(_shake_distance / 180.0, 1.2)
	var drop_bonus := minf(downward_drag / 170.0, 1.2)
	var strength := clampf(1.0 + shake_bonus + drop_bonus, 1.0, 3.4)
	pyramid_gesture_released.emit(strength)


func _screen_hits_pyramid(screen_position: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _pyramid_hit_area == null:
		return false
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == _pyramid_hit_area


func _on_pyramid_mouse_entered() -> void:
	if gesture_enabled:
		_pyramid.scale = Vector3.ONE * 1.04
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_pyramid_mouse_exited() -> void:
	if not _gesture_holding:
		_pyramid.scale = Vector3.ONE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _recover_inside_arena() -> void:
	die.freeze = true
	die.position = Vector3(_rng.randf_range(-0.4, 0.4), 2.5, _rng.randf_range(-0.4, 0.4))
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
	die.freeze = false


func _build_die() -> void:
	die = RigidBody3D.new()
	die.input_ray_pickable = false
	die.mass = 0.7
	die.continuous_cd = true
	die.freeze = true
	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = 0.62
	physics_material.friction = 0.48
	die.physics_material_override = physics_material
	die.gravity_scale = 1.45
	die.linear_damp = 2.15
	die.angular_damp = 2.65
	die.contact_monitor = true
	die.max_contacts_reported = 8
	die.body_entered.connect(_on_die_body_entered)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh_node.mesh = mesh
	_die_material = StandardMaterial3D.new()
	_die_material.albedo_color = Color("f4eee1")
	_die_material.roughness = 0.45
	mesh_node.material_override = _die_material
	die.add_child(mesh_node)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	die.add_child(collision)
	_add_face_label("1", Vector3(0, 0.506, 0), Vector3(-PI * 0.5, 0, 0))
	_add_face_label("1", Vector3(0, -0.506, 0), Vector3(PI * 0.5, 0, 0))
	_add_face_label("2", Vector3(0.506, 0, 0), Vector3(0, PI * 0.5, 0))
	_add_face_label("2", Vector3(-0.506, 0, 0), Vector3(0, -PI * 0.5, 0))
	_add_face_label("3", Vector3(0, 0, -0.506), Vector3.ZERO)
	_add_face_label("3", Vector3(0, 0, 0.506), Vector3(0, PI, 0))
	add_child(die)


func _add_face_label(text_value: String, position_value: Vector3, rotation_value: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Face%s" % text_value
	label.text = text_value
	label.font_size = 88
	label.pixel_size = 0.0046
	label.modulate = Color("fff9e8")
	label.outline_modulate = Color("29252a")
	label.outline_size = 10
	label.position = position_value
	label.rotation = rotation_value
	die.add_child(label)


func _set_die_color(die_id: String) -> void:
	var colors := {
		"blue": Color("3887ff"), "yellow": Color("ffd447"), "green": Color("43c86f"),
		"red": Color("ef5350"), "purple": Color("a66cff"), "gray": Color("9aa0aa"),
	}
	_die_material.albedo_color = colors.get(die_id, Color("f4eee1"))
	var light_face := die_id == "yellow"
	for child in die.get_children():
		if child is Label3D:
			(child as Label3D).modulate = Color("29252a") if light_face else Color("fff9e8")
			(child as Label3D).outline_modulate = Color("fff2c8") if light_face else Color("29252a")


func _build_bumpers() -> void:
	for bumper_position in [Vector3(-1.9, 0.42, -1.15), Vector3(1.75, 0.42, 1.15), Vector3(2.0, 0.42, -1.25)]:
		var body := StaticBody3D.new(); body.position = bumper_position; body.input_ray_pickable = false
		var shape_node := CollisionShape3D.new(); var shape := CylinderShape3D.new(); shape.radius = 0.38; shape.height = 0.82; shape_node.shape = shape; body.add_child(shape_node)
		var mesh_node := MeshInstance3D.new(); var mesh := CylinderMesh.new(); mesh.top_radius = 0.38; mesh.bottom_radius = 0.46; mesh.height = 0.82; mesh_node.mesh = mesh; mesh_node.visible = false; mesh_node.material_override = _die_material if _die_material != null else StandardMaterial3D.new(); body.add_child(mesh_node)
		var physics := PhysicsMaterial.new(); physics.bounce = 0.72; physics.friction = 0.38; body.physics_material_override = physics
		add_child(body)


func _on_die_body_entered(_body: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_collision_msec < 55: return
	_last_collision_msec = now
	collision_sound_requested.emit(die.linear_velocity.length() + die.angular_velocity.length() * 0.08)
