extends SceneTree

var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/OnlineGame.tscn") as PackedScene
	var online := packed.instantiate() as CamelOnlineGameController
	root.add_child(online)
	online._network.set_process(false)
	for unused in 5: await process_frame
	var roster := [
		{"player_id": "player_1", "nickname": "Host", "is_cpu": false, "connected": true, "is_host": true},
		{"player_id": "player_2", "nickname": "Friend", "is_cpu": false, "connected": true, "is_host": false},
		{"player_id": "cpu_1", "nickname": "CPU 1", "is_cpu": true, "connected": true, "is_host": false},
		{"player_id": "cpu_2", "nickname": "CPU 2", "is_cpu": true, "connected": true, "is_host": false},
	]
	online.start_room({"room_code": "TEST", "player_id": "player_1", "lobby": {"room_code": "TEST", "host_player_id": "player_1", "max_slots": 4, "players": roster}})
	_check(online.lobby_ui.visible, "online room opens the four-slot lobby")
	var rules := CamelGameRules.new(["Host", "Friend", "CPU 1", "CPU 2"], 777)
	for index in roster.size():
		var player := rules.state.players[index] as Dictionary
		player["id"] = roster[index]["player_id"]; player["is_cpu"] = roster[index]["is_cpu"]; player["connected"] = true
	online._on_game_update({
		"room_code": "TEST", "game_sequence": 1, "actor_id": "", "events": [],
		"public_state": CamelGameProjection.public_state(rules.state),
		"private_state": CamelGameProjection.private_states(rules.state)["player_1"],
		"authority_state": rules.state.to_dict(),
		"game_busy": false,
	})
	await create_timer(0.5).timeout
	_check(online.board.visible and not online.lobby_ui._root.visible, "authoritative update reveals the shared 3D board")
	_check(online.online_ui._private_cards.size() == 5 and online.online_ui._hand_cards.size() == 5, "local player sees five tactile private cards")
	_check(not online.online_ui._roll_button.disabled, "only current local player action controls are enabled")
	online.online_ui._select_card("red")
	_check(online.board._enabled_targets.has("prediction:winner") and online.board._enabled_targets.has("prediction:loser"), "selecting a hand card highlights only prediction zones")
	var submitted: Array = []
	online.online_ui.online_action_requested.connect(func(action: CamelAction): submitted.append(action))
	online.online_ui.handle_board_target("prediction", "winner")
	_check(not submitted.is_empty() and (submitted[0] as CamelAction).type == CamelAction.FINAL_BET, "clicking the highlighted board zone creates a final-bet Action")
	online.online_ui._can_act = true
	online.online_ui._set_mode("track", [])
	_check(not online.board._enabled_targets.is_empty() and online.board._enabled_targets.keys().all(func(key): return str(key).begins_with("track:")), "audience mode highlights only legal track spaces")
	var cpu := CamelCPUController.new()
	rules.state.current_player_index = 2
	var cpu_action := cpu.choose_action(rules, "cpu_1")
	_check(cpu_action is CamelAction and rules.validate_action("cpu_1", cpu_action).is_empty(), "CPU controller returns a legal instance of the same Action type as a human")
	print("Online client flow: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else: failed = true; push_error("FAIL: " + label)
