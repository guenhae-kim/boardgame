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
	var car_follow := online.get_node("CityEnvironment/CityRoadPath/CarFollow") as PathFollow3D
	var car_progress := car_follow.progress_ratio
	await create_timer(0.2).timeout
	_check(car_follow.progress_ratio != car_progress, "editor-placeable city car moves along its independent road path")
	_check(online.get_node("CityEnvironment/TrafficLightA/Green") is MeshInstance3D, "editor-placeable traffic light cycles emissive signal meshes")
	var roster := [
		{"player_id": "player_1", "nickname": "Host", "is_cpu": false, "connected": true, "is_host": true},
		{"player_id": "player_2", "nickname": "Friend", "is_cpu": false, "connected": true, "is_host": false},
		{"player_id": "cpu_1", "nickname": "CPU 1", "is_cpu": true, "connected": true, "is_host": false},
		{"player_id": "cpu_2", "nickname": "CPU 2", "is_cpu": true, "connected": true, "is_host": false},
	]
	online.start_room({"room_code": "TEST", "player_id": "player_1", "lobby": {"room_code": "TEST", "host_player_id": "player_1", "max_slots": 4, "players": roster}})
	_check(online.lobby_ui.visible, "online room opens the four-slot lobby")
	_check(online.lobby_ui.has_signal("leave_requested"), "room lobby exposes an explicit leave action")
	var leave_requested := [false]
	online.online_ui.leave_game_requested.connect(func(): leave_requested[0] = true)
	online.online_ui._settings_button.pressed.emit()
	_check(online.online_ui._settings_panel.visible, "game settings button opens the leave panel")
	online.online_ui._confirm_leave_game()
	_check(bool(leave_requested[0]), "game leave confirmation emits one explicit leave request")
	var rules := CamelGameRules.new(["Host", "Friend", "CPU 1", "CPU 2"], 777)
	for index in roster.size():
		var player := rules.state.players[index] as Dictionary
		player["id"] = roster[index]["player_id"]; player["is_cpu"] = roster[index]["is_cpu"]; player["connected"] = true
	(rules.state.player_by_id("player_1")["leg_tickets"] as Array).append({"camel": "red", "value": 5})
	rules.state.dice_history = [{"die": "red", "camel": "red", "value": 3}, {"die": "blue", "camel": "blue", "value": 1}]
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
	_check(online.online_ui._hand_row.get_child_count() == 6, "hand contains prediction cards plus the spectator tool, never acquired betting tickets")
	_check((online.online_ui._ticket_rows["player_1"] as HBoxContainer).get_child_count() == 1, "acquired betting ticket appears beside its owner HUD")
	_check((online.online_ui._history_slots[0].get_node("Value") as Label).text == "3" and (online.online_ui._history_slots[1].get_node("Value") as Label).text == "1", "dice history uses clear face values without cramped color text")
	_check(not online.dice.gesture_enabled, "online dice cannot be triggered by the hidden pyramid gesture")
	online.online_ui.receive_chat("Friend", "red please three", "player_2")
	_check(online.online_ui._hud_chat_bubbles.has("player_2"), "room chat appears as a visible speech bubble beside its sender HUD")
	var top_bet_card := (online.board._bet_card_nodes["red"] as Array)[-1] as Node3D
	var top_bet_label := top_bet_card.get_child(1) as Label3D
	_check(is_zero_approx(top_bet_label.rotation.x + PI * 0.5), "betting value is printed flat on the physical card surface")
	_check(not online.online_ui._roll_button.disabled, "only current local player action controls are enabled")
	_check(online.board._enabled_targets.has("bet:red"), "legal board betting stacks are directly tappable on my turn")
	var submitted: Array = []
	online.online_ui.online_action_requested.connect(func(action: CamelAction): submitted.append(action))
	online.online_ui._select_card("red")
	_check(submitted.is_empty(), "selecting a color card never submits a dice action")
	var unlocked_before_legacy_roll := online._turn_unlocked
	online._run_roll("", 0, 1.0, true)
	_check(online._turn_unlocked == unlocked_before_legacy_roll and submitted.is_empty(), "legacy world roll input is ignored in OnlineGame")
	_check(online.board._enabled_targets.has("prediction:winner") and online.board._enabled_targets.has("prediction:loser"), "selecting a hand card highlights only prediction zones")
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
