class_name GameManager
extends Node3D

const NETWORK_SEND_INTERVAL := 1.0 / 20.0
const PLAYER_SCENE := preload("res://scenes/Player.tscn")

@onready var players_root: Node3D = $Players
@onready var room_label: Label = $HUD/RoomLabel
@onready var status_label: Label = $HUD/StatusLabel

var room_code := ""
var local_player_id := ""
var players: Dictionary = {}
var _send_elapsed := 0.0
var _input_sequence := 0
var _touch_up := false
var _touch_down := false
var _touch_left := false
var _touch_right := false

func _ready() -> void:
	NetworkClient.player_joined.connect(_on_player_joined)
	NetworkClient.player_left.connect(_on_player_left)
	NetworkClient.player_state.connect(_on_player_state)
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	$HUD/Controls/Up.button_down.connect(func() -> void: _touch_up = true)
	$HUD/Controls/Up.button_up.connect(func() -> void: _touch_up = false)
	$HUD/Controls/Down.button_down.connect(func() -> void: _touch_down = true)
	$HUD/Controls/Down.button_up.connect(func() -> void: _touch_down = false)
	$HUD/Controls/Left.button_down.connect(func() -> void: _touch_left = true)
	$HUD/Controls/Left.button_up.connect(func() -> void: _touch_left = false)
	$HUD/Controls/Right.button_down.connect(func() -> void: _touch_right = true)
	$HUD/Controls/Right.button_up.connect(func() -> void: _touch_right = false)

func start_room(payload: Dictionary) -> void:
	clear_room()
	room_code = str(payload.get("room_code", ""))
	local_player_id = str(payload.get("player_id", ""))
	room_label.text = "ROOM: %s" % room_code
	for player_data in payload.get("players", []):
		_spawn_or_update_player(player_data as Dictionary, true)

func clear_room() -> void:
	for child in players_root.get_children():
		child.queue_free()
	players.clear()
	room_code = ""
	local_player_id = ""

func _process(delta: float) -> void:
	if local_player_id.is_empty() or not visible:
		return
	_send_elapsed += delta
	if _send_elapsed < NETWORK_SEND_INTERVAL:
		return
	_send_elapsed = fmod(_send_elapsed, NETWORK_SEND_INTERVAL)
	_input_sequence += 1
	NetworkClient.send_player_input(_movement_input(), _input_sequence)

func _movement_input() -> Vector2:
	var keyboard := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)),
	)
	var touch := Vector2(
		float(_touch_right) - float(_touch_left),
		float(_touch_down) - float(_touch_up),
	)
	var combined := keyboard + touch
	return combined.normalized() if combined.length_squared() > 1.0 else combined

func _spawn_or_update_player(data: Dictionary, snap: bool = false) -> void:
	var id := str(data.get("player_id", ""))
	if id.is_empty():
		return
	if players.has(id):
		(players[id] as NetworkPlayer).apply_state(data, snap)
		return
	var player := PLAYER_SCENE.instantiate() as NetworkPlayer
	players_root.add_child(player)
	players[id] = player
	player.setup(data, id == local_player_id)

func _on_player_joined(payload: Dictionary) -> void:
	_spawn_or_update_player(payload.get("player", {}) as Dictionary, true)

func _on_player_left(player_id: String) -> void:
	if not players.has(player_id):
		return
	(players[player_id] as NetworkPlayer).queue_free()
	players.erase(player_id)

func _on_player_state(payload: Dictionary) -> void:
	if str(payload.get("room_code", "")) != room_code:
		return
	for player_data in payload.get("players", []):
		_spawn_or_update_player(player_data as Dictionary)

func _on_connection_status_changed(status: String) -> void:
	status_label.text = status

