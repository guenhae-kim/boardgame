class_name LobbyUI
extends Control

signal room_entered(payload: Dictionary)

@onready var nickname_input: LineEdit = $MenuCard/Margin/Content/Nickname
@onready var nickname_label: Label = $MenuCard/Margin/Content/NicknameLabel
@onready var identity_name: Label = $MenuCard/Margin/Content/IdentityName
@onready var change_nickname: Button = $MenuCard/Margin/Content/ChangeNickname
@onready var create_button: Button = $MenuCard/Margin/Content/CreateButton
@onready var join_button: Button = $MenuCard/Margin/Content/JoinButton
@onready var status_label: Label = $MenuCard/Margin/Content/Status
@onready var join_sheet: CamelJoinRoomSheet = $JoinRoomSheet
@onready var toast: CamelToast = $Toast
var _network: Node


func _ready() -> void:
	_network = get_node("/root/NetworkClient")
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_sheet.join_requested.connect(_on_join_code_submitted)
	nickname_input.text_submitted.connect(func(_value: String): _on_create_pressed())
	change_nickname.pressed.connect(_toggle_nickname_edit)
	_network.identity_changed.connect(func(_value: String): _apply_identity_state())
	_network.connection_status_changed.connect(_on_connection_status_changed)
	_network.room_created.connect(_on_room_entered)
	_network.room_joined.connect(_on_room_entered)
	_network.spectator_joined.connect(_on_room_entered)
	_network.server_error.connect(_on_server_error)
	$TopBar/SoundButton.pressed.connect(func(): toast.show_message("사운드 설정은 준비 중이에요"))
	_on_connection_status_changed("Connecting")
	_apply_identity_state()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _on_create_pressed() -> void:
	var nickname := _nickname()
	if nickname.is_empty():
		toast.show_message("먼저 닉네임을 입력해 주세요")
		nickname_input.grab_focus()
		return
	_set_actions_enabled(false)
	status_label.text = "새로운 테이블을 준비하는 중…"
	_network.create_room(nickname)


func _on_join_pressed() -> void:
	if _nickname().is_empty():
		toast.show_message("먼저 닉네임을 입력해 주세요")
		nickname_input.grab_focus()
		return
	join_sheet.show_sheet()


func _on_join_code_submitted(code: String, role: String) -> void:
	join_sheet.hide_sheet()
	_set_actions_enabled(false)
	status_label.text = "TV 관전 화면을 준비하는 중…" if role == "spectator" else "친구의 방을 찾는 중…"
	if role == "spectator":
		_network.join_spectator(code, _nickname())
	else:
		_network.join_room(code, _nickname())


func _nickname() -> String:
	return (nickname_input.text if nickname_input.visible else str(_network.nickname)).strip_edges().left(20)

func _apply_identity_state() -> void:
	var known: bool = bool(_network.has_identity())
	identity_name.visible = known
	nickname_input.visible = not known
	change_nickname.visible = known
	nickname_label.text = "다시 만나 반가워요!" if known else "처음 오셨네요! 닉네임을 정해주세요"
	if known:
		identity_name.text = str(_network.nickname)

func _toggle_nickname_edit() -> void:
	if not nickname_input.visible:
		nickname_input.text = str(_network.nickname)
		nickname_input.visible = true
		identity_name.visible = false
		change_nickname.text = "닉네임 저장"
		nickname_input.grab_focus()
		return
	var value := nickname_input.text.strip_edges().left(20)
	if value.is_empty():
		toast.show_message("닉네임을 입력해 주세요")
		return
	_network.update_nickname(value)
	change_nickname.text = "닉네임 변경"
	_apply_identity_state()


func _on_connection_status_changed(status: String) -> void:
	match status:
		"Connected":
			status_label.text = "● 친구들과 만날 준비 완료"
			_set_actions_enabled(true)
		"Connecting":
			status_label.text = "도시에 연결하는 중…"
			_set_actions_enabled(false)
		"Disconnected":
			status_label.text = "연결을 다시 확인하고 있어요…"
			_set_actions_enabled(false)
			toast.show_message("서버와 연결이 잠시 끊어졌어요")
		_:
			status_label.text = "연결 상태를 확인하는 중…"


func _set_actions_enabled(enabled: bool) -> void:
	create_button.disabled = not enabled
	join_button.disabled = not enabled

func show_home(message: String = "") -> void:
	visible = true
	modulate.a = 1.0
	join_sheet.hide_sheet()
	_set_actions_enabled(_network != null and _network.is_connected_to_server())
	status_label.text = "● 친구들과 만날 준비 완료"
	if not message.is_empty():
		toast.show_message(message)


func _on_room_entered(payload: Dictionary) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	await tween.finished
	room_entered.emit(payload)


func _on_server_error(code: String, message: String) -> void:
	_set_actions_enabled(true)
	status_label.text = "● 친구들과 만날 준비 완료"
	var friendly := "문제가 생겼어요. 잠시 후 다시 시도해 주세요"
	match code:
		"ROOM_NOT_FOUND": friendly = "방을 찾지 못했어요 · 코드를 다시 확인해 주세요"
		"ROOM_FULL": friendly = "이 방은 이미 친구들로 가득 찼어요"
		"INVALID_ROOM_CODE": friendly = "방 코드는 영문과 숫자 4자리예요"
		"GAME_ALREADY_STARTED": friendly = "이미 경주가 시작된 방이에요"
		"NICKNAME_REQUIRED": friendly = "닉네임을 입력해 주세요"
		"CONNECTION_FAILED": friendly = "서버에 연결하지 못했어요"
	push_warning("Lobby server error %s: %s" % [code, message])
	toast.show_message(friendly, 3.0)
