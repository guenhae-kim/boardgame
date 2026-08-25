extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var portrait := "--portrait" in OS.get_cmdline_user_args()
	var tv_mode := "--tv" in OS.get_cmdline_user_args()
	var requested_size := Vector2i(480, 900) if portrait else Vector2i(1280, 720)
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--size="):
			var parts := str(argument).trim_prefix("--size=").split("x")
			if parts.size() == 2:
				requested_size = Vector2i(int(parts[0]), int(parts[1]))
		if str(argument).begins_with("--output="):
			output = str(argument).trim_prefix("--output=")
	root.size = requested_size
	# Capture the actual logical mobile viewport. Scaling the content factor here
	# made a 480px window report a multi-thousand-pixel UI canvas and hid layout bugs.
	root.content_scale_factor = 1.0
	var online := (load("res://scenes/OnlineGame.tscn") as PackedScene).instantiate() as CamelOnlineGameController
	root.add_child(online); online._network.set_process(false); await process_frame
	var roster := [
		{"player_id": "player_1", "nickname": "그내", "is_cpu": false, "connected": true, "is_host": true},
		{"player_id": "player_2", "nickname": "친구", "is_cpu": false, "connected": true, "is_host": false},
		{"player_id": "cpu_1", "nickname": "CPU 1", "is_cpu": true, "connected": true, "is_host": false},
		{"player_id": "cpu_2", "nickname": "CPU 2", "is_cpu": true, "connected": true, "is_host": false},
	]
	var entry_payload := {"room_code": "K7DF", "player_id": "player_1", "lobby": {"room_code": "K7DF", "host_player_id": "player_1", "max_slots": 4, "players": roster}}
	if tv_mode:
		entry_payload = {"room_code": "K7DF", "role": "spectator", "spectator_id": "spectator_1", "lobby": {"room_code": "K7DF", "host_player_id": "player_1", "max_slots": 4, "players": roster, "spectator_count": 1}}
	online.start_room(entry_payload)
	var rules := CamelGameRules.new(["그내", "친구", "CPU 1", "CPU 2"], 1234)
	for index in roster.size():
		var player := rules.state.players[index] as Dictionary; player["id"] = roster[index]["player_id"]; player["is_cpu"] = roster[index]["is_cpu"]
	(rules.state.player_by_id("player_1")["leg_tickets"] as Array).append({"camel": "red", "value": 5})
	(rules.state.player_by_id("player_2")["leg_tickets"] as Array).append({"camel": "blue", "value": 3})
	rules.state.dice_history = [{"die": "red", "camel": "red", "value": 3}, {"die": "blue", "camel": "blue", "value": 1}]
	if "--stack-demo" in OS.get_cmdline_user_args():
		CamelGameDebug.force_stacks(rules, {
			3: ["white"], 6: ["black"], 10: ["green", "yellow", "red", "purple"],
			13: ["blue"],
		})
	if "--game-over" in OS.get_cmdline_user_args():
		rules.state.phase = "GAME_OVER"
		rules.state.game_end_reason = "finish_crossed"
		(rules.state.players[0] as Dictionary)["money"] = 27
		(rules.state.players[1] as Dictionary)["money"] = 22
		(rules.state.players[2] as Dictionary)["money"] = 19
		(rules.state.players[3] as Dictionary)["money"] = 16
		rules.state.winners = ["player_1"]
	var server_time := int(Time.get_unix_time_from_system() * 1000.0)
	var update_payload := {"room_code": "K7DF", "game_sequence": 1, "actor_id": "", "events": [], "public_state": CamelGameProjection.public_state(rules.state), "game_busy": false, "server_time": server_time, "turn_deadline_ms": server_time + 43000}
	if not tv_mode:
		update_payload["private_state"] = CamelGameProjection.private_states(rules.state)["player_1"]
		update_payload["authority_state"] = rules.state.to_dict()
	online._on_game_update(update_payload)
	if "--highlight" in OS.get_cmdline_user_args():
		online.online_ui._select_card("red")
	if "--chat" in OS.get_cmdline_user_args():
		online.online_ui.receive_chat("친구", "빨강 제발 3!", "player_2")
	await online.camera_director.show_board(0.0)
	await create_timer(1.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	if output.is_empty():
		output = "/tmp/camel_online_%dx%d.png" % [requested_size.x, requested_size.y]
	var error := image.save_png(output); print("Online capture: ", output, " ", error_string(error), " visible=", root.get_visible_rect().size, " window=", root.size); quit(0 if error == OK else 1)
