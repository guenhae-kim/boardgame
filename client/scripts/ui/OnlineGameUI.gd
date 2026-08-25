class_name CamelOnlineGameUI
extends CamelLocalGameUI

signal online_action_requested(action: CamelAction)
signal interaction_mode_changed(target_type: String, valid_ids: Array)
signal chat_send_requested(text: String)
signal sound_requested(cue: String)
signal overview_requested

const CAMEL_NAMES := {"blue": "파랑", "yellow": "노랑", "green": "초록", "red": "빨강", "purple": "보라"}
const CAMEL_UI_COLORS := {"blue": Color("4f91ff"), "yellow": Color("e8bd3f"), "green": Color("48bd70"), "red": Color("e56861"), "purple": Color("9a72d5")}

var _hud_layer: Control
var _history_slots: Array[PanelContainer] = []
var _ticket_rows: Dictionary = {}
var _hud_timer_labels: Dictionary = {}
var _hand_row: HBoxContainer
var _hand_cards: Dictionary = {}
var _private_cards: Array = []
var _selected_camel := ""
var _interaction_mode := ""
var _can_act := false
var _local_player_id := ""
var _roll_button: Button
var _spectator_card: Button
var _cancel_button: Button
var _tile_face_panel: PanelContainer
var _selected_space := -1
var _chat_button: Button
var _emote_button: Button
var _overview_button: Button
var _chat_badge: Label
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _emote_panel: PanelContainer
var _chat_lines: Array[String] = []
var _unread := 0
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
	_top_panel.add_theme_stylebox_override("panel", _panel_style(Color("253942"), 0.90, Color("f0c56b"), 2, 16))
	_root.add_child(_top_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	_top_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	order_label = Label.new()
	order_label.modulate = Color("ffe3a0")
	order_label.add_theme_font_size_override("font_size", 14)
	row.add_child(order_label)
	for index in 5:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(29, 27)
		slot.add_theme_stylebox_override("panel", _panel_style(Color("17272f"), 0.88, Color("61747a"), 1, 8))
		var value_label := Label.new()
		value_label.name = "Value"
		value_label.text = "·"
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override("font_size", 10)
		slot.add_child(value_label)
		row.add_child(slot)
		_history_slots.append(slot)
	_timer_label = Label.new()
	_timer_label.visible = false
	_timer_label.add_theme_font_size_override("font_size", 14)
	row.add_child(_timer_label)
	turn_label = Label.new()
	turn_label.visible = false
	phase_label = Label.new()
	phase_label.visible = false
	players_label = Label.new()
	players_label.visible = false
	_player_row = HFlowContainer.new()
	_player_row.visible = false
	_root.add_child(_player_row)
	_hud_layer = Control.new()
	_hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud_layer)
	_build_right_rail()
	_build_result_panel()


