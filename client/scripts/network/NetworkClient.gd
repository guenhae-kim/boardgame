extends Node

signal connection_status_changed(status: String)
signal room_created(payload: Dictionary)
signal room_joined(payload: Dictionary)
signal spectator_joined(payload: Dictionary)
signal room_left(payload: Dictionary)
signal session_status(payload: Dictionary)
signal identity_changed(nickname: String)
signal nickname_updated(payload: Dictionary)
signal player_takeover(payload: Dictionary)
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
var _leave_elapsed := 0.0
var room_code := ""
var player_id := ""
var spectator_id := ""
var room_role := "player"
var reconnect_token := ""
var identity_player_id := ""
var nickname := ""
var _leave_pending := false
var _attached_to_room := false
var _auto_reconnect_after_drop := false
var _leave_payload: Dictionary = {}

func _ready() -> void:
	_load_identity()
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

func is_connected_to_server() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state != _last_state:
		_last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connection_status_changed.emit("Connected")
			send_message(Protocol.HELLO, {"client": "godot", "protocol_version": Protocol.VERSION})
			if _leave_pending:
				_send_detached_leave()
			elif _auto_reconnect_after_drop and has_room_session():
				_auto_reconnect_after_drop = false
				send_message(Protocol.RECONNECT, {"room_code": room_code, "reconnect_token": reconnect_token})
			elif has_room_session():
				send_message(Protocol.SESSION_CHECK, {"room_code": room_code, "reconnect_token": reconnect_token})
		elif state == WebSocketPeer.STATE_CLOSED:
			if _attached_to_room and not _leave_pending:
				_auto_reconnect_after_drop = true
			_attached_to_room = false
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
	if _leave_pending:
		_leave_elapsed += delta
		if _leave_elapsed >= 2.5:
			_leave_elapsed = 0.0
			if _attached_to_room:
				send_message(Protocol.LEAVE_ROOM, _leave_payload)
			else:
				_send_detached_leave()

	while _socket.get_available_packet_count() > 0:
		_handle_packet(_socket.get_packet().get_string_from_utf8())

	_heartbeat_elapsed += delta
	if _heartbeat_elapsed >= 10.0:
		_heartbeat_elapsed = 0.0
		send_message(Protocol.PING, {"client_time": Time.get_ticks_msec()})

func create_room(nickname: String) -> void:
	set_identity_nickname(nickname)
	send_message(Protocol.CREATE_ROOM, {"nickname": nickname, "identity_id": identity_player_id})

func join_room(room_code: String, nickname: String) -> void:
	set_identity_nickname(nickname)
	send_message(Protocol.JOIN_ROOM, {
		"room_code": room_code.strip_edges().to_upper(),
		"nickname": nickname,
		"identity_id": identity_player_id,
	})

func join_spectator(room_code: String, nickname: String) -> void:
	set_identity_nickname(nickname)
	send_message(Protocol.JOIN_SPECTATOR, {
		"room_code": room_code.strip_edges().to_upper(),
		"nickname": nickname,
		"identity_id": identity_player_id,
	})

func leave_room() -> void:
	if _leave_pending or not has_room_session():
		return
	_leave_payload = {
		"room_code": room_code,
		"role": room_role,
		"player_id": player_id,
		"spectator_id": spectator_id,
		"reconnect_token": reconnect_token,
	}
	_leave_pending = true
	_leave_elapsed = 0.0
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if _attached_to_room:
			send_message(Protocol.LEAVE_ROOM, _leave_payload)
		else:
			_send_detached_leave()
	else:
		connect_to_server()

func discard_saved_session() -> void:
	leave_room()

func resume_saved_session() -> void:
	if has_room_session() and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_message(Protocol.RECONNECT, {"room_code": room_code, "reconnect_token": reconnect_token})

func has_room_session() -> bool:
	return not room_code.is_empty() and not reconnect_token.is_empty()

func has_identity() -> bool:
	return not identity_player_id.is_empty() and not nickname.is_empty()

