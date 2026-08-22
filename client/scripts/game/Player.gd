class_name NetworkPlayer
extends Node3D

const INTERPOLATION_SPEED := 14.0
const COLORS: Array[Color] = [
	Color("ef4444"), Color("3b82f6"), Color("22c55e"), Color("eab308"),
	Color("a855f7"), Color("06b6d4"), Color("f97316"), Color("ec4899"),
]

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel

var player_id := ""
var target_position := Vector3.ZERO
var target_yaw := 0.0
var _initialized := false

func setup(data: Dictionary, is_local: bool) -> void:
	player_id = str(data.get("player_id", ""))
	name_label.text = "%s%s" % [str(data.get("nickname", player_id)), " (YOU)" if is_local else ""]
	var color_index := int(data.get("color_index", 0)) % COLORS.size()
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[color_index]
	material.roughness = 0.7
	mesh.material_override = material
	apply_state(data, true)

func apply_state(data: Dictionary, snap: bool = false) -> void:
	var position_data := data.get("position", {}) as Dictionary
	target_position = Vector3(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.6)),
		float(position_data.get("z", 0.0)),
	)
	var direction := data.get("direction", {}) as Dictionary
	var direction_2d := Vector2(float(direction.get("x", 0.0)), float(direction.get("z", 0.0)))
	if direction_2d.length_squared() > 0.001:
		target_yaw = atan2(direction_2d.x, direction_2d.y)
	if snap or not _initialized:
		position = target_position
		rotation.y = target_yaw
		_initialized = true

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-INTERPOLATION_SPEED * delta)
	position = position.lerp(target_position, weight)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)