func _build_action_bar() -> void:
	_action_panel = PanelContainer.new()
	_action_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_action_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff2d3"), 0.91, Color("d99b5c"), 2, 18))
	_root.add_child(_action_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	_action_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	waiting_label = Label.new()
	waiting_label.modulate = Color("604735")
	waiting_label.add_theme_font_size_override("font_size", 13)
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(waiting_label)
	description_label = Label.new()
	description_label.visible = false
	box.add_child(description_label)
	error_label = Label.new()
	error_label.visible = false
	error_label.modulate = Color("cf5252")
	box.add_child(error_label)
	var hand_line := HBoxContainer.new()
	hand_line.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_line.add_theme_constant_override("separation", 3)
	box.add_child(hand_line)
	_roll_button = _online_button("주사위", func(): _submit(CamelAction.new(CamelAction.ROLL_DIE)), Color("e9a83c"))
	_roll_button.custom_minimum_size = Vector2(58, 58)
	hand_line.add_child(_roll_button)
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_line.add_child(_hand_row)
	_cancel_button = _online_button("취소", cancel_selection, Color("89989d"))
	_cancel_button.custom_minimum_size = Vector2(50, 42)
	hand_line.add_child(_cancel_button)
	# Compatibility placeholders required by the local base class. They remain hidden.
	camel_option = OptionButton.new()
	bet_option = OptionButton.new()
	space_spin = SpinBox.new()
	side_option = OptionButton.new()
	partner_option = OptionButton.new()
	_partner_button = Button.new()
	_selector_row = GridContainer.new()
	_selector_row.visible = false
	_action_buttons_row = GridContainer.new()
	_action_buttons_row.visible = false
	_build_tile_face_panel()
	_build_chat_panel()
	_build_emote_panel()


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_root.add_child(_debug_panel)
	log_view = RichTextLabel.new()
	_debug_panel.add_child(log_view)


func _process(_delta: float) -> void:
	if _turn_deadline_ms <= 0 or _timer_label == null:
		return
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0) + _server_clock_offset_ms
	var seconds := maxi(0, int(ceil(float(_turn_deadline_ms - now_ms) / 1000.0)))
	var timer_text := "%02d:%02d" % [seconds / 60, seconds % 60]
	_timer_label.text = timer_text
	_timer_label.modulate = Color("ff6f61") if seconds <= 10 else Color("f2c66d") if seconds <= 30 else Color("e7efed")
	for player_id in _hud_timer_labels:
		var hud_timer := _hud_timer_labels[player_id] as Label
		if hud_timer.visible:
			hud_timer.text = timer_text
			hud_timer.modulate = _timer_label.modulate
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
	phase_label.text = phase_name
	turn_label.text = "내 차례!" if input_enabled else "%s의 차례" % player_name
	waiting_label.text = "내 차례 · 카드나 보드를 직접 눌러 행동하세요" if input_enabled else "%s 행동 중 · 보드와 손패는 계속 볼 수 있어요" % player_name
	description_label.text = description


func refresh_state(rules: CamelGameRules) -> void:
	if rules == null or rules.state == null:
		return
	var state := rules.state
	order_label.text = "ROUND %d   주사위 %d/5" % [state.leg_number, state.dice_history.size()]
	_refresh_history(state.dice_history)
	_rebuild_player_cards_if_needed(state.players)
	var current_id := str(state.current_player().get("id", "")) if not state.players.is_empty() else ""
	for index in state.players.size():
		var player := state.players[index] as Dictionary
		var player_id := str(player.get("id", ""))
		var current := player_id == current_id and state.phase != "GAME_OVER"
		var card := _player_cards[player_id] as PanelContainer
		var money := _money_labels[player_id] as Label
		money.text = "코인 %d" % int(player.get("money", 0))
		var name_label := card.get_node("Margin/Box/Header/Name") as Label
		name_label.text = "%s%s" % ["나 · " if player_id == _local_player_id else "", str(player.get("name", player_id))]
		(card.get_node("Margin/Box/Header/CPU") as Label).text = "CPU" if bool(player.get("is_cpu", false)) else ""
		(_hud_timer_labels[player_id] as Label).visible = current and _turn_deadline_ms > 0
		card.add_theme_stylebox_override("panel", _panel_style(Color("fff1cf") if current else Color("25343d"), 0.94, PLAYER_COLORS[index], 3 if current else 1, 14))
		card.modulate = Color.WHITE if bool(player.get("connected", true)) else Color(0.55, 0.55, 0.55, 0.72)
		_rebuild_ticket_row(player_id, player.get("leg_tickets", []) as Array)
	_show_result(state)


func set_online_context(state: CamelGameState, private_state: Dictionary, local_player_id: String, can_act: bool) -> void:
	_local_player_id = local_player_id
	_can_act = can_act
	_private_cards = (private_state.get("final_cards", []) as Array).duplicate()
	refresh_state(_rules_view(state))
	_rebuild_hand()
	_roll_button.disabled = not can_act
	_spectator_card.disabled = not can_act
	_cancel_button.visible = can_act
	if can_act:
		_set_mode("bet", CamelGameState.RACE_CAMELS)
	else:
		cancel_selection()


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


func receive_chat(nickname: String, text: String, _player_id: String = "") -> void:
	_chat_lines.append("%s: %s" % [nickname, text])
	if _chat_lines.size() > 50:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)
	if not _chat_panel.visible:
		_unread += 1
		_chat_badge.text = str(_unread)
		_chat_badge.visible = true


