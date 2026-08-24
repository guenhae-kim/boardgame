class_name CamelOnlineGameUI
extends CamelLocalGameUI

signal online_action_requested(action: CamelAction)
signal interaction_mode_changed(target_type: String, valid_ids: Array)
signal chat_send_requested(text: String)
signal sound_requested(cue: String)

const CAMEL_NAMES := {"blue": "파랑", "yellow": "노랑", "green": "초록", "red": "빨강", "purple": "보라"}
const CAMEL_UI_COLORS := {"blue": Color("4f91ff"), "yellow": Color("e8bd3f"), "green": Color("48bd70"), "red": Color("e56861"), "purple": Color("9a72d5")}

var _hand_row: HBoxContainer
var _hand_title: Label
var _hand_cards: Dictionary = {}
var _private_cards: Array = []
var _selected_camel := ""
var _interaction_mode := ""
var _can_act := false
var _local_player_id := ""
var _roll_button: Button
var _bet_button: Button
var _tile_button: Button
var _cancel_button: Button
var _tile_face_panel: PanelContainer
var _selected_space := -1
var _chat_button: Button
var _chat_badge: Label
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_lines: Array[String] = []
var _unread := 0
var _turn_box: VBoxContainer
var _timer_label: Label
var _turn_deadline_ms := 0
var _server_clock_offset_ms := 0
var _timer_is_mine := false
var _last_warning_second := -1
var _result_panel: PanelContainer
var _result_label: Label

func _build_top_hud() -> void:
	_top_panel = PanelContainer.new()
	_top_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_top_panel.add_theme_stylebox_override("panel", _panel_style(Color("23323b"), 0.92, Color("f2c66d"), 2, 20))
	_root.add_child(_top_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	_top_panel.add_child(margin)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	_turn_box = VBoxContainer.new()
	_turn_box.custom_minimum_size.x = 180
	content.add_child(_turn_box)
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 23)
	turn_label.modulate = Color("ffd778")
	_turn_box.add_child(turn_label)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.modulate = Color("dce8e6")
	_timer_label.visible = false
	_turn_box.add_child(_timer_label)
	order_label = Label.new()
	order_label.add_theme_font_size_override("font_size", 13)
	_turn_box.add_child(order_label)
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 11)
	phase_label.modulate = Color("8dd7df")
	_turn_box.add_child(phase_label)
	_player_row = HFlowContainer.new()
	_player_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_row.add_theme_constant_override("h_separation", 7)
	content.add_child(_player_row)
	_chat_button = Button.new()
	_chat_button.text = "채팅"
	_chat_button.custom_minimum_size = Vector2(72, 48)
	_chat_button.pressed.connect(_toggle_chat)
	content.add_child(_chat_button)
	_chat_badge = Label.new()
	_chat_badge.visible = false
	_chat_badge.modulate = Color("ff7c69")
	content.add_child(_chat_badge)
	players_label = Label.new()
	players_label.visible = false
	_build_result_panel()

func _process(_delta: float) -> void:
	if _turn_deadline_ms <= 0 or _timer_label == null:
		return
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0) + _server_clock_offset_ms
	var seconds := maxi(0, int(ceil(float(_turn_deadline_ms - now_ms) / 1000.0)))
	_timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_timer_label.modulate = Color("ff6f61") if seconds <= 10 else Color("f2c66d") if seconds <= 30 else Color("dce8e6")
	if _timer_is_mine and seconds <= 10 and seconds > 0 and seconds != _last_warning_second:
		_last_warning_second = seconds
		sound_requested.emit("timer_warning")

func set_turn_deadline(deadline_ms: int, server_time_ms: int, is_mine: bool) -> void:
	_turn_deadline_ms = deadline_ms
	_server_clock_offset_ms = server_time_ms - int(Time.get_unix_time_from_system() * 1000.0) if server_time_ms > 0 else 0
	_timer_is_mine = is_mine
	_last_warning_second = -1
	_timer_label.visible = deadline_ms > 0

func set_flow_state(phase_name: String, player_name: String, description: String, input_enabled: bool) -> void:
	super.set_flow_state(phase_name, player_name, description, input_enabled)
	turn_label.text = "내 차례!" if input_enabled else "%s의 차례" % player_name

