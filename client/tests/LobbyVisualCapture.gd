extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	var network := root.get_node("NetworkClient")
	network.set_process(false)
	var online := (load("res://scenes/OnlineGame.tscn") as PackedScene).instantiate() as CamelOnlineGameController
	root.add_child(online)
	await process_frame
	var roster := [
		{"player_id": "player_1", "nickname": "꼬부기", "is_cpu": false, "connected": true, "is_host": true},
		{"player_id": "player_2", "nickname": "철수", "is_cpu": false, "connected": true, "is_host": false},
		{"player_id": "cpu_1", "nickname": "CPU 친구", "is_cpu": true, "connected": true, "is_host": false},
	]
	online.start_room({"room_code": "XHW7", "player_id": "player_1", "lobby": {"room_code": "XHW7", "host_player_id": "player_1", "max_slots": 4, "players": roster}})
	await create_timer(1.0).timeout
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png("/tmp/camel_room_lobby.png")
	print("Lobby capture: ", error_string(error))
	quit(0 if error == OK else 1)
