class_name CamelOnlineGameController
extends CamelGameFlowController

var room_code := ""
var local_player_id := ""
var host_player_id := ""
var lobby_ui: CamelRoomLobbyUI
var online_ui: CamelOnlineGameUI
var private_state: Dictionary = {}
var _last_game_sequence := 0
var _update_queue: Array = []
var _processing_updates := false
var _cpu_pending := false
var _turn_unlocked := false
var _cpu_controller := CamelCPUController.new()
var _network: Node

func _ready() -> void:
	_network = get_node("/root/NetworkClient")
	_build_world()
	_build_ui()
	lobby_ui = CamelRoomLobbyUI.new(); add_child(lobby_ui)
	lobby_ui.visible = false; online_ui.visible = false
	lobby_ui.start_requested.connect(func(fill: bool): _network.start_game(fill))
	lobby_ui.cpu_count_requested.connect(func(count: int): _network.set_cpu_count(count))
	_network.connect("lobby_state", _on_lobby_state)
	_network.connect("game_authority_requested", _on_authority_request)
	_network.connect("game_action_requested", _on_action_request)
	_network.connect("game_update", _on_game_update)
	_network.connect("game_unlocked", _on_game_unlocked)
	_network.connect("game_timeout_requested", _on_timeout_request)
	_network.connect("chat_message", _on_chat_message)
	_network.connect("server_error", _on_server_error)
	board.board_target_pressed.connect(online_ui.handle_board_target)
	board.visible = false; dice.visible = false

func _build_ui() -> void:
	online_ui = CamelOnlineGameUI.new(); ui = online_ui; add_child(ui)
	online_ui.online_action_requested.connect(_request_action)
	online_ui.interaction_mode_changed.connect(_on_interaction_mode)
	online_ui.chat_send_requested.connect(Callable(_network, "send_chat"))
	online_ui.sound_requested.connect(sound_manager.play)

func start_room(payload: Dictionary) -> void:
	set_room_active(true)
	room_code = str(payload.get("room_code", ""))
	local_player_id = str(payload.get("player_id", ""))
	var lobby := payload.get("lobby", {}) as Dictionary
	if lobby.is_empty(): lobby = {"room_code": room_code, "players": payload.get("players", []), "max_slots": 4}
	_on_lobby_state(lobby)

func clear_room() -> void:
	room_code = ""; local_player_id = ""; rules = null; board.visible = false; dice.visible = false
	set_room_active(false)

func set_room_active(active: bool) -> void:
	if lobby_ui != null: lobby_ui.visible = active
	if online_ui != null: online_ui.visible = active

func _on_lobby_state(payload: Dictionary) -> void:
	if not room_code.is_empty() and str(payload.get("room_code", "")) != room_code: return
	room_code = str(payload.get("room_code", room_code)); host_player_id = str(payload.get("host_player_id", ""))
	lobby_ui.update_lobby(payload, local_player_id)

func _on_authority_request(payload: Dictionary) -> void:
	if local_player_id != host_player_id and host_player_id != "": return
	if str(payload.get("reason", "")) == "host_migration" and payload.has("authority_state"):
		rules = CamelGameRules.new()
		rules.load_state(CamelGameState.from_dict(payload.get("authority_state", {}) as Dictionary))
		var current := rules.state.current_player()
		if _turn_unlocked and bool(current.get("is_cpu", false)) and rules.state.phase == "PLAYING":
			_schedule_cpu(str(current.get("id", "")))
		return
	var roster := payload.get("players", []) as Array
	var names: Array = []
	for player in roster: names.append(str((player as Dictionary).get("nickname", "Player")))
	rules = CamelGameRules.new()
	var events := rules.start_new_game(names)
	for index in mini(roster.size(), rules.state.players.size()):
		var source := roster[index] as Dictionary; var player := rules.state.players[index] as Dictionary
		player["id"] = str(source.get("player_id", player["id"])); player["name"] = str(source.get("nickname", player["name"])); player["is_cpu"] = bool(source.get("is_cpu", false)); player["connected"] = bool(source.get("connected", true))
	_commit(events, "")

func _on_action_request(payload: Dictionary) -> void:
	if local_player_id != host_player_id or rules == null: return
	var actor := str(payload.get("actor_id", ""))
	var result := rules.apply_action(actor, CamelAction.from_dict(payload.get("action", {}) as Dictionary))
	if bool(result.get("ok", false)):
		_commit(result.get("events", []) as Array, actor)
	else:
		_commit([CamelEvent.new("ACTION_REJECTED", {"player_id": actor, "error": str(result.get("error", "잘못된 행동"))})], actor)

