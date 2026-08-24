extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var portrait := "--portrait" in OS.get_cmdline_user_args()
	root.size = Vector2i(480, 900) if portrait else Vector2i(1280, 720)
	root.content_scale_factor = float(root.size.x) / 1280.0
	var online := (load("res://scenes/OnlineGame.tscn") as PackedScene).instantiate() as CamelOnlineGameController
	root.add_child(online); online._network.set_process(false); await process_frame
	var roster := [
		{"player_id": "player_1", "nickname": "그내", "is_cpu": false, "connected": true, "is_host": true},
		{"player_id": "player_2", "nickname": "친구", "is_cpu": false, "connected": true, "is_host": false},
		{"player_id": "cpu_1", "nickname": "CPU 1", "is_cpu": true, "connected": true, "is_host": false},
		{"player_id": "cpu_2", "nickname": "CPU 2", "is_cpu": true, "connected": true, "is_host": false},
	]
	online.start_room({"room_code": "K7DF", "player_id": "player_1", "lobby": {"room_code": "K7DF", "host_player_id": "player_1", "max_slots": 4, "players": roster}})
	var rules := CamelGameRules.new(["그내", "친구", "CPU 1", "CPU 2"], 1234)
	for index in roster.size():
		var player := rules.state.players[index] as Dictionary; player["id"] = roster[index]["player_id"]; player["is_cpu"] = roster[index]["is_cpu"]
	online._on_game_update({"room_code": "K7DF", "game_sequence": 1, "actor_id": "", "events": [], "public_state": CamelGameProjection.public_state(rules.state), "private_state": CamelGameProjection.private_states(rules.state)["player_1"], "authority_state": rules.state.to_dict(), "game_busy": false})
	await online.camera_director.show_board(0.0)
	await create_timer(1.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	var output := "/tmp/camel_online_portrait.png" if portrait else "/tmp/camel_online_landscape.png"
	var error := image.save_png(output); print("Online capture: ", output, " ", error_string(error), " visible=", root.get_visible_rect().size, " window=", root.size); quit(0 if error == OK else 1)
