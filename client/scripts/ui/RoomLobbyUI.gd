class_name CamelRoomLobbyUI
extends CanvasLayer

signal start_requested(fill_cpu: bool)
signal cpu_count_requested(count: int)

var _root: ColorRect
var _panel: PanelContainer
var _margin: MarginContainer
var _content: VBoxContainer
var _title: Label
var _room_label: Label
var _copy_button: Button
var _slots: VBoxContainer
var _host_controls: VBoxContainer
var _start_button: Button
var _fill_cpu: Button
var _hint: Label
var _room_code := ""
var _cpu_count := 0
var _max_slots := 4

func _ready() -> void:
	_root = ColorRect.new()
	_root.color = Color("101827")
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _root.add_child(center)
	_panel = PanelContainer.new(); center.add_child(_panel)
	_margin = MarginContainer.new(); _panel.add_child(_margin)
	_content = VBoxContainer.new(); _margin.add_child(_content)
	_title = Label.new(); _title.text = "친구들과 경주 준비"; _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _content.add_child(_title)
	var code_row := HBoxContainer.new(); code_row.alignment = BoxContainer.ALIGNMENT_CENTER; _content.add_child(code_row)
	_room_label = Label.new(); _room_label.add_theme_font_size_override("font_size", 34); _room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; code_row.add_child(_room_label)
	_copy_button = Button.new(); _copy_button.text = "코드 복사"; _copy_button.pressed.connect(func(): DisplayServer.clipboard_set(_room_code)); code_row.add_child(_copy_button)
	_slots = VBoxContainer.new(); _content.add_child(_slots)
	_host_controls = VBoxContainer.new(); _content.add_child(_host_controls)
	var fill_center := CenterContainer.new(); _host_controls.add_child(fill_center)
	_fill_cpu = Button.new(); _fill_cpu.toggle_mode = true; _fill_cpu.button_pressed = true; _fill_cpu.text = "빈 자리 CPU로 채우기  켜짐"; _fill_cpu.toggled.connect(func(enabled: bool): _fill_cpu.text = "빈 자리 CPU로 채우기  %s" % ("켜짐" if enabled else "꺼짐")); fill_center.add_child(_fill_cpu)
	_start_button = Button.new(); _start_button.text = "GAME START"; _start_button.pressed.connect(func(): start_requested.emit(_fill_cpu.button_pressed)); _content.add_child(_start_button)
	_hint = Label.new(); _hint.text = "방장만 시작할 수 있습니다 · 접속이 끊겨도 60초 안에 돌아오면 복구됩니다"; _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _content.add_child(_hint)
	_apply_responsive_style()
	get_viewport().size_changed.connect(_apply_responsive_style)

func _apply_responsive_style() -> void:
	var physical_width := maxi(1, get_window().size.x)
	var ui_scale := maxf(1.0, get_viewport().get_visible_rect().size.x / float(physical_width))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("fff4d8")
	panel_style.border_color = Color("e7b85f")
	panel_style.set_border_width_all(int(3 * ui_scale))
	panel_style.set_corner_radius_all(int(26 * ui_scale))
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.custom_minimum_size.x = 470 * ui_scale
	for side in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, int(26 * ui_scale))
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, int(22 * ui_scale))
	_content.add_theme_constant_override("separation", int(13 * ui_scale))
	_slots.add_theme_constant_override("separation", int(8 * ui_scale))
	_host_controls.add_theme_constant_override("separation", int(8 * ui_scale))
	_title.add_theme_font_size_override("font_size", int(31 * ui_scale))
	_title.modulate = Color("8f563d")
	_room_label.add_theme_font_size_override("font_size", int(34 * ui_scale))
	_room_label.modulate = Color("72513c")
	_copy_button.custom_minimum_size = Vector2(112, 44) * ui_scale
	_copy_button.add_theme_font_size_override("font_size", int(16 * ui_scale))
	_fill_cpu.add_theme_font_size_override("font_size", int(17 * ui_scale))
	_fill_cpu.add_theme_color_override("font_color", Color("6a5946"))
	_fill_cpu.custom_minimum_size = Vector2(270, 42) * ui_scale
	_hint.add_theme_font_size_override("font_size", int(14 * ui_scale))
	_hint.modulate = Color("756652")
	_start_button.custom_minimum_size.y = 60 * ui_scale
	_start_button.add_theme_font_size_override("font_size", int(21 * ui_scale))
	var start_style := StyleBoxFlat.new(); start_style.bg_color = Color("e7a83e"); start_style.set_corner_radius_all(int(18 * ui_scale))
	_start_button.add_theme_stylebox_override("normal", start_style)
	_start_button.add_theme_stylebox_override("hover", start_style)
	_start_button.add_theme_stylebox_override("pressed", start_style)

func update_lobby(payload: Dictionary, local_player_id: String) -> void:
	_room_code = str(payload.get("room_code", "----"))
	_room_label.text = "ROOM  %s" % _room_code
	_max_slots = int(payload.get("max_slots", 4))
	var players := payload.get("players", []) as Array
	_cpu_count = 0
	for child in _slots.get_children(): child.queue_free()
	for index in _max_slots:
		var physical_width := maxi(1, get_window().size.x)
		var ui_scale := maxf(1.0, get_viewport().get_visible_rect().size.x / float(physical_width))
		var row := PanelContainer.new(); row.custom_minimum_size.y = 56 * ui_scale
		var row_style := StyleBoxFlat.new(); row_style.bg_color = Color("f4dfb8") if index < players.size() else Color("efe8d7"); row_style.set_corner_radius_all(int(14 * ui_scale)); row.add_theme_stylebox_override("panel", row_style)
		var label := Label.new(); label.add_theme_font_size_override("font_size", int(19 * ui_scale)); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.modulate = Color("6a5946")
		if index < players.size():
			var player := players[index] as Dictionary
			var is_cpu := bool(player.get("is_cpu", false)); if is_cpu: _cpu_count += 1
			label.text = "%s P%d  %s%s%s" % ["CPU" if is_cpu else "HOST" if bool(player.get("is_host", false)) else "PLAYER", index + 1, str(player.get("nickname", "")), "  방장" if bool(player.get("is_host", false)) else "", "  연결 끊김" if not bool(player.get("connected", true)) else "  준비"]
		else: label.text = "○ P%d  기다리는 중..." % (index + 1)
		row.add_child(label); _slots.add_child(row)
	var is_host := str(payload.get("host_player_id", "")) == local_player_id
	_host_controls.visible = is_host and not bool(payload.get("started", false))
	_start_button.visible = is_host and not bool(payload.get("started", false))
	_start_button.disabled = bool(payload.get("started", false))

func show_game() -> void:
	_root.visible = false
