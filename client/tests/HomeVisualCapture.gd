extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(390, 844)
	# Capture the same logical viewport Godot's mobile stretch settings expose.
	# Scaling the content factor here made the UI several times too small and
	# hid portrait-specific layout problems.
	root.content_scale_factor = 1.0
	var network := root.get_node("NetworkClient")
	network._clear_session()
	network.set_process(false)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var lobby := main.get_node("Lobby") as LobbyUI
	lobby._on_connection_status_changed("Connected")
	if "--join-sheet" in OS.get_cmdline_user_args():
		lobby.nickname_input.text = "그내"
		lobby._on_join_pressed()
	await create_timer(0.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	var output := "/tmp/camel_join_sheet.png" if "--join-sheet" in OS.get_cmdline_user_args() else "/tmp/camel_online_home.png"
	var error := image.save_png(output)
	print("Home capture: ", error_string(error))
	quit(0 if error == OK else 1)