func cancel_selection() -> void:
	_selected_camel = ""
	_interaction_mode = ""
	_selected_space = -1
	_tile_face_panel.visible = false
	interaction_mode_changed.emit("", [])
	for button in _hand_cards.values():
		(button as Button).scale = Vector2.ONE
		(button as Button).modulate = Color.WHITE
	if _spectator_card != null:
		_spectator_card.scale = Vector2.ONE
	if _can_act:
		_set_mode("bet", CamelGameState.RACE_CAMELS)


func play_ticket_gain(player_id: String, camel: String, value: int) -> void:
	if not _player_cards.has(player_id):
		return
	var badge := Label.new()
	badge.text = "%s %d" % [str(CAMEL_NAMES.get(camel, camel)), value]
	badge.add_theme_font_size_override("font_size", 18)
	badge.modulate = CAMEL_UI_COLORS.get(camel, Color.WHITE)
	badge.position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.46)
	_root.add_child(badge)
	var target := (_player_cards[player_id] as Control).global_position + Vector2(22, 50)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(badge, "position", target, 0.48)
	tween.parallel().tween_property(badge, "scale", Vector2(0.72, 0.72), 0.48)
	await tween.finished
	badge.queue_free()


func _rebuild_hand() -> void:
	for child in _hand_row.get_children():
		child.queue_free()
	_hand_cards.clear()
	var ui_scale := _display_scale()
	_hand_row.add_theme_constant_override("separation", int(-10 * ui_scale))
	for camel_value in _private_cards:
		var camel := str(camel_value)
		var card := Button.new()
		card.text = "%s\n동물 카드" % CAMEL_NAMES.get(camel, camel)
		card.custom_minimum_size = Vector2(62, 76) * ui_scale
		card.pivot_offset = Vector2(31, 70) * ui_scale
		card.add_theme_font_size_override("font_size", int(12 * ui_scale))
		var color: Color = CAMEL_UI_COLORS.get(camel, Color.GRAY)
		card.add_theme_stylebox_override("normal", _button_style(color, 1.0))
		card.add_theme_stylebox_override("disabled", _button_style(color.darkened(0.25), 0.7))
		card.pressed.connect(func(): _select_card(camel))
		_hand_row.add_child(card)
		_hand_cards[camel] = card
	_spectator_card = Button.new()
	_spectator_card.text = "+1 / -1\n응원"
	_spectator_card.custom_minimum_size = Vector2(64, 76) * ui_scale
	_spectator_card.pivot_offset = Vector2(32, 70) * ui_scale
	_spectator_card.add_theme_font_size_override("font_size", int(12 * ui_scale))
	_spectator_card.add_theme_stylebox_override("normal", _button_style(Color("59ad9d"), 1.0))
	_spectator_card.pressed.connect(_select_spectator)
	_hand_row.add_child(_spectator_card)