func set_identity_nickname(value: String) -> void:
	var clean := value.strip_edges().left(20)
	if clean.is_empty():
		return
	if identity_player_id.is_empty():
		identity_player_id = Crypto.new().generate_random_bytes(16).hex_encode()
	nickname = clean
	_save_identity()
	identity_changed.emit(nickname)

func update_nickname(value: String) -> void:
	set_identity_nickname(value)
	if _attached_to_room:
		send_message(Protocol.UPDATE_NICKNAME, {"nickname": nickname})

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
			_attached_to_room = true
			_remember_session(payload)
			room_created.emit(payload)
		Protocol.ROOM_JOINED:
			_attached_to_room = true
			_remember_session(payload)
			room_joined.emit(payload)
		Protocol.SPECTATOR_JOINED:
			_attached_to_room = true
			_remember_session(payload)
			spectator_joined.emit(payload)
		Protocol.ROOM_LEFT:
			_leave_pending = false
			_leave_elapsed = 0.0
			_attached_to_room = false
			_auto_reconnect_after_drop = false
			_clear_session()
			room_left.emit(payload)
		Protocol.SESSION_STATUS:
			var session_state := str(payload.get("status", "invalid"))
			if session_state != "active":
				_clear_session()
			session_status.emit(payload)
		Protocol.NICKNAME_UPDATED:
			nickname_updated.emit(payload)
		Protocol.PLAYER_TAKEOVER:
			player_takeover.emit(payload)
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
			if _leave_pending and error_code in ["NOT_IN_ROOM", "ROOM_NOT_FOUND", "RECONNECT_FAILED"]:
				var finished_payload := _leave_payload.duplicate()
				_leave_pending = false
				_attached_to_room = false
				_clear_session()
				room_left.emit(finished_payload)
				return
			if error_code == "RECONNECT_FAILED" or (error_code == "ROOM_NOT_FOUND" and not reconnect_token.is_empty()):
				_clear_session()
			server_error.emit(error_code, str(payload.get("message", "Unknown error")))
		_:
			server_error.emit("UNKNOWN_TYPE", "Unknown server message: %s" % type)


func _send_detached_leave() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and _leave_pending:
		send_message(Protocol.LEAVE_SESSION, _leave_payload)

func _remember_session(payload: Dictionary) -> void:
	room_code = str(payload.get("room_code", room_code))
	room_role = str(payload.get("role", "spectator" if payload.has("spectator_id") else "player"))
	player_id = "" if room_role == "spectator" else str(payload.get("player_id", ""))
	spectator_id = str(payload.get("spectator_id", "")) if room_role == "spectator" else ""
	reconnect_token = str(payload.get("reconnect_token", reconnect_token))
	_save_session()

func _save_session() -> void:
	var data := JSON.stringify({
		"room_code": room_code, "role": room_role, "player_id": player_id,
		"spectator_id": spectator_id, "reconnect_token": reconnect_token,
	})
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
	spectator_id = ""
	room_role = "player"
	reconnect_token = ""
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			storage.removeItem("boardgame_session")
	else:
		var config := ConfigFile.new()
		config.set_value("session", "data", "")
		config.save("user://network_session.cfg")

func _save_identity() -> void:
	var data := JSON.stringify({"player_id": identity_player_id, "nickname": nickname})
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			storage.setItem("boardgame_identity", data)
	else:
		var config := ConfigFile.new()
		config.set_value("identity", "data", data)
		config.save("user://player_identity.cfg")

func _load_identity() -> void:
	var data := ""
	if OS.has_feature("web"):
		var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
		if storage != null:
			data = str(storage.getItem("boardgame_identity"))
	else:
		var config := ConfigFile.new()
		if config.load("user://player_identity.cfg") == OK:
			data = str(config.get_value("identity", "data", ""))
	if data.is_empty() or data == "<null>":
		return
	var parsed: Variant = JSON.parse_string(data)
	if parsed is Dictionary:
		identity_player_id = str(parsed.get("player_id", ""))
		nickname = str(parsed.get("nickname", ""))

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
		spectator_id = str(parsed.get("spectator_id", ""))
		room_role = str(parsed.get("role", "spectator" if not spectator_id.is_empty() else "player"))
		reconnect_token = str(parsed.get("reconnect_token", ""))
