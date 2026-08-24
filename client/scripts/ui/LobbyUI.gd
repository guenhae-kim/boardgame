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
	$Center/Panel/Content/Title.text = "동물들의 테이블 경주"
	_apply_home_style()
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	room_code_input.text_submitted.connect(func(_value: String) -> void: _on_join_pressed())
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	NetworkClient.room_created.connect(_on_room_entered)
	NetworkClient.room_joined.connect(_on_room_entered)
	NetworkClient.server_error.connect(_on_server_error)
	_on_connection_status_changed("Connecting")
	get_viewport().size_changed.connect(_apply_home_style)

func _apply_home_style() -> void:
	var physical_width := maxi(1, get_window().size.x)
	var ui_scale := maxf(1.0, get_viewport().get_visible_rect().size.x / float(physical_width))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("fff4d8")
	panel_style.border_color = Color("e7b85f")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(int(26 * ui_scale))
	panel_style.content_margin_left = 28 * ui_scale
	panel_style.content_margin_right = 28 * ui_scale
	panel_style.content_margin_top = 26 * ui_scale
	panel_style.content_margin_bottom = 26 * ui_scale
	$Center/Panel.add_theme_stylebox_override("panel", panel_style)
	$Center/Panel.custom_minimum_size.x = 430 * ui_scale
	$Center/Panel/Content.add_theme_constant_override("separation", int(14 * ui_scale))
	$Center/Panel/Content/Title.modulate = Color("8f563d")
	$Center/Panel/Content/Title.add_theme_font_size_override("font_size", int(34 * ui_scale))
	for button in [create_button, join_button]:
		var normal := StyleBoxFlat.new(); normal.bg_color = Color("e7a83e") if button == create_button else Color("55a89c"); normal.set_corner_radius_all(int(18 * ui_scale))
		var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = normal.bg_color.lightened(0.08)
		var disabled := normal.duplicate() as StyleBoxFlat; disabled.bg_color = Color("9ca5a3")
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("disabled", disabled)
		button.custom_minimum_size.y = 58 * ui_scale
		button.add_theme_font_size_override("font_size", int(20 * ui_scale))
	for field in [nickname_input, room_code_input]:
		var field_style := StyleBoxFlat.new(); field_style.bg_color = Color("ffffff"); field_style.border_color = Color("d8b987"); field_style.set_border_width_all(2); field_style.set_corner_radius_all(int(14 * ui_scale)); field_style.content_margin_left = 16 * ui_scale; field_style.content_margin_right = 16 * ui_scale
		field.add_theme_stylebox_override("normal", field_style)
		field.custom_minimum_size.y = 52 * ui_scale
		field.add_theme_font_size_override("font_size", int(19 * ui_scale))
	for label in [$Center/Panel/Content/NicknameLabel, status_label, error_label]:
		label.add_theme_font_size_override("font_size", int(16 * ui_scale))

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
