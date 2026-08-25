class_name CamelTrafficLight
extends Node3D

@export var green_seconds := 4.0
@export var yellow_seconds := 1.0
@export var red_seconds := 4.0
@export var phase_offset := 0.0
var _elapsed := 0.0

func _ready() -> void:
	_elapsed = phase_offset
	# Each scene instance owns its emissive materials so multiple signals can use
	# different phase offsets without fighting over a shared imported resource.
	for light_name in ["Red", "Yellow", "Green"]:
		var mesh := get_node_or_null(light_name) as MeshInstance3D
		if mesh != null and mesh.material_override != null:
			mesh.material_override = mesh.material_override.duplicate()

func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, green_seconds + yellow_seconds + red_seconds)
	var active := "Green" if _elapsed < green_seconds else "Yellow" if _elapsed < green_seconds + yellow_seconds else "Red"
	for light_name in ["Red", "Yellow", "Green"]:
		var mesh := get_node_or_null(light_name) as MeshInstance3D
		if mesh == null:
			continue
		var material := mesh.material_override as StandardMaterial3D
		material.emission_enabled = light_name == active
		material.emission_energy_multiplier = 2.2 if light_name == active else 0.0