func _build_action_bar() -> void:
	_action_panel = PanelContainer.new()
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_action_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff5dd"), 0.96, Color("cf8d57"), 3, 22))
	_root.add_child(_action_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	_action_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	var status := HBoxContainer.new()
	content.add_child(status)
	waiting_label = Label.new()
	waiting_label.add_theme_font_size_override("font_size", 18)
	waiting_label.modulate = Color("4b3528")
	status.add_child(waiting_label)
	description_label = Label.new()
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	description_label.modulate = Color("765a48")
	status.add_child(description_label)
	error_label = Label.new()
	error_label.visible = false
	error_label.modulate = Color("d64d4d")
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(error_label)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	content.add_child(body)
	var hand_box := VBoxContainer.new()
	hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(hand_box)
	_hand_title = Label.new()
	_hand_title.text = "내 손패 · 카드를 고른 뒤 보드의 1등/꼴등 영역에 놓으세요"
	_hand_title.modulate = Color("765a48")
	hand_box.add_child(_hand_title)
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", -18)
	hand_box.add_child(_hand_row)
	_action_buttons_row = GridContainer.new()
	_action_buttons_row.columns = 2
	body.add_child(_action_buttons_row)
	_roll_button = _online_button("주사위", func(): _submit(CamelAction.new(CamelAction.ROLL_DIE)), Color("e7a83e"))
	_bet_button = _online_button("구간 베팅", func(): _set_mode("bet", CamelGameState.RACE_CAMELS), Color("e06b62"))
	_tile_button = _online_button("관중 타일", func(): _set_mode("track", []), Color("55a89c"))
	_cancel_button = _online_button("선택 취소", cancel_selection, Color("8b8f94"))
	for button in [_roll_button, _bet_button, _tile_button, _cancel_button]:
		_action_buttons_row.add_child(button)
	# Parent compatibility: online mode deliberately has no dropdown form.
	camel_option = OptionButton.new(); bet_option = OptionButton.new(); space_spin = SpinBox.new()
	side_option = OptionButton.new(); partner_option = OptionButton.new(); _partner_button = Button.new()
	_selector_row = GridContainer.new(); _selector_row.visible = false
	_build_tile_face_panel()
	_build_chat_panel()

func refresh_state(rules: CamelGameRules) -> void:
	if rules == null or rules.state == null:
		return
	var state := rules.state
	var portrait := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
	var display_scale := _display_scale()
	order_label.text = "구간 %d · 주사위 %d/5 · 남은 %d회" % [state.leg_number, state.dice_history.size(), maxi(0, 5 - state.dice_history.size())]
	_rebuild_player_cards_if_needed(state.players)
	for index in state.players.size():
		var player := state.players[index] as Dictionary
		var player_id := str(player["id"])
		var current := player_id == str(state.current_player()["id"]) and state.phase != "GAME_OVER"
		var card := _player_cards[player_id] as PanelContainer
		var money := _money_labels[player_id] as Label
		money.text = "%s 코인 %d" % ["CPU ·" if bool(player.get("is_cpu", false)) else "", int(player["money"])]
		var card_labels := card.find_children("*", "Label", true, false)
		if not card_labels.is_empty():
			(card_labels[0] as Label).text = "%s%s● %s" % ["나 · " if player_id == _local_player_id else "", "CPU " if bool(player.get("is_cpu", false)) else "", str(player.get("name", player_id))]
			(card_labels[0] as Label).add_theme_font_size_override("font_size", int((13 if portrait else 15) * display_scale))
		money.add_theme_font_size_override("font_size", int((16 if portrait else 18) * display_scale))
		card.custom_minimum_size = (Vector2(88, 48) if portrait else Vector2(112, 58)) * display_scale
		card.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8") if current else Color("2d3540"), 0.96, PLAYER_COLORS[index], 4 if current else 0, 16))
		card.modulate = Color.WHITE if bool(player.get("connected", true)) else Color(0.5, 0.5, 0.5, 0.7)

func set_online_context(state: CamelGameState, private_state: Dictionary, local_player_id: String, can_act: bool) -> void:
	_local_player_id = local_player_id
	_can_act = can_act
	_private_cards = (private_state.get("final_cards", []) as Array).duplicate()
	refresh_state(_rules_view(state))
	_rebuild_hand()
	_roll_button.disabled = not can_act
	_bet_button.disabled = not can_act
	_tile_button.disabled = not can_act
	if not can_act:
		cancel_selection()
	_show_result(state)

func handle_board_target(target_type: String, target_id: String) -> void:
	if not _can_act or target_type != _interaction_mode:
		return
	match target_type:
		"bet":
			_submit(CamelAction.new(CamelAction.TAKE_LEG_BET, {"camel": target_id}))
		"prediction":
			if not _selected_camel.is_empty():
				_submit(CamelAction.new(CamelAction.FINAL_BET, {"camel": _selected_camel, "bet": target_id}))
		"track":
			_selected_space = int(target_id)
			_tile_face_panel.visible = true

func receive_chat(nickname: String, text: String) -> void:
	_chat_lines.append("%s: %s" % [nickname, text])
	if _chat_lines.size() > 50: _chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)
	if not _chat_panel.visible:
		_unread += 1
		_chat_badge.text = str(_unread)
		_chat_badge.visible = true

