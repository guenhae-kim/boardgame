extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(480, 900)
	root.content_scale_factor = float(root.size.x) / 1280.0
	var network := root.get_node("NetworkClient")
	network._clear_session()
	network.set_process(false)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png("/tmp/camel_online_home.png")
	print("Home capture: ", error_string(error))
	quit(0 if error == OK else 1)
