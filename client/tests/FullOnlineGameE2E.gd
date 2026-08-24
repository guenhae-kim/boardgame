extends SceneTree

var failed := false
var sequence_count := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var network := root.get_node("NetworkClient")
	network._clear_session()
	network._socket.close()
	await create_timer(0.1).timeout
	network._socket = WebSocketPeer.new()
	network._last_state = WebSocketPeer.STATE_CONNECTING
	network._socket.connect_to_url("ws://127.0.0.1:8080/ws")
	await _wait_network(network)
	var online := (load("res://scenes/OnlineGame.tscn") as PackedScene).instantiate() as CamelOnlineGameController
	root.add_child(online)
	await process_frame
	var created_holder: Array = []
	network.room_created.connect(func(payload: Dictionary): created_holder.append(payload), CONNECT_ONE_SHOT)
	network.create_room("A")
	await _wait_array(created_holder)
	var created := created_holder[0] as Dictionary
	online.start_room(created)
	var host_id := str(created.get("player_id", ""))

	var guest := await _connect_peer()
	guest.send_text(Protocol.encode_message(Protocol.JOIN_ROOM, {"room_code": created["room_code"], "nickname": "B"}))
	var joined := await _next_message(guest, Protocol.ROOM_JOINED)
	var guest_id := str(joined.get("payload", {}).get("player_id", ""))
	var guest_token := str(joined.get("payload", {}).get("reconnect_token", ""))
	_check(host_id == "player_1" and guest_id == "player_2", "two clients keep stable P1/P2 ownership")

	network.send_chat("hello")
	var host_chat := await _next_message(guest, Protocol.CHAT_MESSAGE)
	_check(str(host_chat.get("payload", {}).get("text", "")) == "hello", "room chat reaches the second client")
	guest.send_text(Protocol.encode_message(Protocol.CHAT_SEND, {"text": "ㅋㅋ"}))
	var chat_holder: Array = []
	network.chat_message.connect(func(payload: Dictionary): chat_holder.append(payload), CONNECT_ONE_SHOT)
	await _wait_array(chat_holder)
	_check(not chat_holder.is_empty() and str(chat_holder[0].get("text", "")) == "ㅋㅋ", "Korean room chat returns to the host")

	network.start_game(true)
	var update := await _next_message(guest, Protocol.GAME_UPDATE, 8.0)
	var payload := update.get("payload", {}) as Dictionary
	sequence_count = int(payload.get("game_sequence", 0))
	_check((payload.get("public_state", {}).get("players", []) as Array).size() == 4, "start fills P3/P4 with CPU")
	_check(not payload.has("authority_state"), "guest never receives host authority state")
	_check((payload.get("private_state", {}).get("final_cards", []) as Array).size() == 5, "guest receives only its own five-card hand")
	guest.send_text(Protocol.encode_message(Protocol.GAME_READY, {"game_sequence": sequence_count}))
	var unlock := await _next_message(guest, Protocol.GAME_UNLOCK, 8.0)
	_check(int(unlock.get("payload", {}).get("turn_deadline_ms", 0)) > int(unlock.get("payload", {}).get("server_time", 0)), "server starts the human turn deadline")
	guest.send_text(Protocol.encode_message(Protocol.GAME_ACTION, {"request_id": "steal-p1", "action": {"type": CamelAction.ROLL_DIE, "player_id": host_id, "data": {}}}))
	var ownership_error := await _next_message(guest, Protocol.ERROR)
	_check(str(ownership_error.get("payload", {}).get("code", "")) in ["NOT_YOUR_TURN", "PLAYER_OWNERSHIP_MISMATCH"], "P2 cannot submit P1's action")

	# Do nothing on P1's first turn. The short test server deadline must cause a
	# complete legal Action through the same host GameRules pipeline.
	update = await _next_message(guest, Protocol.GAME_UPDATE, 8.0)
	payload = update.get("payload", {}) as Dictionary
	var first_types := _event_types(payload)
	_check(CamelEvent.TURN_TIMED_OUT in first_types, "human timeout commits an automatic legal action")
	sequence_count = int(payload.get("game_sequence", 0))
	guest.send_text(Protocol.encode_message(Protocol.GAME_READY, {"game_sequence": sequence_count}))

	var reconnected := false
	var finished := str((payload.get("public_state", {}) as Dictionary).get("phase", "")) == "GAME_OVER"
	var actions := 1
	while not finished and actions < 180:
		unlock = await _next_message(guest, Protocol.GAME_UNLOCK, 30.0)
		var unlock_payload := unlock.get("payload", {}) as Dictionary
		var current_id := str(unlock_payload.get("current_player_id", ""))
		if unlock.is_empty():
			_check(false, "game unlock arrives without deadlock")
			break

		if not reconnected and actions >= 3:
			guest.close()
			await create_timer(0.18).timeout
			guest = await _connect_peer()
			guest.send_text(Protocol.encode_message(Protocol.RECONNECT, {"room_code": created["room_code"], "reconnect_token": guest_token}))
			var resumed := await _next_message(guest, Protocol.ROOM_JOINED)
			var restored := await _next_message(guest, Protocol.GAME_UPDATE)
			_check(str(resumed.get("payload", {}).get("player_id", "")) == guest_id, "refresh reconnect restores the same P2 slot")
			_check((restored.get("payload", {}).get("private_state", {}).get("final_cards", []) as Array) == (payload.get("private_state", {}).get("final_cards", []) as Array), "reconnect restores P2 private hand")
			reconnected = true

		if current_id == host_id:
			network.send_game_action(CamelAction.new(CamelAction.ROLL_DIE).to_dict(), "full-host-%d" % actions)
		elif current_id == guest_id:
			guest.send_text(Protocol.encode_message(Protocol.GAME_ACTION, {"request_id": "full-guest-%d" % actions, "action": CamelAction.new(CamelAction.ROLL_DIE).to_dict()}))
		# CPU turns are scheduled by the authoritative host client.

		update = await _next_message(guest, Protocol.GAME_UPDATE, 15.0)
		if update.is_empty():
			_check(false, "every turn produces an authoritative update")
			break
		payload = update.get("payload", {}) as Dictionary
		print("TURN UPDATE seq=", payload.get("game_sequence", 0), " events=", _event_types(payload))
		var next_sequence := int(payload.get("game_sequence", 0))
		_check(next_sequence == sequence_count + 1, "game sequence advances exactly once")
		sequence_count = next_sequence
		_check(not payload.has("authority_state"), "private authority state remains absent throughout the game")
		guest.send_text(Protocol.encode_message(Protocol.GAME_READY, {"game_sequence": sequence_count}))
		finished = str((payload.get("public_state", {}) as Dictionary).get("phase", "")) == "GAME_OVER"
		actions += 1

	_check(finished, "Human 2 + CPU 2 complete a full online game")
	_check(online.rules != null and online.rules.state.phase == "GAME_OVER", "host and guest finish on the same public phase")
	_check(reconnected, "mid-game reconnect was exercised")
	print("Full multiplayer E2E: ", "FAILED" if failed else "PASSED", " · actions=", actions, " · final_sequence=", sequence_count)
	guest.close()
	quit(1 if failed else 0)

