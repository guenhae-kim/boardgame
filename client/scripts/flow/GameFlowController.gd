class_name CamelGameFlowController
extends Node3D

enum FlowPhase {
	SETUP,
	TURN_START,
	WAITING_FOR_ACTION,
	ROLLING_DICE,
	RESOLVING_ACTION,
	PLAYING_MOVEMENT_ANIMATION,
	PLAYING_EFFECT_ANIMATION,
	TURN_END,
	ROUND_END,
	GAME_END,
}

const PHASE_NAMES := {
	FlowPhase.SETUP: "SETUP",
	FlowPhase.TURN_START: "TURN_START",
	FlowPhase.WAITING_FOR_ACTION: "WAITING_FOR_ACTION",
	FlowPhase.ROLLING_DICE: "ROLLING_DICE",
	FlowPhase.RESOLVING_ACTION: "RESOLVING_ACTION",
	FlowPhase.PLAYING_MOVEMENT_ANIMATION: "PLAYING_MOVEMENT_ANIMATION",
	FlowPhase.PLAYING_EFFECT_ANIMATION: "PLAYING_EFFECT_ANIMATION",
	FlowPhase.TURN_END: "TURN_END",
	FlowPhase.ROUND_END: "ROUND_END",
	FlowPhase.GAME_END: "GAME_END",
}

var phase := FlowPhase.SETUP
var rules: CamelGameRules
var event_queue := CamelGameEventQueue.new()
var board: CamelBoardVisual
var dice: CamelDiceController
var camera_director: CamelCameraDirector
var ui: CamelLocalGameUI
var _camera: Camera3D
var _acting_player_id := ""
var _acting_player_name := ""
var _pending_die_event: Dictionary = {}
var sound_manager: CamelSoundManager


func _ready() -> void:
	_build_world()
	_build_ui()
	await get_tree().process_frame
	await _start_new_game(["Player 1", "Player 2", "Player 3"])


func _build_world() -> void:
	board = CamelBoardVisual.new()
	add_child(board)
	dice = CamelDiceController.new()
	dice.position = Vector3.ZERO
	add_child(dice)
	sound_manager = CamelSoundManager.new(); add_child(sound_manager)
	dice.collision_sound_requested.connect(sound_manager.play_collision)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(0, 8, 2)
	fill_light.omni_range = 25.0
	fill_light.light_energy = 0.55
	add_child(fill_light)
	_camera = Camera3D.new()
	# Keep the board's horizontal framing stable when a phone rotates.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 88.0
	_camera.position = Vector3(0, 13.5, 14.5)
	_camera.rotation_degrees = Vector3(-43, 0, 0)
	add_child(_camera)
	camera_director = CamelCameraDirector.new()
	add_child(camera_director)
	camera_director.setup(_camera)
	board.movement_step_changed.connect(camera_director.follow_space)
	dice.pyramid_gesture_started.connect(_on_pyramid_gesture_started)
	dice.pyramid_gesture_released.connect(func(strength: float): await _run_roll("", 0, strength, true))


func _build_ui() -> void:
	ui = CamelLocalGameUI.new()
	add_child(ui)
	ui.new_game_requested.connect(func(names: Array): await _start_new_game(names))
	ui.action_requested.connect(func(action: CamelAction): await _run_action(action))
	ui.roll_requested.connect(func(die_id: String, value: int): await _run_roll(die_id, value))
	ui.debug_stack_requested.connect(_prepare_stack_demo)
	ui.debug_next_turn_requested.connect(_debug_next_turn)


func _start_new_game(names: Array) -> void:
	if names.size() < 2:
		names = ["Player 1", "Player 2", "Player 3"]
	event_queue.clear()
	_pending_die_event.clear()
	_set_phase(FlowPhase.SETUP, "새 게임을 준비합니다.", false)
	rules = CamelGameRules.new()
	var events := rules.start_new_game(names)
	board.sync_state(rules.state)
	ui.clear_log()
	for event in events:
		_log_event(event as CamelEvent)
	ui.refresh_state(rules)
	await camera_director.show_board(0.35)
	await _begin_turn()