func _select_card(camel: String) -> void:
	if not _can_act:
		return
	sound_requested.emit("card_select")
	_selected_camel = camel
	for key in _hand_cards:
		var card := _hand_cards[key] as Button
		var selected := str(key) == camel
		card.modulate = Color.WHITE if selected else Color(0.68, 0.68, 0.68, 0.82)
		create_tween().tween_property(card, "scale", Vector2(1.12, 1.12) if selected else Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	_set_mode("prediction", ["winner", "loser"])


func _select_spectator() -> void:
	if not _can_act:
		return
	sound_requested.emit("card_select")
	_selected_camel = ""
	create_tween().tween_property(_spectator_card, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK)
	_set_mode("track", [])


func _set_mode(mode: String, ids: Array) -> void:
	if not _can_act:
		return
	_interaction_mode = mode
	interaction_mode_changed.emit(mode, ids)


func _submit(action: CamelAction) -> void:
	if not _can_act:
		return
	_can_act = false
	sound_requested.emit("ui")
	cancel_selection()
	online_action_requested.emit(action)


func _choose_tile_face(side: String) -> void:
	if _selected_space > 0:
		_submit(CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": _selected_space, "side": side}))


func _rebuild_player_cards_if_needed(players: Array) -> void:
	if _player_cards.size() == players.size():
		return
	for child in _hud_layer.get_children():
		child.queue_free()
	_player_cards.clear()
	_money_labels.clear()
	_ticket_rows.clear()
	_hud_timer_labels.clear()
	for index in players.size():
		var player := players[index] as Dictionary
		var player_id := str(player.get("id", ""))
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 5)
		margin.add_theme_constant_override("margin_bottom", 5)
		card.add_child(margin)
		var box := VBoxContainer.new()
		box.name = "Box"
		box.add_theme_constant_override("separation", 1)
		margin.add_child(box)
		var header := HBoxContainer.new()
		header.name = "Header"
		box.add_child(header)
		var face := Label.new()
		face.text = ["●", "◆", "▲", "■"][index % 4]
		face.modulate = PLAYER_COLORS[index]
		header.add_child(face)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header.add_child(name_label)
		var cpu := Label.new()
		cpu.name = "CPU"
		cpu.add_theme_font_size_override("font_size", 9)
		cpu.modulate = Color("9ecbd0")
		header.add_child(cpu)
		var info := HBoxContainer.new()
		box.add_child(info)
		var money := Label.new()
		money.modulate = Color("ffd36b")
		money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(money)
		var timer := Label.new()
		timer.visible = false
		info.add_child(timer)
		var tickets := HBoxContainer.new()
		tickets.name = "Tickets"
		tickets.add_theme_constant_override("separation", -3)
		box.add_child(tickets)
		_hud_layer.add_child(card)
		_player_cards[player_id] = card
		_money_labels[player_id] = money
		_ticket_rows[player_id] = tickets
		_hud_timer_labels[player_id] = timer
	_apply_responsive_layout()


func _rebuild_ticket_row(player_id: String, tickets: Array) -> void:
	if not _ticket_rows.has(player_id):
		return
	var row := _ticket_rows[player_id] as HBoxContainer
	var ui_scale := _display_scale()
	for child in row.get_children():
		child.queue_free()
	for ticket_value in tickets:
		var ticket := ticket_value as Dictionary
		var camel := str(ticket.get("camel", ""))
		var badge := Label.new()
		badge.text = "%d" % int(ticket.get("value", 0))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(24, 18) * ui_scale
		badge.add_theme_font_size_override("font_size", int(10 * ui_scale))
		badge.add_theme_stylebox_override("normal", _panel_style(CAMEL_UI_COLORS.get(camel, Color.GRAY), 1.0, Color.WHITE, 1, 5))
		row.add_child(badge)


func _refresh_history(history: Array) -> void:
	for index in _history_slots.size():
		var slot := _history_slots[index]
		var value_label := slot.get_node("Value") as Label
		if index < history.size():
			var result := history[index] as Dictionary
			var camel := str(result.get("camel", result.get("die", "")))
			value_label.text = "%s%d" % [str(CAMEL_NAMES.get(camel, camel)).left(1), int(result.get("value", 0))]
			slot.add_theme_stylebox_override("panel", _panel_style(CAMEL_UI_COLORS.get(camel, Color.GRAY), 1.0, Color.WHITE, 1, 8))
		else:
			value_label.text = "·"
			slot.add_theme_stylebox_override("panel", _panel_style(Color("17272f"), 0.88, Color("61747a"), 1, 8))


func _build_right_rail() -> void:
	_chat_button = _rail_button("CHAT", _toggle_chat)
	_root.add_child(_chat_button)
	_chat_badge = Label.new()
	_chat_badge.visible = false
	_chat_badge.modulate = Color("ff7668")
	_root.add_child(_chat_badge)
	_emote_button = _rail_button("EMOTE", func(): _emote_panel.visible = not _emote_panel.visible)
	_root.add_child(_emote_button)
	_overview_button = _rail_button("HOME", func(): overview_requested.emit())
	_root.add_child(_overview_button)


func _rail_button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(48, 38)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", _button_style(Color("263b43"), 0.92))
	button.pressed.connect(callback)
	return button


func _build_tile_face_panel() -> void:
	_tile_face_panel = PanelContainer.new()
	_tile_face_panel.visible = false
	_tile_face_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff0ce"), 1.0, Color("55a89c"), 3, 18))
	var box := VBoxContainer.new()
	_tile_face_panel.add_child(box)
	var title := Label.new()
	title.text = "놓을 면 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_online_button("+1", func(): _choose_tile_face("oasis"), Color("4cbf91")))
	row.add_child(_online_button("-1", func(): _choose_tile_face("mirage"), Color("df7598")))
	_root.add_child(_tile_face_panel)


func _build_chat_panel() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.visible = false
	_chat_panel.add_theme_stylebox_override("panel", _panel_style(Color("20323a"), 0.97, Color("f2c66d"), 2, 18))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_chat_panel.add_child(box)
	_chat_log = RichTextLabel.new()
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_chat_log)
	var row := HBoxContainer.new()
	box.add_child(row)
	_chat_input = LineEdit.new()
	_chat_input.max_length = 200
	_chat_input.placeholder_text = "메시지..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_chat_input)
	var send := Button.new()
	send.text = ">"
	send.pressed.connect(_send_chat)
	row.add_child(send)
	_chat_input.text_submitted.connect(func(_text: String): _send_chat())
	_root.add_child(_chat_panel)