func _commit(events: Array, actor_id: String) -> void:
	_network.send_game_commit({
		"actor_id": actor_id,
		"events": CamelGameProjection.sanitized_events(events),
		"public_state": CamelGameProjection.public_state(rules.state),
		"private_states": CamelGameProjection.private_states(rules.state),
		"authority_state": rules.state.to_dict(),
	})

func _request_action(action: CamelAction) -> void:
	if not _turn_unlocked or rules == null or rules.state.phase != "PLAYING":
		return
	if str(rules.state.current_player().get("id", "")) != local_player_id:
		return
	if not rules.validate_action(local_player_id, action).is_empty():
		return
	_turn_unlocked = false
	_network.send_game_action(action.to_dict(), "%s-%d" % [local_player_id, Time.get_ticks_msec()])

func _on_game_update(payload: Dictionary) -> void:
	if str(payload.get("room_code", "")) != room_code: return
	var sequence := int(payload.get("game_sequence", 0))
	if sequence <= _last_game_sequence: return
	_last_game_sequence = sequence
	_update_queue.append(payload.duplicate(true))
	if not _processing_updates: _drain_updates()

func _drain_updates() -> void:
	_processing_updates = true
	while not _update_queue.is_empty():
		var payload := _update_queue.pop_front() as Dictionary
		_turn_unlocked = false
		online_ui.set_turn_deadline(0, int(payload.get("server_time", 0)), false)
		private_state = payload.get("private_state", {}) as Dictionary
		var incoming: CamelGameState
		if local_player_id == host_player_id and payload.has("authority_state"):
			incoming = CamelGameState.from_dict(payload["authority_state"] as Dictionary)
			if rules == null: rules = CamelGameRules.new()
			rules.load_state(incoming)
		else:
			incoming = CamelGameProjection.state_for_client(payload.get("public_state", {}) as Dictionary, private_state)
			if rules == null: rules = CamelGameRules.new()
			rules.load_state(incoming)
		board.visible = true; dice.visible = true; lobby_ui.show_game()
		var actor_id := str(payload.get("actor_id", ""))
		if not actor_id.is_empty():
			_acting_player_id = actor_id
			var actor := rules.state.player_by_id(actor_id); _acting_player_name = str(actor.get("name", actor_id))
		var events := CamelGameProjection.events_from_dict(payload.get("events", []) as Array)
		if not events.is_empty():
			event_queue.enqueue_all(events); await event_queue.play_all(_play_event)
		board.sync_state(rules.state)
		var current := rules.state.current_player(); var current_id := str(current["id"])
		var game_busy := bool(payload.get("game_busy", true))
		_turn_unlocked = not game_busy and rules.state.phase == "PLAYING"
		var can_act := current_id == local_player_id and not bool(current.get("is_cpu", false)) and rules.state.phase == "PLAYING" and not game_busy
		_acting_player_id = current_id; _acting_player_name = str(current["name"]); online_ui.set_presented_player(current_id)
		_set_phase(FlowPhase.WAITING_FOR_ACTION if rules.state.phase == "PLAYING" else FlowPhase.GAME_END, "내 차례입니다. 행동을 선택하세요." if can_act else "%s가 행동 중입니다." % _acting_player_name, can_act)
		online_ui.set_online_context(rules.state, private_state, local_player_id, can_act)
		if not game_busy:
			online_ui.set_turn_deadline(int(payload.get("turn_deadline_ms", 0)), int(payload.get("server_time", 0)), can_act)
		dice.gesture_enabled = can_act
		if can_act: _on_interaction_mode("", [])
		if game_busy:
			_network.send_game_ready(int(payload.get("game_sequence", 0)))
		elif local_player_id == host_player_id and bool(current.get("is_cpu", false)) and rules.state.phase == "PLAYING":
			_schedule_cpu(current_id)
	_processing_updates = false

func _on_game_unlocked(payload: Dictionary) -> void:
	if str(payload.get("room_code", "")) != room_code or int(payload.get("game_sequence", 0)) != _last_game_sequence or rules == null:
		return
	var current := rules.state.current_player()
	var current_id := str(current.get("id", ""))
	var can_act := current_id == local_player_id and not bool(current.get("is_cpu", false)) and rules.state.phase == "PLAYING"
	_turn_unlocked = rules.state.phase == "PLAYING"
	_acting_player_id = current_id
	_acting_player_name = str(current.get("name", current_id))
	_set_phase(FlowPhase.WAITING_FOR_ACTION if rules.state.phase == "PLAYING" else FlowPhase.GAME_END, "내 차례입니다. 행동을 선택하세요." if can_act else "%s가 행동 중입니다." % _acting_player_name, can_act)
	online_ui.set_online_context(rules.state, private_state, local_player_id, can_act)
	online_ui.set_turn_deadline(int(payload.get("turn_deadline_ms", 0)), int(payload.get("server_time", 0)), can_act)
	dice.gesture_enabled = can_act
	if can_act:
		_on_interaction_mode("", [])
	if local_player_id == host_player_id and bool(current.get("is_cpu", false)) and rules.state.phase == "PLAYING":
		_schedule_cpu(current_id)

