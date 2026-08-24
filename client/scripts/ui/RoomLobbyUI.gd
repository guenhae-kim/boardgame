class_name CamelRoomLobbyUI
extends CanvasLayer

signal start_requested(fill_cpu: bool)
signal cpu_count_requested(count: int)

var _root: ColorRect
var _room_label: Label
var _slots: VBoxContainer
var _host_controls: HBoxContainer
var _start_button: Button
var _cpu_count := 0
var _max_slots := 4

func _ready() -> void:
	_root = ColorRect.new()
	_root.color = Color("101827")
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _root.add_child(center)
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(460, 0); center.add_child(panel)
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 24); margin.add_theme_constant_override("margin_right", 24); margin.add_theme_constant_override("margin_top", 22); margin.add_theme_constant_override("margin_bottom", 22); panel.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12); margin.add_child(box)
	var title := Label.new(); title.text = "친구들과 경주 준비"; title.add_theme_font_size_override("font_size", 30); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title)
	_room_label = Label.new(); _room_label.add_theme_font_size_override("font_size", 24); _room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(_room_label)
	_slots = VBoxContainer.new(); _slots.add_theme_constant_override("separation", 8); box.add_child(_slots)
	_host_controls = HBoxContainer.new(); _host_controls.add_theme_constant_override("separation", 8); box.add_child(_host_controls)
	var minus := Button.new(); minus.text = "CPU 빼기"; minus.pressed.connect(func(): cpu_count_requested.emit(maxi(0, _cpu_count - 1))); _host_controls.add_child(minus)
	var plus := Button.new(); plus.text = "CPU 추가"; plus.pressed.connect(func(): cpu_count_requested.emit(mini(_max_slots - 1, _cpu_count + 1))); _host_controls.add_child(plus)
	_start_button = Button.new(); _start_button.text = "빈 자리 CPU로 채우고 게임 시작"; _start_button.custom_minimum_size.y = 58; _start_button.pressed.connect(func(): start_requested.emit(true)); box.add_child(_start_button)
	var hint := Label.new(); hint.text = "방장만 시작할 수 있습니다 · 접속이 끊겨도 60초 안에 돌아오면 복구됩니다"; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(hint)

func update_lobby(payload: Dictionary, local_player_id: String) -> void:
	_room_label.text = "ROOM  %s" % str(payload.get("room_code", "----"))
	_max_slots = int(payload.get("max_slots", 4))
	var players := payload.get("players", []) as Array
	_cpu_count = 0
	for child in _slots.get_children(): child.queue_free()
	for index in _max_slots:
		var row := PanelContainer.new(); row.custom_minimum_size.y = 54
		var label := Label.new(); label.add_theme_font_size_override("font_size", 19); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if index < players.size():
			var player := players[index] as Dictionary
			var is_cpu := bool(player.get("is_cpu", false)); if is_cpu: _cpu_count += 1
			label.text = "%s  %s%s%s" % ["CPU" if is_cpu else "PLAYER", str(player.get("nickname", "")), "  HOST" if bool(player.get("is_host", false)) else "", "  OFFLINE" if not bool(player.get("connected", true)) else "  READY"]
		else: label.text = "PLAYER %d  EMPTY" % (index + 1)
		row.add_child(label); _slots.add_child(row)
	var is_host := str(payload.get("host_player_id", "")) == local_player_id
	_host_controls.visible = is_host and not bool(payload.get("started", false))
	_start_button.visible = is_host and not bool(payload.get("started", false))
	_start_button.disabled = bool(payload.get("started", false))

func show_game() -> void:
	_root.visible = false