func _build_emote_panel() -> void:
	_emote_panel = PanelContainer.new()
	_emote_panel.visible = false
	_emote_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff2d3"), 0.97, Color("d99b5c"), 2, 14))
	var grid := GridContainer.new()
	grid.columns = 2
	_emote_panel.add_child(grid)
	for emote_text in ["ㅋㅋㅋ", "ㅠㅠ", "박수!", "제발!", "나이스!", "음..."]:
		var button := Button.new()
		button.text = emote_text
		button.pressed.connect(func(): chat_send_requested.emit(emote_text); _emote_panel.visible = false)
		grid.add_child(button)
	_root.add_child(_emote_panel)


func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8"), 0.98, Color("f2c66d"), 4, 24))
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "경주 종료!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	_result_panel.add_child(box)
	_root.add_child(_result_panel)


func _show_result(state: CamelGameState) -> void:
	_result_panel.visible = state.phase == "GAME_OVER"
	if not _result_panel.visible:
		return
	var standings := state.players.duplicate(true)
	standings.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("money", 0)) > int(b.get("money", 0)))
	var lines: Array[String] = []
	for index in standings.size():
		var player := standings[index] as Dictionary
		lines.append("%d위  %s  코인 %d" % [index + 1, str(player.get("name", "Player")), int(player.get("money", 0))])
	_result_label.text = "\n".join(lines)


func _toggle_chat() -> void:
	_chat_panel.visible = not _chat_panel.visible
	if _chat_panel.visible:
		_unread = 0
		_chat_badge.visible = false
		_chat_input.grab_focus()


func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	if text.is_empty():
		return
	chat_send_requested.emit(text.left(200))
	_chat_input.clear()


func _online_button(title: String, callback: Callable, color: Color) -> Button:
	var button := Button.new()
	button.text = title
	button.add_theme_stylebox_override("normal", _button_style(color, 1.0))
	button.add_theme_stylebox_override("disabled", _button_style(Color("92989c"), 0.6))
	button.pressed.connect(func(): sound_requested.emit("ui"); callback.call())
	return button


func _rules_view(state: CamelGameState) -> CamelGameRules:
	var view := CamelGameRules.new()
	view.load_state(state)
	return view


func _display_scale() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	# Size from a readable mobile design baseline. Comparing the logical canvas
	# to the physical window returned 1.0 in the editor's 1080x1920 test window,
	# leaving 12px labels nearly unreadable.
	if viewport_size.y > viewport_size.x:
		return clampf(viewport_size.x / 480.0, 1.0, 2.25)
	return clampf(viewport_size.y / 720.0, 0.9, 1.4)


