extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/environment/CityEnvironment.tscn") as PackedScene
	var city := packed.instantiate()
	root.add_child(city)
	await process_frame
	_check_group(city.get_node("Roads"), "Kenney road atlas is restored")
	_check_group(city.get_node("Buildings"), "Kenney building atlas is restored")
	_check_group(city.get_node("Trees"), "Kenney prop atlas is restored")
	_check_group(city.get_node("CityRoadPath/CarFollow/CarNPC/ModelSlot"), "Kenney toy-car atlas is restored")
	city.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _check_group(group: Node, message: String) -> void:
	var textured := 0
	var meshes := group.find_children("*", "MeshInstance3D", true, false)
	for mesh_node in meshes:
		var material := (mesh_node as MeshInstance3D).material_override as StandardMaterial3D
		if material != null and material.albedo_texture != null:
			textured += 1
	var ok := not meshes.is_empty() and textured == meshes.size()
	print("PASS: " if ok else "FAIL: ", message, " (", textured, "/", meshes.size(), ")")
	_failed = _failed or not ok
