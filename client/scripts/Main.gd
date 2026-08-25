extends Node

@onready var lobby: LobbyUI = $Lobby
@onready var game: CamelOnlineGameController = $Game
var _resume_overlay: Control
var _resume_detail: Label

func _ready() -> void:
	lobby.room_entered.connect(_on_room_entered)
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	NetworkClient.room_left.connect(_on_room_left)
	NetworkClient.session_status.connect(_on_session_status)
	game.online_ui.leave_game_requested.connect(NetworkClient.leave_room)
	_build_resume_prompt()
	game.visible = false
	game.set_room_active(false)

func _on_room_entered(payload: Dictionary) -> void:
	lobby.visible = false
	game.visible = true
	game.set_room_active(true)
	game.start_room(payload)

func _on_connection_status_changed(status: String) -> void:
	if status != "Disconnected" or not game.visible:
		return
	# Keep the board and hand visible while NetworkClient attempts token reconnect.
	game.online_ui.show_error("연결이 끊겼습니다. 같은 플레이어로 다시 연결하는 중입니다...")

func _on_room_left(_payload: Dictionary) -> void:
	_hide_resume_prompt()
	game.clear_room()
	game.visible = false
	lobby.visible = true
	lobby.show_home("게임에서 나왔어요")

func _on_session_status(payload: Dictionary) -> void:
	if str(payload.get("status", "invalid")) != "active":
		_hide_resume_prompt()
		if str(payload.get("status", "")) == "finished":
			lobby.show_home("종료된 게임 세션을 정리했어요")
		return
	_resume_detail.text = "ROOM %s · %s · %s" % [
		str(payload.get("room_code", "")),
		str(payload.get("nickname", NetworkClient.nickname)),
		("ROUND %d" % int(payload.get("round", 0))) if int(payload.get("round", 0)) > 0 else "대기실",
	]
	_resume_overlay.visible = true

func _build_resume_prompt() -> void:
	_resume_overlay = Control.new()
	_resume_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resume_overlay.z_index = 200
	_resume_overlay.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.05, 0.72)
	_resume_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resume_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 270)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff3d8")
	style.border_color = Color("dc9d53")
	style.set_border_width_all(3)
	style.set_corner_radius_all(26)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "진행 중인 게임이 있어요"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("493528"))
	box.add_child(title)
	_resume_detail = Label.new()
	_resume_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_detail.add_theme_font_size_override("font_size", 17)
	_resume_detail.add_theme_color_override("font_color", Color("806044"))
	box.add_child(_resume_detail)
	var resume := Button.new()
	resume.text = "게임으로 돌아가기"
	resume.custom_minimum_size.y = 58
	resume.pressed.connect(func(): _hide_resume_prompt(); NetworkClient.resume_saved_session())
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "이 게임에서 나가기"
	leave.custom_minimum_size.y = 48
	leave.pressed.connect(func(): leave.disabled = true; NetworkClient.discard_saved_session())
	box.add_child(leave)
	add_child(_resume_overlay)

func _hide_resume_prompt() -> void:
	if _resume_overlay != null:
		_resume_overlay.visible = false
