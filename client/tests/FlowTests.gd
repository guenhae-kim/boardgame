extends SceneTree

var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/LocalGame.tscn") as PackedScene
	var flow := packed.instantiate() as CamelGameFlowController
	root.add_child(flow)
	for unused in 8:
		await process_frame
	await create_timer(1.5).timeout
	_check(flow.board.track_point(2).x > flow.board.track_point(1).x, "track indices increase clockwise from the start marker")
	_check(flow.phase == CamelGameFlowController.FlowPhase.WAITING_FOR_ACTION, "game reaches WAITING_FOR_ACTION")
	_check(not flow.ui._action_controls[0].disabled, "current player input is enabled")
	CamelGameDebug.force_stacks(flow.rules, {
		2: ["red"], 3: ["blue", "yellow"], 4: ["green", "purple"], 5: ["white", "black"],
	})
	flow.board.sync_state(flow.rules.state)
	var actor_before := str(flow.rules.state.current_player()["id"])
	await flow._run_roll("red", 2)
	_check(flow.phase == CamelGameFlowController.FlowPhase.WAITING_FOR_ACTION, "queue drains before next turn input")
	_check(str(flow.rules.state.current_player()["id"]) != actor_before, "turn advances after animations")
	var physical_value := int((flow.rules.state.dice_history[0] as Dictionary).get("value", 0))
	var destination := 2 + physical_value
	_check(flow.rules.state.stack_at(destination).size() == 3 and flow.rules.state.stack_at(destination).back() == "red", "natural physical result creates a three-piece stack")
	var red_visual := flow.board.piece_visuals["red"] as CamelPieceVisual
	_check(red_visual.position.distance_to(flow.board.piece_position(destination, 2)) < 0.05, "piece visual finishes on top of stack")
	var stacked := flow.rules.state.stack_at(destination)
	var bottom_position := (flow.board.piece_visuals[str(stacked[0])] as CamelPieceVisual).position
	var top_position := (flow.board.piece_visuals[str(stacked[2])] as CamelPieceVisual).position
	_check(top_position.y - bottom_position.y >= 1.45, "stack levels remain vertically readable in the three-quarter camera")
	_check(Vector2(top_position.x, top_position.z).distance_to(Vector2(bottom_position.x, bottom_position.z)) > 0.03, "stack silhouettes receive a subtle non-staircase offset")
	_check(flow.board._history_nodes.size() == 1, "rolled die lands in the 3D round history tray")
	_check(not flow.event_queue.is_playing and flow.event_queue.is_empty(), "animation event queue is empty")
	_check(not flow._defer_state_refresh, "state presentation is released after the animation queue")
	var second_actor := str(flow.rules.state.current_player()["id"])
	await flow._run_action(CamelAction.new(CamelAction.TAKE_LEG_BET, {"camel": "blue"}))
	_check((flow.board._bet_card_nodes["blue"] as Array).size() == 3, "3D bet pile mirrors the remaining GameState cards")
	_check(str(flow.rules.state.current_player()["id"]) != second_actor, "non-dice rule action uses the same locked turn flow")
	_check(flow.phase == CamelGameFlowController.FlowPhase.WAITING_FOR_ACTION, "non-dice event queue also reopens input after completion")
	_check(flow.camera_director.state == CamelCameraDirector.CameraState.BOARD_OVERVIEW, "camera returns to overview before next turn input")
	_check(flow._camera.fov <= 65.0, "landscape overview avoids the distant ultra-wide prototype framing")
	var gesture_actor := str(flow.rules.state.current_player()["id"])
	var pyramid_screen_position := flow._camera.unproject_position(flow.dice.global_position + Vector3(0, 4.25, 0))
	_check(flow.dice._screen_hits_pyramid(pyramid_screen_position), "screen ray selects the pyramid interaction area")
	flow.dice._begin_gesture(Vector2(100, 100))
	await process_frame
	_check(flow.phase == CamelGameFlowController.FlowPhase.ROLLING_DICE, "holding the pyramid immediately locks the turn")
	_check(flow.ui._action_controls[0].disabled, "action UI stays disabled during pyramid gesture")
	flow.dice._update_gesture(Vector2(260, 140), Vector2(160, 40))
	flow.dice._update_gesture(Vector2(80, 180), Vector2(-180, 40))
	flow.dice._finish_gesture(Vector2(80, 330))
	var wait_time := 0.0
	while flow.phase != CamelGameFlowController.FlowPhase.WAITING_FOR_ACTION and wait_time < 15.0:
		await create_timer(0.1).timeout
		wait_time += 0.1
	_check(flow.phase == CamelGameFlowController.FlowPhase.WAITING_FOR_ACTION, "release gesture completes physical roll and reopens next turn")
	_check(str(flow.rules.state.current_player()["id"]) != gesture_actor, "gesture roll advances to the next player")
	print("Flow integration: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
