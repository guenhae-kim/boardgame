class_name LobbyUI
extends Control

signal room_entered(payload: Dictionary)

@onready var nickname_input: LineEdit = $Center/Panel/Content/Nickname
@onready var room_code_input: LineEdit = $Center/Panel/Content/RoomCode
@onready var create_button: Button = $Center/Panel/Content/CreateButton
@onready var join_button: Button = $Center/Panel/Content/JoinButton
@onready var status_label: Label = $Center/Panel/Content/Status
@onready var error_label: Label = $Center/Panel/Content/Error

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	room_code_input.text_submitted.connect(func(_value: String) -> void: _on_join_pressed())
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	NetworkClient.room_created.connect(_on_room_entered)
	NetworkClient.room_joined.connect(_on_room_entered)
	NetworkClient.server_error.connect(_on_server_error)
	_on_connection_status_changed("Connecting")

func _on_create_pressed() -> void:
	error_label.text = ""
	var nickname := _nickname()
	if nickname.is_empty():
		error_label.text = "닉네임을 입력해 주세요."
		nickname_input.grab_focus()
		return
	NetworkClient.create_room(nickname)

func _on_join_pressed() -> void:
	error_label.text = ""
	var code := room_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		error_label.text = "Room Code는 4글자입니다."
		return
	var nickname := _nickname()
	if nickname.is_empty():
		error_label.text = "닉네임을 입력해 주세요."
		nickname_input.grab_focus()
		return
	NetworkClient.join_room(code, nickname)

func _nickname() -> String:
	var value := nickname_input.text.strip_edges()
	return value.left(20)

func _on_connection_status_changed(status: String) -> void:
	status_label.text = "Server: %s" % status
	var enabled := status == "Connected"
	create_button.disabled = not enabled
	join_button.disabled = not enabled
	if status == "Disconnected":
		error_label.text = "서버 연결이 끊어졌습니다. 페이지를 새로고침하세요."

func _on_room_entered(payload: Dictionary) -> void:
	room_entered.emit(payload)

func _on_server_error(code: String, message: String) -> void:
	error_label.text = "%s: %s" % [code, message]
