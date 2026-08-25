@tool
extends Node3D
class_name KenneyMaterialFix

@export var color_atlas: Texture2D:
	set(value):
		color_atlas = value
		_apply_material()
@export_range(0.0, 1.0, 0.05) var roughness := 0.82
@export var tint := Color.WHITE

var _shared_material: StandardMaterial3D


func _ready() -> void:
	_apply_material()


func _apply_material() -> void:
	if not is_inside_tree() or color_atlas == null:
		return
	_shared_material = StandardMaterial3D.new()
	_shared_material.albedo_texture = color_atlas
	_shared_material.albedo_color = tint
	_shared_material.roughness = roughness
	_shared_material.metallic = 0.0
	_shared_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _shared_material