func _on_timeout_request(payload: Dictionary) -> void:
	if local_player_id != host_player_id or rules == null or rules.state.phase != "PLAYING":
		return
	var actor_id := str(payload.get("actor_id", ""))
	if str(rules.state.current_player().get("id", "")) != actor_id:
		return
	var action := _cpu_controller.choose_random_legal_action(rules, actor_id)
	var result := rules.apply_action(actor_id, action)
	if not bool(result.get("ok", false)):
		return
	var events := result.get("events", []) as Array
	events.push_front(CamelEvent.new(CamelEvent.TURN_TIMED_OUT, {"player_id": actor_id, "action": action.to_dict()}))
	_commit(events, actor_id)

func _play_event(event: CamelEvent) -> void:
	if event.type == CamelEvent.DIE_ROLLED:
		_set_phase(FlowPhase.ROLLING_DICE, "%s 주사위가 빠르게 굴러갑니다." % event.data.get("die", ""), false)
		await camera_director.show_dice(dice.global_position, 0.28)
		await dice.play_roll(str(event.data.get("die", "blue")), int(event.data.get("value", 1)), 2.25)
	if event.type == "ACTION_REJECTED":
		if str(event.data.get("player_id", "")) == local_player_id: online_ui.show_error(str(event.data.get("error", "행동할 수 없습니다.")))
		await get_tree().create_timer(0.15).timeout; return
	if event.type == CamelEvent.TURN_TIMED_OUT:
		_set_phase(FlowPhase.RESOLVING_ACTION, "시간 초과! 자동으로 행동했습니다.", false)
		sound_manager.play("timer_warning")
		await get_tree().create_timer(0.45).timeout
		return
	await super._play_event(event)

func _schedule_cpu(cpu_id: String) -> void:
	if _cpu_pending: return
	_cpu_pending = true
	await get_tree().create_timer(randf_range(0.55, 0.9)).timeout
	if rules != null and rules.state.phase == "PLAYING" and str(rules.state.current_player()["id"]) == cpu_id:
		var action := _cpu_controller.choose_action(rules, cpu_id)
		var result := rules.apply_action(cpu_id, action)
		if bool(result.get("ok", false)): _commit(result.get("events", []) as Array, cpu_id)
	_cpu_pending = false

func _on_interaction_mode(target_type: String, ids: Array) -> void:
	if target_type == "bet" and rules != null:
		ids = []
		for camel_id in CamelGameState.RACE_CAMELS:
			if not (rules.state.betting_stacks.get(camel_id, []) as Array).is_empty(): ids.append(camel_id)
	if target_type == "track" and ids.is_empty() and rules != null:
		ids = _valid_track_spaces()
	board.set_interaction(target_type, ids)

func _valid_track_spaces() -> Array:
	var result: Array = []
	for space in range(2, CamelGameState.TRACK_LENGTH + 1):
		for side in ["oasis", "mirage"]:
			if rules.validate_action(local_player_id, CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": space, "side": side})).is_empty(): result.append(str(space)); break
	return result

func _run_roll(_forced_die: String = "", _forced_value: int = 0, _throw_strength: float = 1.0, _from_gesture: bool = false) -> void:
	if dice.gesture_enabled: _request_action(CamelAction.new(CamelAction.ROLL_DIE))

func _on_pyramid_gesture_started() -> void:
	if dice.gesture_enabled: online_ui.set_action_enabled(false)

func _on_chat_message(payload: Dictionary) -> void:
	if str(payload.get("room_code", "")) == room_code: online_ui.receive_chat(str(payload.get("nickname", "Player")), str(payload.get("text", "")))

func _on_server_error(code: String, message: String) -> void:
	if room_code.is_empty(): return
	online_ui.show_error("%s: %s" % [code, message])
	if rules != null and rules.state.phase == "PLAYING":
		var current := rules.state.current_player()
		var can_retry := _turn_unlocked and str(current.get("id", "")) == local_player_id and not bool(current.get("is_cpu", false))
		online_ui.set_online_context(rules.state, private_state, local_player_id, can_retry)
		dice.gesture_enabled = can_retry