func _begin_turn() -> void:
	if rules.state.phase == "GAME_OVER":
		_set_phase(FlowPhase.GAME_END, "게임이 종료되었습니다.", false)
		return
	_acting_player_id = str(rules.state.current_player()["id"])
	_acting_player_name = str(rules.state.current_player()["name"])
	ui.set_presented_player(_acting_player_id)
	_set_phase(FlowPhase.TURN_START, "%s의 턴이 시작됩니다." % _acting_player_name, false)
	await camera_director.show_board(0.38)
	await get_tree().create_timer(0.3).timeout
	_set_phase(FlowPhase.WAITING_FOR_ACTION, "%s: 행동 하나를 선택하세요." % _acting_player_name, true)


func _run_roll(forced_die: String = "", forced_value: int = 0, throw_strength: float = 1.0, from_gesture: bool = false) -> void:
	if (from_gesture and phase != FlowPhase.ROLLING_DICE) or (not from_gesture and phase != FlowPhase.WAITING_FOR_ACTION):
		return
	_acting_player_id = str(rules.state.current_player()["id"])
	_acting_player_name = str(rules.state.current_player()["name"])
	var die_id := forced_die
	if die_id.is_empty() or die_id not in rules.state.remaining_dice:
		die_id = rules.choose_next_die()
	if die_id.is_empty():
		ui.show_error("굴릴 수 있는 주사위가 없습니다.")
		return
	_set_phase(FlowPhase.ROLLING_DICE, "%s가 피라미드 안의 주사위를 섞습니다. 강도 %.1f" % [_acting_player_name, throw_strength], false)
	ui.add_log("%s가 피라미드를 작동합니다. 남은 주사위 중 하나를 추첨합니다." % _acting_player_name, "ffd166")
	await camera_director.show_dice(dice.global_position)
	var rolled_value := await dice.play_roll(die_id, forced_value, throw_strength)
	ui.add_log("피라미드에서 나온 주사위: %s / 결과 %d" % [die_id, rolled_value], "7ee7ff")
	rules.force_next_roll(die_id, rolled_value)
	_set_phase(FlowPhase.RESOLVING_ACTION, "주사위 결과를 규칙에 적용합니다.", false)
	var result := rules.apply_action(_acting_player_id, CamelAction.new(CamelAction.ROLL_DIE))
	await _resolve_result(result)


func _run_action(action: CamelAction) -> void:
	if phase != FlowPhase.WAITING_FOR_ACTION:
		return
	_acting_player_id = str(rules.state.current_player()["id"])
	_acting_player_name = str(rules.state.current_player()["name"])
	_set_phase(FlowPhase.RESOLVING_ACTION, "%s의 행동을 처리합니다." % _acting_player_name, false)
	var result := rules.apply_action(_acting_player_id, action)
	await _resolve_result(result)


func _on_pyramid_gesture_started() -> void:
	if phase != FlowPhase.WAITING_FOR_ACTION:
		return
	_acting_player_id = str(rules.state.current_player()["id"])
	_acting_player_name = str(rules.state.current_player()["name"])
	_set_phase(FlowPhase.ROLLING_DICE, "피라미드를 잡았습니다. 흔든 뒤 아래로 끌어 놓으면 더 강하게 떨어집니다.", false)
	ui.add_log("%s가 피라미드를 잡았습니다." % _acting_player_name, "ffd166")


func _resolve_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		ui.show_error(str(result.get("error", "행동할 수 없습니다.")))
		_set_phase(FlowPhase.WAITING_FOR_ACTION, "%s: 다른 행동을 선택하세요." % _acting_player_name, true)
		return
	ui.show_error("")
	event_queue.enqueue_all(result.get("events", []) as Array)
	await event_queue.play_all(_play_event)
	board.sync_state(rules.state)
	ui.refresh_state(rules)
	if rules.state.phase == "GAME_OVER":
		var names: Array = []
		for player_id in rules.state.winners:
			names.append(str(rules.state.player_by_id(str(player_id))["name"]))
		_set_phase(FlowPhase.GAME_END, "게임 종료 · 승자: %s" % ", ".join(names), false)
		await camera_director.show_board()
		return
	await _begin_turn()


