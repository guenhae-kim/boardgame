extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	var lobby := (load("res://scenes/ui/RoomLobby.tscn") as PackedScene).instantiate() as CamelRoomLobbyUI
	root.add_child(lobby)
	lobby.update_lobby({
		"room_code": "K7DF",
		"host_player_id": "player_1",
		"max_slots": 4,
		"started": false,
		"players": [
			{"player_id": "player_1", "nickname": "그내", "is_host": true, "is_cpu": false, "connected": true},
			{"player_id": "player_2", "nickname": "철수", "is_host": false, "is_cpu": false, "connected": true},
		],
	}, "player_1")
	await create_timer(0.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png("/tmp/camel_room_lobby.png")
	print("Room lobby capture: ", error_string(error))
	quit(0 if error == OK else 1)
