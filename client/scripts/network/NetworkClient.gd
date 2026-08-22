extends Node

signal connection_status_changed(status: String)
signal room_created(payload: Dictionary)
signal room_joined(payload: Dictionary)
signal player_joined(payload: Dictionary)
signal player_left(player_id: String)
signal player_state(payload: Dictionary)
signal server_error(code: String, message: String)

var _socket := WebSocketPeer.new()
var _last_state := WebSocketPeer.STATE_CLOSED
var _heartbeat_elapsed := 0.0
var _reconnect_elapsed := 0.0

func _ready() -> void:
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
			room_created.emit(payload)
		Protocol.ROOM_JOINED:
			room_joined.emit(payload)
		Protocol.PLAYER_JOINED:
			player_joined.emit(payload)
		Protocol.PLAYER_LEFT:
			player_left.emit(str(payload.get("player_id", "")))
		Protocol.PLAYER_STATE:
			player_state.emit(payload)
		Protocol.PING:
			send_message(Protocol.PONG, {"server_time": payload.get("server_time", 0)})
		Protocol.PONG:
			pass
		Protocol.ERROR:
			server_error.emit(str(payload.get("code", "ERROR")), str(payload.get("message", "Unknown error")))
		_:
			server_error.emit("UNKNOWN_TYPE", "Unknown server message: %s" % type)