func _play_event(event: CamelEvent) -> void:
	_log_event(event)
	_play_event_sound(event)
	match event.type:
		CamelEvent.DIE_ROLLED:
			_pending_die_event = event.data.duplicate(true)
			_set_phase(FlowPhase.RESOLVING_ACTION, "%s 낙타가 %d칸 이동합니다." % [event.data["camel"], event.data["value"]], false)
			await get_tree().create_timer(0.28).timeout
		CamelEvent.CAMEL_MOVED:
			_set_phase(FlowPhase.PLAYING_MOVEMENT_ANIMATION, "%s 말과 위쪽 스택이 %d → %d칸으로 이동합니다." % [event.data["moving_camel"], event.data["from"], event.data["to"]], false)
			await camera_director.focus_space(board.track_point(int(event.data["from"])))
			await board.play_move(event.data)
			if (event.data.get("destination_stack", []) as Array).size() <= 1:
				await camera_director.show_result(board.track_point(int(event.data["to"])))
		CamelEvent.CAMELS_STACKED:
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%d번 칸에서 말이 쌓입니다." % event.data["position"], false)
			await camera_director.focus_space(board.track_point(int(event.data["position"])), 0.25)
			await board.play_stack(event.data)
			await camera_director.show_result(board.track_point(int(event.data["position"])))
		CamelEvent.SPECTATOR_TRIGGERED:
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%s 타일 효과로 %d번 칸으로 이동합니다." % [event.data["side"], event.data["to"]], false)
			await board.play_spectator_move(event.data)
		CamelEvent.SPECTATOR_PLACED:
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%d번 칸에 %s 관중 타일을 놓습니다." % [event.data["space"], event.data["side"]], false)
			await camera_director.focus_space(board.track_point(int(event.data["space"])), 0.3)
			await board.play_spectator_placed(event.data)
		CamelEvent.MONEY_CHANGED:
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%s의 EP: %d → %d" % [event.data["player_id"], event.data["before"], event.data["after"]], false)
			await ui.play_money_change(str(event.data["player_id"]), int(event.data["after"]) - int(event.data["before"]))
			await get_tree().create_timer(0.22).timeout
		CamelEvent.LEG_BET_TAKEN:
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%s 구간 베팅 카드 %d를 가져갑니다." % [event.data["camel"], event.data["value"]], false)
			await camera_director.focus_component(board.bet_stack_position(str(event.data["camel"])))
			await board.play_take_bet(event.data)
		CamelEvent.FINAL_BET_PLACED:
			var bet_type := str(event.data["bet"])
			_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "최종 %s 예측 카드를 비공개로 제출합니다." % ("1등" if bet_type == "winner" else "꼴등"), false)
			await camera_director.focus_component(board.prediction_position(bet_type))
			await board.play_prediction_card(event.data)
		CamelEvent.LEG_ENDED:
			# The fifth result belongs on the physical history tray before scoring clears it.
			await _place_pending_die_history()
			_set_phase(FlowPhase.ROUND_END, "%d구간이 끝났습니다. 정산합니다." % event.data["leg"], false)
			await camera_director.show_board(0.35)
			await ui.show_round_complete(int(event.data["leg"]))
			await get_tree().create_timer(0.55).timeout
			await board.clear_dice_history()
		CamelEvent.TURN_ENDED:
			await _place_pending_die_history()
			_set_phase(FlowPhase.TURN_END, "%s의 행동과 모든 연출이 끝났습니다." % _acting_player_name, false)
			await get_tree().create_timer(0.35).timeout
		CamelEvent.GAME_END_TRIGGERED:
			await _place_pending_die_history()
		CamelEvent.GAME_ENDED:
			_set_phase(FlowPhase.GAME_END, "최종 정산이 완료되었습니다.", false)
			await get_tree().create_timer(0.7).timeout
		_:
			await get_tree().create_timer(0.08).timeout


