class_name CamelRoomLobbyUI
extends CanvasLayer

signal start_requested(fill_cpu: bool)
signal cpu_count_requested(count: int)
signal leave_requested
signal nickname_change_requested(nickname: String)

@onready var root: Control = $Root
@onready var _root: Control = $Root # Compatibility for existing flow diagnostics.
@onready var room_label: Label = $Root/LobbyPanel/Margin/Content/RoomCodePanel/CodeRow/CodeBlock/RoomCode
@onready var copy_button: Button = $Root/LobbyPanel/Margin/Content/RoomCodePanel/CodeRow/CopyButton
@onready var slots: Array[CamelPlayerLobbyCard] = [
	$Root/LobbyPanel/Margin/Content/Slots/Slot1,
	$Root/LobbyPanel/Margin/Content/Slots/Slot2,
	$Root/LobbyPanel/Margin/Content/Slots/Slot3,
	$Root/LobbyPanel/Margin/Content/Slots/Slot4,
]
@onready var host_controls: VBoxContainer = $Root/LobbyPanel/Margin/Content/HostControls
@onready var fill_cpu: CheckButton = $Root/LobbyPanel/Margin/Content/HostControls/CpuPanel/FillCpu
@onready var start_button: Button = $Root/LobbyPanel/Margin/Content/HostControls/StartButton
@onready var guest_hint: Label = $Root/LobbyPanel/Margin/Content/GuestHint
@onready var toast: CamelToast = $Root/Toast

var _room_code := ""


func _ready() -> void:
	copy_button.pressed.connect(_copy_room_code)
	start_button.pressed.connect(func(): start_requested.emit(fill_cpu.button_pressed))
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.3)
	for index in slots.size():
		slots[index].set_slot(index, {})
	_build_settings()


func update_lobby(payload: Dictionary, local_player_id: String) -> void:
	_room_code = str(payload.get("room_code", "----"))
	room_label.text = _room_code
	var players := payload.get("players", []) as Array
	for index in slots.size():
		var player := players[index] as Dictionary if index < players.size() else {}
		slots[index].set_slot(index, player)
	var is_host := str(payload.get("host_player_id", "")) == local_player_id
	var started := bool(payload.get("started", false))
	host_controls.visible = is_host and not started
	guest_hint.visible = not is_host and not started
	start_button.disabled = started


func show_game() -> void:
	if not root.visible:
		return
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.24)
	await tween.finished
	root.visible = false


func _copy_room_code() -> void:
	DisplayServer.clipboard_set(_room_code)
	toast.show_message("방 코드 복사 완료!")


func _build_settings() -> void:
	var settings_button := Button.new()
	settings_button.text = "⚙ 설정"
	settings_button.tooltip_text = "방 설정"
	settings_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings_button.position = Vector2(-138, 18)
	settings_button.size = Vector2(120, 54)
	root.add_child(settings_button)
	var panel := PanelContainer.new()
	panel.name = "LeaveRoomPanel"
	panel.visible = false
	panel.z_index = 100
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270, -220)
	panel.size = Vector2(540, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff4d8")
	style.border_color = Color("d99b5c")
	style.set_border_width_all(4)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(0.08, 0.04, 0.02, 0.4)
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "설정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var guide := Label.new()
	guide.text = "현재 방에서 나가 홈으로 돌아갈까요?"
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_font_size_override("font_size", 24)
	box.add_child(guide)
	var nickname_input := LineEdit.new()
	nickname_input.placeholder_text = "새 닉네임"
	nickname_input.max_length = 20
	nickname_input.custom_minimum_size.y = 60
	nickname_input.add_theme_font_size_override("font_size", 24)
	box.add_child(nickname_input)
	var nickname_button := Button.new()
	nickname_button.text = "닉네임 변경"
	nickname_button.custom_minimum_size.y = 58
	nickname_button.pressed.connect(func():
		var value := nickname_input.text.strip_edges().left(20)
		if not value.is_empty():
			nickname_change_requested.emit(value)
			nickname_input.clear())
	box.add_child(nickname_button)
	var leave_button := Button.new()
	leave_button.text = "게임 나가기"
	leave_button.custom_minimum_size.y = 72
	leave_button.add_theme_font_size_override("font_size", 28)
	leave_button.pressed.connect(func(): panel.visible = false; leave_requested.emit())
	box.add_child(leave_button)
	var cancel_button := Button.new()
	cancel_button.text = "계속 기다리기"
	cancel_button.custom_minimum_size.y = 60
	cancel_button.add_theme_font_size_override("font_size", 24)
	cancel_button.pressed.connect(func(): panel.visible = false)
	box.add_child(cancel_button)
	margin.add_child(box)
	panel.add_child(margin)
	root.add_child(panel)
	settings_button.pressed.connect(func(): panel.visible = not panel.visible)
