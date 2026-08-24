class_name CamelPieceVisual
extends Node3D

var piece_id := ""
var body: MeshInstance3D
var _base_scale := Vector3.ONE


func setup(id: String, color: Color) -> void:
	piece_id = id
	body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.34
	mesh.height = 0.72
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	body.material_override = material
	add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.58
	head.mesh = head_mesh
	head.position = Vector3(0, 0.42, 0.03)
	head.material_override = material
	add_child(head)
	for ear_x in [-0.16, 0.16]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius = 0.015
		ear_mesh.bottom_radius = 0.095
		ear_mesh.height = 0.22
		ear.mesh = ear_mesh
		ear.position = Vector3(ear_x, 0.72, 0.02)
		ear.rotation.z = -ear_x * 0.65
		ear.material_override = material
		add_child(ear)
	for eye_x in [-0.085, 0.085]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.position = Vector3(eye_x, 0.48, 0.285)
		var eye_material := StandardMaterial3D.new()
		eye_material.albedo_color = Color("252229")
		eye.material_override = eye_material
		add_child(eye)
	var snout := MeshInstance3D.new()
	var snout_mesh := SphereMesh.new()
	snout_mesh.radius = 0.075
	snout_mesh.height = 0.1
	snout.mesh = snout_mesh
	snout.position = Vector3(0, 0.39, 0.31)
	snout.material_override = _simple_material(Color("f4d0b2"))
	add_child(snout)
	var marker := Label3D.new()
	marker.text = id.left(1).to_upper()
	marker.font_size = 42
	marker.outline_size = 8
	marker.position = Vector3(0, 0.58, 0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(marker)
	_base_scale = scale


func _simple_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func play_idle() -> void:
	rotation.z = 0.0
	scale = _base_scale


func play_walk() -> void:
	var tween := create_tween()
	tween.set_loops(2)
	tween.tween_property(self, "rotation:z", 0.12, 0.08)
	tween.tween_property(self, "rotation:z", -0.12, 0.08)
	tween.tween_property(self, "rotation:z", 0.0, 0.05)
	await tween.finished


func move_step(target: Vector3, duration: float = 0.24) -> void:
	var high := target + Vector3(0, 0.35, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", high, duration * 0.5)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", target, duration * 0.5)
	await tween.finished


func play_jump(target: Vector3) -> void:
	var apex := (position + target) * 0.5 + Vector3(0, 1.25, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", apex, 0.22)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", target, 0.22)
	await tween.finished


func play_land() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.16, 0.72, 1.16), 0.08)
	tween.tween_property(self, "scale", _base_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


func play_squashed() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.22, 0.62, 1.22), 0.1)
	tween.tween_property(self, "scale", _base_scale, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tween.finished


func play_happy() -> void:
	var original_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", original_y + 0.28, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await tween.finished