func cancel_selection() -> void:
	_selected_camel = ""
	_interaction_mode = ""
	_tile_face_panel.visible = false
	interaction_mode_changed.emit("", [])
	for button in _hand_cards.values():
		(button as Button).scale = Vector2.ONE

func _rebuild_hand() -> void:
	for child in _hand_row.get_children(): child.queue_free()
	_hand_cards.clear()
	var portrait := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
	var display_scale := _display_scale()
	_hand_row.add_theme_constant_override("separation", int((-12 if portrait else -18) * display_scale))
	for camel_id in _private_cards:
		var camel := str(camel_id)
		var card := Button.new()
		card.text = "%s\n최종 예측" % CAMEL_NAMES.get(camel, camel)
		card.custom_minimum_size = (Vector2(75, 90) if portrait else Vector2(105, 82)) * display_scale
		card.add_theme_font_size_override("font_size", int((16 if portrait else 16) * display_scale))
		card.pivot_offset = card.custom_minimum_size * 0.5
		var color: Color = CAMEL_UI_COLORS.get(camel, Color.GRAY)
		card.add_theme_stylebox_override("normal", _button_style(color, 1.0))
		card.add_theme_stylebox_override("hover", _button_style(color.lightened(0.12), 1.0))
		card.pressed.connect(func(): _select_card(camel))
		_hand_row.add_child(card)
		_hand_cards[camel] = card

func _select_card(camel: String) -> void:
	sound_requested.emit("card_select")
	_selected_camel = camel
	for key in _hand_cards:
		var card := _hand_cards[key] as Button
		var selected := str(key) == camel
		var tween := create_tween()
		tween.tween_property(card, "scale", Vector2(1.1, 1.1) if selected else Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	if _can_act:
		_set_mode("prediction", ["winner", "loser"])

func _set_mode(mode: String, ids: Array) -> void:
	if not _can_act: return
	_interaction_mode = mode
	interaction_mode_changed.emit(mode, ids)

func _submit(action: CamelAction) -> void:
	if not _can_act: return
	_can_act = false
	sound_requested.emit("ui")
	cancel_selection()
	online_action_requested.emit(action)

func _choose_tile_face(side: String) -> void:
	if _selected_space > 0:
		_submit(CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": _selected_space, "side": side}))

func _build_tile_face_panel() -> void:
	_tile_face_panel = PanelContainer.new()
	_tile_face_panel.visible = false
	_tile_face_panel.set_anchors_preset(Control.PRESET_CENTER)
	_tile_face_panel.position = Vector2(-150, -70)
	_tile_face_panel.size = Vector2(300, 140)
	_tile_face_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff0ce"), 1.0, Color("55a89c"), 3, 20))
	var box := VBoxContainer.new()
	_tile_face_panel.add_child(box)
	var title := Label.new(); title.text = "어떤 면으로 놓을까요?"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title)
	var row := HBoxContainer.new(); box.add_child(row)
	row.add_child(_online_button("오아시스 +1", func(): _choose_tile_face("oasis"), Color("4cbf91")))
	row.add_child(_online_button("신기루 -1", func(): _choose_tile_face("mirage"), Color("df7598")))
	_root.add_child(_tile_face_panel)

func _build_chat_panel() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.visible = false
	_chat_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_chat_panel.position = Vector2(-360, -230)
	_chat_panel.size = Vector2(340, 460)
	_chat_panel.add_theme_stylebox_override("panel", _panel_style(Color("23323b"), 0.98, Color("f2c66d"), 2, 18))
	var box := VBoxContainer.new(); _chat_panel.add_child(box)
	_chat_log = RichTextLabel.new(); _chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(_chat_log)
	var row := HBoxContainer.new(); box.add_child(row)
	_chat_input = LineEdit.new(); _chat_input.max_length = 200; _chat_input.placeholder_text = "메시지..."; _chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(_chat_input)
	var send := Button.new(); send.text = "보내기"; send.pressed.connect(_send_chat); row.add_child(send)
	_chat_input.text_submitted.connect(func(_text: String): _send_chat())
	_root.add_child(_chat_panel)

func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.position = Vector2(-190, -220)
	_result_panel.size = Vector2(380, 440)
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8"), 0.98, Color("f2c66d"), 4, 24))
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 24); margin.add_theme_constant_override("margin_right", 24); margin.add_theme_constant_override("margin_top", 22); margin.add_theme_constant_override("margin_bottom", 22); _result_panel.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 16); margin.add_child(box)
	var title := Label.new(); title.text = "경주 종료!"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 32); title.modulate = Color("bf704c"); box.add_child(title)
	_result_label = Label.new(); _result_label.add_theme_font_size_override("font_size", 21); _result_label.modulate = Color("4b3528"); _result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(_result_label)
	_root.add_child(_result_panel)