func _event_types(payload: Dictionary) -> Array:
	var result: Array = []
	for event in payload.get("events", []):
		result.append(str((event as Dictionary).get("type", "")))
	return result

func _connect_peer() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	peer.connect_to_url("ws://127.0.0.1:8080/ws")
	var elapsed := 0.0
	while peer.get_ready_state() != WebSocketPeer.STATE_OPEN and elapsed < 5.0:
		peer.poll(); await create_timer(0.02).timeout; elapsed += 0.02
	await _next_message(peer, Protocol.HELLO)
	return peer

func _wait_network(network: Node) -> void:
	var elapsed := 0.0
	while network._socket.get_ready_state() != WebSocketPeer.STATE_OPEN and elapsed < 5.0:
		await create_timer(0.02).timeout; elapsed += 0.02

func _wait_array(holder: Array, timeout := 3.0) -> void:
	var elapsed := 0.0
	while holder.is_empty() and elapsed < timeout:
		await create_timer(0.02).timeout; elapsed += 0.02

func _next_message(socket: WebSocketPeer, type: String, timeout := 3.0) -> Dictionary:
	var elapsed := 0.0
	while elapsed < timeout:
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var message := Protocol.decode_message(socket.get_packet().get_string_from_utf8())
			if str(message.get("type", "")) == type:
				return message
		await create_timer(0.02).timeout; elapsed += 0.02
	return {}

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
