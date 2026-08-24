extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var portrait := "--portrait" in OS.get_cmdline_user_args()
	if portrait:
		root.size = Vector2i(480, 900)
	var scene := (load("res://scenes/LocalGame.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(2.2).timeout
	var image := root.get_viewport().get_texture().get_image()
	var output := "/tmp/camel_tabletop_portrait.png" if portrait else "/tmp/camel_tabletop_ui.png"
	var error := image.save_png(output)
	print("Visual capture: ", output, " ", error_string(error))
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