func _apply_responsive_layout() -> void:
	if _root == null or _top_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var portrait := viewport_size.y > viewport_size.x
	var ui_scale := _display_scale()
	var pad := 8.0 * ui_scale
	_top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_left = viewport_size.x * (0.13 if portrait else 0.31)
	_top_panel.offset_right = -viewport_size.x * (0.13 if portrait else 0.31)
	_top_panel.offset_top = pad
	_top_panel.offset_bottom = 48 * ui_scale
	_action_panel.anchor_left = 0.04 if portrait else 0.24
	_action_panel.anchor_right = 0.96 if portrait else 0.76
	_action_panel.anchor_top = 1.0
	_action_panel.anchor_bottom = 1.0
	_action_panel.offset_left = 0
	_action_panel.offset_right = 0
	_action_panel.offset_top = (-114 if portrait else -104) * ui_scale
	_action_panel.offset_bottom = -6 * ui_scale
	var hud_width := (140.0 if portrait else 176.0) * ui_scale
	var hud_height := 74.0 * ui_scale
	var lower_y := viewport_size.y - (202 if portrait else 112) * ui_scale
	var positions := [Vector2(pad, 56), Vector2(viewport_size.x - hud_width - pad, 56), Vector2(pad, lower_y), Vector2(viewport_size.x - hud_width - pad, lower_y)]
	var ids := _player_cards.keys()
	for index in ids.size():
		var card := _player_cards[ids[index]] as Control
		card.position = positions[index % 4]
		card.size = Vector2(hud_width, hud_height)
		card.custom_minimum_size = card.size
		for label_node in card.find_children("*", "Label", true, false):
			var label := label_node as Label
			label.add_theme_font_size_override("font_size", int((10 if label.name == "CPU" else 12) * ui_scale))
	order_label.add_theme_font_size_override("font_size", int(14 * ui_scale))
	_timer_label.add_theme_font_size_override("font_size", int(14 * ui_scale))
	waiting_label.add_theme_font_size_override("font_size", int(13 * ui_scale))
	_roll_button.custom_minimum_size = Vector2(58, 58) * ui_scale
	_roll_button.add_theme_font_size_override("font_size", int(12 * ui_scale))
	_cancel_button.custom_minimum_size = Vector2(50, 42) * ui_scale
	_cancel_button.add_theme_font_size_override("font_size", int(11 * ui_scale))
	for slot in _history_slots:
		slot.custom_minimum_size = Vector2(29, 27) * ui_scale
		(slot.get_node("Value") as Label).add_theme_font_size_override("font_size", int(10 * ui_scale))
	if _chat_button != null:
		var rail_y := viewport_size.y * 0.42
		_chat_button.position = Vector2(viewport_size.x - 56 * ui_scale, rail_y)
		_emote_button.position = Vector2(viewport_size.x - 56 * ui_scale, rail_y + 44 * ui_scale)
		_overview_button.position = Vector2(viewport_size.x - 56 * ui_scale, rail_y + 88 * ui_scale)
		_chat_badge.position = Vector2(viewport_size.x - 18 * ui_scale, rail_y - 4 * ui_scale)
		for rail_button in [_chat_button, _emote_button, _overview_button]:
			rail_button.custom_minimum_size = Vector2(48, 38) * ui_scale
			rail_button.add_theme_font_size_override("font_size", int(9 * ui_scale))
	if _chat_panel != null:
		_chat_panel.position = Vector2(pad, viewport_size.y * 0.57)
		_chat_panel.size = Vector2(viewport_size.x - pad * 2.0, viewport_size.y * 0.41)
	if _emote_panel != null:
		_emote_panel.position = Vector2(viewport_size.x - 196, viewport_size.y * 0.42)
		_emote_panel.size = Vector2(136, 154)
	if _tile_face_panel != null:
		_tile_face_panel.position = Vector2(viewport_size.x * 0.5 - 115, viewport_size.y * 0.52)
		_tile_face_panel.size = Vector2(230, 108)
	if _result_panel != null:
		_result_panel.position = Vector2(viewport_size.x * 0.12, viewport_size.y * 0.22)
		_result_panel.size = Vector2(viewport_size.x * 0.76, viewport_size.y * 0.5)