func _play_event_sound(event: CamelEvent) -> void:
	match event.type:
		CamelEvent.DIE_ROLLED: sound_manager.play("dice_throw")
		CamelEvent.CAMEL_MOVED: sound_manager.play("walk")
		CamelEvent.CAMELS_STACKED: sound_manager.play("stack")
		CamelEvent.SPECTATOR_PLACED: sound_manager.play("card_land")
		CamelEvent.LEG_BET_TAKEN, CamelEvent.FINAL_BET_PLACED: sound_manager.play("card_fly")
		CamelEvent.MONEY_CHANGED: sound_manager.play("coin_gain" if int(event.data.get("after", 0)) >= int(event.data.get("before", 0)) else "coin_loss")
		CamelEvent.TURN_STARTED: sound_manager.play("turn")
		CamelEvent.LEG_ENDED: sound_manager.play("round")
		CamelEvent.GAME_ENDED: sound_manager.play("game")


func _place_pending_die_history() -> void:
	if _pending_die_event.is_empty():
		return
	_set_phase(FlowPhase.PLAYING_EFFECT_ANIMATION, "%s %d 주사위를 구간 기록에 놓습니다." % [_pending_die_event["die"], _pending_die_event["value"]], false)
	await camera_director.show_history(board.dice_history_position())
	await board.play_dice_history(str(_pending_die_event["die"]), int(_pending_die_event["value"]), dice.die.global_position)
	dice.hide_result_die()
	_pending_die_event.clear()


func _prepare_stack_demo() -> void:
	if phase != FlowPhase.WAITING_FOR_ACTION:
		return
	CamelGameDebug.force_stacks(rules, {
		2: ["red"], 4: ["blue", "yellow"], 7: ["green"], 10: ["purple"],
		14: ["white"], 15: ["black"],
	})
	board.sync_state(rules.state)
	ui.refresh_state(rules)
	ui.add_log("Debug: red가 2를 굴리면 3단 스택에 착지합니다.", "ff9f7e")
	ui.debug_die_option.select(CamelGameState.RACE_CAMELS.find("red"))
	ui.debug_value.value = 2


func _debug_next_turn() -> void:
	if phase != FlowPhase.WAITING_FOR_ACTION:
		return
	var event := CamelGameDebug.force_next_player(rules)
	_log_event(event)
	ui.refresh_state(rules)
	await _begin_turn()


func _set_phase(next_phase: FlowPhase, description: String, input_enabled: bool) -> void:
	phase = next_phase
	var display_name := _acting_player_name
	if rules != null and rules.state != null and display_name.is_empty():
		display_name = str(rules.state.current_player()["name"])
	ui.set_flow_state(PHASE_NAMES[phase], display_name, description, input_enabled)
	if dice != null:
		dice.gesture_enabled = phase == FlowPhase.WAITING_FOR_ACTION
	if rules != null and rules.state != null:
		ui.refresh_state(rules)


func _log_event(event: CamelEvent) -> void:
	var text := event.type
	match event.type:
		CamelEvent.TURN_STARTED:
			text = "%s의 턴이 시작됩니다." % event.data.get("player_name", event.data.get("player_id", ""))
		CamelEvent.DIE_ROLLED:
			text = "%s 주사위 %d: %s 말 이동" % [event.data["die"], event.data["value"], event.data["camel"]]
		CamelEvent.CAMEL_MOVED:
			text = "%s: %d번 → %d번" % [event.data["moving_camel"], event.data["from"], event.data["to"]]
		CamelEvent.CAMELS_STACKED:
			text = "%d번 스택(아래→위): %s" % [event.data["position"], ", ".join(event.data["bottom_to_top"])]
		CamelEvent.SPECTATOR_TRIGGERED:
			text = "%s 발동: %d번 → %d번" % [event.data["side"], event.data["from"], event.data["to"]]
		CamelEvent.TURN_ENDED:
			text = "%s의 턴 종료" % _acting_player_name
		CamelEvent.LEG_ENDED:
			text = "%d구간 종료 · 순위 %s" % [event.data["leg"], " > ".join(event.data["order"])]
		CamelEvent.GAME_ENDED:
			text = "게임 종료 · 승자 %s" % ", ".join(event.data["winners"])
	ui.add_log(text)
