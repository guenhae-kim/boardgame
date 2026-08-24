extends Node

signal connection_status_changed(status: String)
signal room_created(payload: Dictionary)
signal room_joined(payload: Dictionary)
signal player_joined(payload: Dictionary)
signal player_left(player_id: String)
signal player_state(payload: Dictionary)
signal lobby_state(payload: Dictionary)
signal game_authority_requested(payload: Dictionary)
signal game_action_requested(payload: Dictionary)
signal game_update(payload: Dictionary)
signal game_unlocked(payload: Dictionary)
signal game_timeout_requested(payload: Dictionary)
signal chat_message(payload: Dictionary)
signal server_error(code: String, message: String)

var _socket := WebSocketPeer.new()
var _last_state := WebSocketPeer.STATE_CLOSED
var _heartbeat_elapsed := 0.0
var _reconnect_elapsed := 0.0
var room_code := ""
var player_id := ""
var reconnect_token := ""

func _ready() -> void:
	_load_session()
	set_process(true)
	connect_to_server()

func connect_to_server() -> void:
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_OPEN:
		return
	_socket = WebSocketPeer.new()
	_last_state = WebSocketPeer.STATE_CONNECTING
	connection_status_changed.emit("Connecting")
	var result := _socket.connect_to_url(NetworkConfig.server_url())
	if result != OK:
		_last_state = WebSocketPeer.STATE_CLOSED
		connection_status_changed.emit("Error")
		server_error.emit("CONNECT_FAILED", error_string(result))

func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state != _last_state:
		_last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connection_status_changed.emit("Connected")
			send_message(Protocol.HELLO, {"client": "godot", "protocol_version": Protocol.VERSION})
			if not room_code.is_empty() and not reconnect_token.is_empty():
				send_message(Protocol.RECONNECT, {"room_code": room_code, "reconnect_token": reconnect_token})
		elif state == WebSocketPeer.STATE_CLOSED:
			connection_status_changed.emit("Disconnected")

	if state == WebSocketPeer.STATE_CLOSED:
		_reconnect_elapsed += delta
		if _reconnect_elapsed >= 2.5:
			_reconnect_elapsed = 0.0
			connect_to_server()
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	_reconnect_elapsed = 0.0

	while _socket.get_available_packet_count() > 0:
		_handle_packet(_socket.get_packet().get_string_from_utf8())

	_heartbeat_elapsed += delta
	if _heartbeat_elapsed >= 10.0:
		_heartbeat_elapsed = 0.0
		send_message(Protocol.PING, {"client_time": Time.get_ticks_msec()})

func create_room(nickname: String) -> void:
	send_message(Protocol.CREATE_ROOM, {"nickname": nickname})

func join_room(room_code: String, nickname: String) -> void:
	send_message(Protocol.JOIN_ROOM, {
		"room_code": room_code.strip_edges().to_upper(),
		"nickname": nickname,
	})

func send_player_input(direction: Vector2, sequence: int) -> void:
	send_message(Protocol.PLAYER_INPUT, {
		"direction": {"x": direction.x, "z": direction.y},
		"sequence": sequence,
	})

func send_chat(text: String) -> void:
	send_message(Protocol.CHAT_SEND, {"text": text})

func set_cpu_count(count: int) -> void:
	send_message(Protocol.LOBBY_CPU, {"count": count})

func start_game(fill_cpu: bool = true) -> void:
	send_message(Protocol.START_GAME, {"fill_cpu": fill_cpu})

func send_game_action(action: Dictionary, request_id: String) -> void:
	send_message(Protocol.GAME_ACTION, {"action": action, "request_id": request_id})

func send_game_commit(payload: Dictionary) -> void:
	send_message(Protocol.GAME_COMMIT, payload)

func send_game_ready(game_sequence: int) -> void:
	send_message(Protocol.GAME_READY, {"game_sequence": game_sequence})

func send_message(type: String, payload: Dictionary = {}) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		server_error.emit("NOT_CONNECTED", "Server is not connected")
		return
	_socket.send_text(Protocol.encode_message(type, payload))

func _handle_packet(text: String) -> void:
	var message := Protocol.decode_message(text)
	if message.is_empty():
		server_error.emit("INVALID_MESSAGE", "Invalid server message")
		return

	var type := str(message["type"])
	var payload := message["payload"] as Dictionary
	match type:
		Protocol.HELLO:
			pass
		Protocol.ROOM_CREATED:
			_remember_session(payload)
			room_created.emit(payload)
		Protocol.ROOM_JOINED:
			_remember_session(payload)
			room_joined.emit(payload)
		Protocol.PLAYER_JOINED:
			player_joined.emit(payload)
		Protocol.PLAYER_LEFT:
			player_left.emit(str(payload.get("player_id", "")))
		Protocol.PLAYER_STATE:
			player_state.emit(payload)
		Protocol.LOBBY_STATE:
			lobby_state.emit(payload)
		Protocol.GAME_AUTHORITY_REQUEST:
			game_authority_requested.emit(payload)
		Protocol.GAME_ACTION_REQUEST:
			game_action_requested.emit(payload)
		Protocol.GAME_UPDATE:
			game_update.emit(payload)
		Protocol.GAME_UNLOCK:
			game_unlocked.emit(payload)
		Protocol.GAME_TIMEOUT_REQUEST:
			game_timeout_requested.emit(payload)
		Protocol.CHAT_MESSAGE:
			chat_message.emit(payload)
		Protocol.PING:
			send_message(Protocol.PONG, {"server_time": payload.get("server_time", 0)})
		Protocol.PONG:
			pass
		Protocol.ERROR:
			var error_code := str(payload.get("code", "ERROR"))
			if error_code == "RECONNECT_FAILED" or (error_code == "ROOM_NOT_FOUND" and not reconnect_token.is_empty()):
				_clear_session()
			server_error.emit(error_code, str(payload.get("message", "Unknown error")))
		_:
			server_error.emit("UNKNOWN_TYPE", "Unknown server message: %s" % type)

func _remember_session(payload: Dictionary) -> void:
	room_code = str(payload.get("room_code", room_code))
	player_id = str(payload.get("player_id", player_id))
	reconnect_token = str(payload.get("reconnect_token", reconnect_token))
	_save_session()

func _save_session() -> void:
	var data := JSON.stringify({"room_code": room_code, "player_id": player_id, "reconnect_token": reconnect_token})
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			storage.setItem("boardgame_session", data)
	else:
		var config := ConfigFile.new()
		config.set_value("session", "data", data)
		config.save("user://network_session.cfg")

func _clear_session() -> void:
	room_code = ""
	player_id = ""
	reconnect_token = ""
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			storage.removeItem("boardgame_session")
	else:
		var config := ConfigFile.new()
		config.set_value("session", "data", "")
		config.save("user://network_session.cfg")

func _load_session() -> void:
	var data := ""
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			data = str(storage.getItem("boardgame_session"))
	else:
		var config := ConfigFile.new()
		if config.load("user://network_session.cfg") == OK:
			data = str(config.get_value("session", "data", ""))
	if data.is_empty() or data == "<null>":
		return
	var parsed: Variant = JSON.parse_string(data)
	if parsed is Dictionary:
		room_code = str(parsed.get("room_code", ""))
		player_id = str(parsed.get("player_id", ""))
		reconnect_token = str(parsed.get("reconnect_token", ""))