func _show_result(state: CamelGameState) -> void:
	if _result_panel == null:
		return
	_result_panel.visible = state.phase == "GAME_OVER"
	if not _result_panel.visible:
		return
	var standings := state.players.duplicate(true)
	standings.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("money", 0)) > int(b.get("money", 0)))
	var lines: Array[String] = []
	for index in standings.size():
		var player := standings[index] as Dictionary
		lines.append("%d위  %s%s   코인 %d" % [index + 1, "CPU · " if bool(player.get("is_cpu", false)) else "", str(player.get("name", "Player")), int(player.get("money", 0))])
	_result_label.text = "\n\n".join(lines)

func _toggle_chat() -> void:
	_chat_panel.visible = not _chat_panel.visible
	if _chat_panel.visible:
		_unread = 0; _chat_badge.visible = false; _chat_input.grab_focus()

func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	if text.is_empty(): return
	chat_send_requested.emit(text.left(200)); _chat_input.clear()

func _online_button(title: String, callback: Callable, color: Color) -> Button:
	var button := Button.new(); button.text = title; button.custom_minimum_size = Vector2(120, 48)
	button.add_theme_stylebox_override("normal", _button_style(color, 1.0)); button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.1), 1.0))
	button.add_theme_stylebox_override("disabled", _button_style(Color("92989c"), 0.6)); button.pressed.connect(func(): sound_requested.emit("ui"); callback.call()); _track(button); return button

func _rules_view(state: CamelGameState) -> CamelGameRules:
	var view := CamelGameRules.new(); view.load_state(state); return view

func _apply_responsive_layout() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var portrait := visible_size.y > visible_size.x
	var display_scale := _display_scale()
	_top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_left = 8 * display_scale if portrait else 14 * display_scale; _top_panel.offset_right = -8 * display_scale if portrait else -14 * display_scale; _top_panel.offset_top = 6 * display_scale if portrait else 12 * display_scale; _top_panel.offset_bottom = (135 if portrait else 118) * display_scale
	_action_panel.anchor_left = 0.02 if portrait else 0.08; _action_panel.anchor_right = 0.98 if portrait else 0.92
	_action_panel.anchor_top = 1.0; _action_panel.anchor_bottom = 1.0
	_action_panel.offset_left = 0; _action_panel.offset_right = 0; _action_panel.offset_top = (-165 if portrait else -154) * display_scale; _action_panel.offset_bottom = -6 * display_scale if portrait else -10 * display_scale
	if _action_buttons_row != null: _action_buttons_row.columns = 2
	if waiting_label != null:
		waiting_label.add_theme_font_size_override("font_size", int((22 if portrait else 18) * display_scale))
		description_label.add_theme_font_size_override("font_size", int((14 if portrait else 14) * display_scale))
		turn_label.add_theme_font_size_override("font_size", int((30 if portrait else 23) * display_scale))
		order_label.add_theme_font_size_override("font_size", int((16 if portrait else 13) * display_scale))
		phase_label.add_theme_font_size_override("font_size", int((13 if portrait else 11) * display_scale))
		_timer_label.add_theme_font_size_override("font_size", int((18 if portrait else 16) * display_scale))
		_hand_title.add_theme_font_size_override("font_size", int((12 if portrait else 14) * display_scale))
	for button in [_roll_button, _bet_button, _tile_button, _cancel_button]:
		if button != null:
			button.custom_minimum_size = (Vector2(62, 48) if portrait else Vector2(120, 48)) * display_scale
			button.add_theme_font_size_override("font_size", int((14 if portrait else 16) * display_scale))
	if _player_row != null:
		for card in _player_cards.values(): (card as PanelContainer).custom_minimum_size = (Vector2(88, 48) if portrait else Vector2(112, 58)) * display_scale
	if _chat_button != null:
		_chat_button.custom_minimum_size = (Vector2(48, 42) if portrait else Vector2(72, 48)) * display_scale
		_chat_button.add_theme_font_size_override("font_size", int((12 if portrait else 16) * display_scale))
	if _turn_box != null: _turn_box.custom_minimum_size.x = (140 if portrait else 180) * display_scale
	if _chat_panel != null:
		_chat_panel.position = Vector2(-360, -230) * display_scale; _chat_panel.size = Vector2(340, 460) * display_scale

func _display_scale() -> float:
	var physical_width := maxi(1, get_window().size.x)
	return maxf(1.0, get_viewport().get_visible_rect().size.x / float(physical_width))
