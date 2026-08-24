extends SceneTree

var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var network := root.get_node("NetworkClient")
	var server_url := _server_url()
	# Native test runs share user:// storage; start this integration case with a
	# deliberately fresh browser-equivalent session.
	network._clear_session()
	network._socket.close()
	await create_timer(0.1).timeout
	network._socket = WebSocketPeer.new()
	network._last_state = WebSocketPeer.STATE_CONNECTING
	network._socket.connect_to_url(server_url)
	var waited := 0.0
	while network._socket.get_ready_state() != WebSocketPeer.STATE_OPEN and waited < 5.0:
		await create_timer(0.05).timeout; waited += 0.05
	_check(network._socket.get_ready_state() == WebSocketPeer.STATE_OPEN, "Godot host connects to the real WebSocket server")
	var online := (load("res://scenes/OnlineGame.tscn") as PackedScene).instantiate() as CamelOnlineGameController
	root.add_child(online)
	await process_frame
	var created_holder: Array = []
	network.connect("room_created", func(payload: Dictionary): created_holder.append(payload), CONNECT_ONE_SHOT)
	network.create_room("Godot Host")
	await _wait_array(created_holder)
	var created := created_holder[0] as Dictionary
	online.start_room(created)
	_check(str(created.get("reconnect_token", "")).length() > 20, "host receives a persistent reconnect token")

	var guest := WebSocketPeer.new()
	guest.connect_to_url(server_url)
	await _wait_socket_open(guest)
	await _next_message(guest, Protocol.HELLO)
	guest.send_text(Protocol.encode_message(Protocol.JOIN_ROOM, {"room_code": created["room_code"], "nickname": "Guest"}))
	var joined := await _next_message(guest, Protocol.ROOM_JOINED)
	_check(str(joined.payload.get("player_id", "")) != str(created["player_id"]), "second real WebSocket client joins a distinct player slot")

	network.set_cpu_count(2)
	await create_timer(0.15).timeout
	var first_update: Array = []
	network.connect("game_update", func(payload: Dictionary): first_update.append(payload), CONNECT_ONE_SHOT)
	network.start_game(true)
	await _wait_array(first_update, 5.0)
	_check(not first_update.is_empty() and int(first_update[0].get("game_sequence", 0)) == 1, "Godot host initializes and commits authoritative GameState")
	var guest_initial := await _next_message(guest, Protocol.GAME_UPDATE, 5.0)
	_check(not guest_initial.payload.has("authority_state"), "guest packet never contains host authority state")
	_check((guest_initial.payload.get("private_state", {}) as Dictionary).has("final_cards"), "guest receives its own private hand")
	guest.send_text(Protocol.encode_message(Protocol.GAME_READY, {"game_sequence": 1}))
	await _next_message(guest, Protocol.GAME_UNLOCK, 5.0)

	var second_update: Array = []
	network.connect("game_update", func(payload: Dictionary): second_update.append(payload), CONNECT_ONE_SHOT)
	network.send_game_action(CamelAction.new(CamelAction.ROLL_DIE).to_dict(), "e2e-roll")
	await _wait_array(second_update, 5.0)
	var guest_action := await _next_message(guest, Protocol.GAME_UPDATE, 5.0)
	var event_types: Array = []
	for event in guest_action.payload.get("events", []): event_types.append(str((event as Dictionary).get("type", "")))
	_check(CamelEvent.DIE_ROLLED in event_types and CamelEvent.CAMEL_MOVED in event_types, "authoritative dice and movement events reach every client")
	_check(int(second_update[0].get("game_sequence", 0)) == int(guest_action.payload.get("game_sequence", -1)), "host and guest observe the same game sequence")
	guest.close()
	print("Godot/Node online E2E: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _server_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-url="):
			return argument.trim_prefix("--server-url=")
	return "ws://127.0.0.1:8080/ws"

func _wait_array(holder: Array, timeout := 2.0) -> void:
	var elapsed := 0.0
	while holder.is_empty() and elapsed < timeout:
		await create_timer(0.02).timeout; elapsed += 0.02

func _wait_socket_open(socket: WebSocketPeer) -> void:
	var elapsed := 0.0
	while socket.get_ready_state() != WebSocketPeer.STATE_OPEN and elapsed < 3.0:
		socket.poll(); await create_timer(0.02).timeout; elapsed += 0.02

func _next_message(socket: WebSocketPeer, type: String, timeout := 2.0) -> Dictionary:
	var elapsed := 0.0
	while elapsed < timeout:
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var message := Protocol.decode_message(socket.get_packet().get_string_from_utf8())
			if str(message.get("type", "")) == type: return message
		await create_timer(0.02).timeout; elapsed += 0.02
	return {}

func _check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else: failed = true; push_error("FAIL: " + label)
