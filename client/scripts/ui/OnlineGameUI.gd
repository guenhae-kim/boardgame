class_name CamelOnlineGameUI
extends CamelLocalGameUI

signal online_action_requested(action: CamelAction)
signal interaction_mode_changed(target_type: String, valid_ids: Array)
signal chat_send_requested(text: String)
signal sound_requested(cue: String)
signal overview_requested
signal leave_game_requested
signal nickname_change_requested(nickname: String)

const CAMEL_NAMES := {"blue": "파랑", "yellow": "노랑", "green": "초록", "red": "빨강", "purple": "보라"}
const CAMEL_UI_COLORS := {"blue": Color("4f91ff"), "yellow": Color("e8bd3f"), "green": Color("48bd70"), "red": Color("e56861"), "purple": Color("9a72d5")}
const CAMEL_PORTRAITS := {
	"red": preload("res://assets/art/portraits/red-corgi.png"),
	"blue": preload("res://assets/art/portraits/blue-kitten.png"),
	"green": preload("res://assets/art/portraits/green-rabbit.png"),
	"yellow": preload("res://assets/art/portraits/yellow-duck.png"),
	"purple": preload("res://assets/art/portraits/purple-fox.png"),
}
const PLAYER_PORTRAIT_ORDER := ["red", "blue", "green", "yellow"]
const GAME_THEME := preload("res://themes/GameTheme.tres")
const PLAYER_HUD_SCENE := preload("res://scenes/ui/PlayerHUD.tscn")
const CARD_VIEW_SCENE := preload("res://scenes/ui/CardView.tscn")
const DICE_BUTTON_SCENE := preload("res://scenes/ui/DiceButton.tscn")
const HAND_UI_SCENE := preload("res://scenes/ui/HandUI.tscn")
const TV_SPECTATOR_LAYOUT_SCENE := preload("res://scenes/ui/TVSpectatorLayout.tscn")
const CHAT_ICON := preload("res://assets/ui/chat_icon.svg")
const EMOTE_ICON := preload("res://assets/ui/emote_icon.svg")
const HOME_ICON := preload("res://assets/ui/home_icon.svg")

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
var _settings_button: Button
var _settings_panel: PanelContainer
var _chat_badge: Label
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _emote_panel: PanelContainer
var _chat_lines: Array[String] = []
var _unread := 0
var _hud_chat_bubbles: Dictionary = {}
var _timer_label: Label
var _turn_deadline_ms := 0
var _server_clock_offset_ms := 0
var _timer_is_mine := false
var _last_warning_second := -1
var _result_panel: PanelContainer
var _result_title: Label
var _result_reason: Label
var _result_label: Label
var _tv_layout: CamelTVSpectatorLayout
var _tv_spectator_mode := false
var _settings_description: Label


func _build_top_hud() -> void:
	_root.theme = GAME_THEME
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
	_build_settings_panel()
	_build_result_panel()
	_tv_layout = TV_SPECTATOR_LAYOUT_SCENE.instantiate() as CamelTVSpectatorLayout
	_tv_layout.visible = false
	_root.add_child(_tv_layout)


func _build_action_bar() -> void:
	_action_panel = PanelContainer.new()
	_action_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_action_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
	_roll_button = DICE_BUTTON_SCENE.instantiate() as Button
	_roll_button.pressed.connect(func(): sound_requested.emit("ui"); _submit(CamelAction.new(CamelAction.ROLL_DIE)))
	_root.add_child(_roll_button)
	var hand_ui := HAND_UI_SCENE.instantiate() as MarginContainer
	hand_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_line.add_child(hand_ui)
	_hand_row = hand_ui.get_node("HandCards") as HBoxContainer
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
	var standings := state.players.duplicate(true)
	standings.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("money", 0)) > int(b.get("money", 0)))
	for index in state.players.size():
		var player := state.players[index] as Dictionary
		var player_id := str(player.get("id", ""))
		var current := player_id == current_id and state.phase != "GAME_OVER"
		var card := _player_cards[player_id] as PanelContainer
		var money := _money_labels[player_id] as Label
		money.text = "코인 %d" % int(player.get("money", 0))
		var name_label := card.get_node("Margin/Box/Info/Header/Name") as Label
		name_label.text = "%s%s" % ["나 · " if player_id == _local_player_id else "", str(player.get("name", player_id))]
		var rank_index := standings.find_custom(func(candidate: Dictionary): return str(candidate.get("id", "")) == player_id)
		(card.get_node("Margin/Box/Info/Stats/Rank") as Label).text = "%d위" % (rank_index + 1)
		(card.get_node("Margin/Box/Info/Header/CPU") as Label).text = "CPU" if bool(player.get("is_cpu", false)) else ""
		var portrait := card.get_node("Margin/Box/Portrait") as TextureRect
		portrait.texture = CAMEL_PORTRAITS[PLAYER_PORTRAIT_ORDER[index % PLAYER_PORTRAIT_ORDER.size()]]
		(card.get_node("Margin/Box/Portrait/Initial") as Label).visible = false
		(_hud_timer_labels[player_id] as Label).visible = current and _turn_deadline_ms > 0
		card.add_theme_stylebox_override("panel", _panel_style(Color("324950") if current else Color("1d3037"), 0.84, PLAYER_COLORS[index], 3 if current else 1, 18))
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


func set_tv_spectator_mode(enabled: bool) -> void:
	_tv_spectator_mode = enabled
	_can_act = false if enabled else _can_act
	if _tv_layout != null:
		_tv_layout.visible = enabled
	if _action_panel != null:
		_action_panel.visible = not enabled
	if _roll_button != null:
		_roll_button.visible = not enabled
	if _chat_button != null:
		_chat_button.visible = not enabled
	if _emote_button != null:
		_emote_button.visible = not enabled
	if _overview_button != null:
		_overview_button.visible = not enabled
	if _settings_button != null:
		_settings_button.visible = true
	if _settings_description != null:
		_settings_description.text = "TV 관전을 종료하고 홈으로 돌아갑니다." if enabled else "게임에서 나가면 현재 자리는 CPU가 이어서 플레이합니다."
	cancel_selection()
	_apply_responsive_layout()


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


func receive_chat(nickname: String, text: String, player_id: String = "") -> void:
	_chat_lines.append("%s: %s" % [nickname, text])
	if _chat_lines.size() > 50:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)
	if not _chat_panel.visible:
		_unread += 1
		_chat_badge.text = str(_unread)
		_chat_badge.visible = true
	if not player_id.is_empty():
		_show_hud_chat_bubble(player_id, nickname, text)


func _show_hud_chat_bubble(player_id: String, nickname: String, text: String) -> void:
	if not _player_cards.has(player_id):
		return
	if _hud_chat_bubbles.has(player_id):
		var previous := _hud_chat_bubbles[player_id] as Control
		if is_instance_valid(previous):
			previous.queue_free()
	var ui_scale := _display_scale()
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 50
	var desired_size := Vector2(168, 44) * ui_scale
	bubble.custom_minimum_size = desired_size
	bubble.size = desired_size
	bubble.clip_contents = true
	var ids := _player_cards.keys()
	var player_index := maxi(0, ids.find(player_id))
	bubble.add_theme_stylebox_override("panel", _panel_style(Color("fff9e9"), 0.98, PLAYER_COLORS[player_index % PLAYER_COLORS.size()], 3, 14))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(12 * ui_scale))
	margin.add_theme_constant_override("margin_right", int(12 * ui_scale))
	margin.add_theme_constant_override("margin_top", int(7 * ui_scale))
	margin.add_theme_constant_override("margin_bottom", int(7 * ui_scale))
	var label := Label.new()
	label.text = "%s: %s" % [nickname, text.left(32)]
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("423229"))
	label.add_theme_font_size_override("font_size", int(16 * ui_scale))
	margin.add_child(label)
	bubble.add_child(margin)
	_root.add_child(bubble)
	var hud := _player_cards[player_id] as Control
	var viewport_size := get_viewport().get_visible_rect().size
	var bubble_size := desired_size
	var x := clampf(hud.position.x + (hud.size.x - bubble_size.x) * 0.5, 8.0, viewport_size.x - bubble_size.x - 8.0)
	var below := hud.position.y < viewport_size.y * 0.5
	var y := hud.position.y + hud.size.y + 8.0 if below else hud.position.y - bubble_size.y - 8.0
	bubble.position = Vector2(x, y)
	bubble.pivot_offset = bubble_size * 0.5
	bubble.scale = Vector2(0.72, 0.72)
	_hud_chat_bubbles[player_id] = bubble
	var tween := create_tween()
	tween.tween_property(bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.6)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.22)
	await tween.finished
	if _hud_chat_bubbles.get(player_id) == bubble:
		_hud_chat_bubbles.erase(player_id)
	if is_instance_valid(bubble):
		bubble.queue_free()


func cancel_selection() -> void:
	_selected_camel = ""
	_interaction_mode = ""
	_selected_space = -1
	_tile_face_panel.visible = false
	interaction_mode_changed.emit("", [])
	for button in _hand_cards.values():
		(button as Button).scale = Vector2.ONE
		(button as Button).position.y = float((button as Button).get_meta("fan_y", 0.0))
		(button as Button).modulate = Color.WHITE
	if _spectator_card != null:
		_spectator_card.scale = Vector2.ONE
		_spectator_card.position.y = float(_spectator_card.get_meta("fan_y", 0.0))
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
		var card := CARD_VIEW_SCENE.instantiate() as Button
		card.text = str(CAMEL_NAMES.get(camel, camel))
		card.tooltip_text = "%s 예측 카드" % CAMEL_NAMES.get(camel, camel)
		card.icon = CAMEL_PORTRAITS.get(camel, null)
		card.add_theme_constant_override("icon_max_width", int(70 * ui_scale))
		card.custom_minimum_size = Vector2(76, 106) * ui_scale
		card.pivot_offset = Vector2(38, 96) * ui_scale
		card.add_theme_font_size_override("font_size", int(12 * ui_scale))
		var color: Color = CAMEL_UI_COLORS.get(camel, Color.GRAY)
		card.self_modulate = color.lightened(0.12)
		card.pressed.connect(func(): _select_card(camel))
		_hand_row.add_child(card)
		_hand_cards[camel] = card
	_spectator_card = CARD_VIEW_SCENE.instantiate() as Button
	_spectator_card.text = "+1 / -1"
	_spectator_card.tooltip_text = "응원 타일"
	_spectator_card.custom_minimum_size = Vector2(76, 106) * ui_scale
	_spectator_card.pivot_offset = Vector2(38, 96) * ui_scale
	_spectator_card.add_theme_font_size_override("font_size", int(12 * ui_scale))
	_spectator_card.self_modulate = Color("65c6ae")
	_spectator_card.add_theme_constant_override("icon_max_width", int(54 * ui_scale))
	_spectator_card.pressed.connect(_select_spectator)
	_hand_row.add_child(_spectator_card)
	var cards := _hand_row.get_children()
	var center := (cards.size() - 1) * 0.5
	for index in cards.size():
		var hand_card := cards[index] as Button
		var distance := float(index) - center
		hand_card.rotation = deg_to_rad(distance * 3.2)
		var fan_y := absf(distance) * 3.5 * ui_scale
		hand_card.position.y = fan_y
		hand_card.set_meta("fan_y", fan_y)
	_apply_responsive_layout()


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
		var resting_y := float(card.get_meta("fan_y", 0.0))
		create_tween().tween_property(card, "position:y", resting_y - 24.0 * _display_scale() if selected else resting_y, 0.16).set_trans(Tween.TRANS_BACK)
	_set_mode("prediction", ["winner", "loser"])


func _select_spectator() -> void:
	if not _can_act:
		return
	sound_requested.emit("card_select")
	_selected_camel = ""
	create_tween().tween_property(_spectator_card, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK)
	create_tween().tween_property(_spectator_card, "position:y", float(_spectator_card.get_meta("fan_y", 0.0)) - 24.0 * _display_scale(), 0.16).set_trans(Tween.TRANS_BACK)
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
		var card := PLAYER_HUD_SCENE.instantiate() as PanelContainer
		var money := card.get_node("Margin/Box/Info/Stats/Money") as Label
		var timer := card.get_node("Margin/Box/Info/Stats/Timer") as Label
		var tickets := card.get_node("Margin/Box/Info/Tickets") as HBoxContainer
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
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(30, 24) * ui_scale
		badge.add_theme_font_size_override("font_size", int(15 * ui_scale))
		badge.add_theme_color_override("font_color", Color("fff9e8"))
		badge.add_theme_color_override("font_outline_color", Color("423229"))
		badge.add_theme_constant_override("outline_size", int(3 * ui_scale))
		badge.add_theme_stylebox_override("normal", _panel_style(CAMEL_UI_COLORS.get(camel, Color.GRAY), 1.0, Color.WHITE, 1, 5))
		row.add_child(badge)


func _refresh_history(history: Array) -> void:
	for index in _history_slots.size():
		var slot := _history_slots[index]
		var value_label := slot.get_node("Value") as Label
		if index < history.size():
			var result := history[index] as Dictionary
			var camel := str(result.get("camel", result.get("die", "")))
			value_label.text = str(int(result.get("value", 0)))
			value_label.tooltip_text = "%s 주사위 %d" % [str(CAMEL_NAMES.get(camel, camel)), int(result.get("value", 0))]
			value_label.add_theme_color_override("font_color", Color("29252a") if camel == "yellow" else Color("fff9e8"))
			value_label.add_theme_color_override("font_outline_color", Color("fff2c8") if camel == "yellow" else Color("29252a"))
			value_label.add_theme_constant_override("outline_size", 3)
			slot.add_theme_stylebox_override("panel", _panel_style(CAMEL_UI_COLORS.get(camel, Color.GRAY), 1.0, Color.WHITE, 1, 8))
		else:
			value_label.text = "·"
			slot.add_theme_stylebox_override("panel", _panel_style(Color("17272f"), 0.88, Color("61747a"), 1, 8))


func _build_right_rail() -> void:
	_chat_button = _rail_button(CHAT_ICON, "채팅", _toggle_chat)
	_root.add_child(_chat_button)
	_chat_badge = Label.new()
	_chat_badge.visible = false
	_chat_badge.modulate = Color("ff7668")
	_root.add_child(_chat_badge)
	_emote_button = _rail_button(EMOTE_ICON, "빠른 반응", func(): _emote_panel.visible = not _emote_panel.visible)
	_root.add_child(_emote_button)
	_overview_button = _rail_button(HOME_ICON, "보드 전체 보기", func(): overview_requested.emit())
	_root.add_child(_overview_button)
	_settings_button = _rail_button(null, "설정", _toggle_settings)
	_settings_button.text = "⚙"
	_settings_button.add_theme_font_size_override("font_size", 24)
	_root.add_child(_settings_button)


func _rail_button(icon_texture: Texture2D, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	if icon_texture != null:
		button.icon = icon_texture
	button.tooltip_text = hint
	button.expand_icon = true
	button.custom_minimum_size = Vector2(48, 38)
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


func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	_settings_panel.z_index = 80
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8"), 0.99, Color("d99b5c"), 3, 22))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "설정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("493528"))
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_settings_description = Label.new()
	_settings_description.text = "게임에서 나가면 현재 자리는 CPU가 이어서 플레이합니다."
	_settings_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_description.add_theme_color_override("font_color", Color("765b48"))
	box.add_child(_settings_description)
	var nickname_input := LineEdit.new()
	nickname_input.name = "NicknameInput"
	nickname_input.placeholder_text = "새 닉네임"
	nickname_input.max_length = 20
	nickname_input.custom_minimum_size.y = 44
	box.add_child(nickname_input)
	var change_nickname_callback := func():
		var value := nickname_input.text.strip_edges().left(20)
		if not value.is_empty():
			nickname_change_requested.emit(value)
			nickname_input.clear()
	var nickname_button := _online_button("닉네임 변경", change_nickname_callback, Color("d8a340"))
	box.add_child(nickname_button)
	var leave_button := _online_button("게임 나가기", _confirm_leave_game, Color("d9655b"))
	leave_button.custom_minimum_size.y = 48
	box.add_child(leave_button)
	var close_button := _online_button("계속 플레이", _hide_settings, Color("58a796"))
	close_button.custom_minimum_size.y = 44
	box.add_child(close_button)
	margin.add_child(box)
	_settings_panel.add_child(margin)
	_root.add_child(_settings_panel)


func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8"), 0.98, Color("f2c66d"), 4, 24))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_result_title = Label.new()
	_result_title.text = "경주 종료!"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_color_override("font_color", Color("6f4228"))
	_result_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_result_title)
	_result_reason = Label.new()
	_result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_reason.add_theme_color_override("font_color", Color("a06c3f"))
	_result_reason.text = "결승선을 통과한 동물이 나왔어요"
	box.add_child(_result_reason)
	var separator := HSeparator.new()
	box.add_child(separator)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_color_override("font_color", Color("493528"))
	_result_label.add_theme_font_size_override("font_size", 19)
	box.add_child(_result_label)
	var leave_button := _online_button("게임 나가기", _confirm_leave_game, Color("d9655b"))
	leave_button.custom_minimum_size.y = 56
	box.add_child(leave_button)
	margin.add_child(box)
	_result_panel.add_child(margin)
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
		lines.append("%d위  %s    코인 %d" % [index + 1, str(player.get("name", "Player")), int(player.get("money", 0))])
	_result_title.text = "%s 우승!" % str((standings[0] as Dictionary).get("name", "Player")) if standings.size() > 0 else "경주 종료!"
	_result_reason.text = "결승선을 통과한 동물이 나와 최종 정산을 마쳤어요" if state.game_end_reason == "finish_crossed" else "최종 정산을 마쳤어요"
	_result_label.text = "\n".join(lines)


func _toggle_chat() -> void:
	_chat_panel.visible = not _chat_panel.visible
	if _chat_panel.visible:
		_unread = 0
		_chat_badge.visible = false
		_chat_input.grab_focus()


func _toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible:
		_chat_panel.visible = false
		_emote_panel.visible = false


func _confirm_leave_game() -> void:
	_settings_panel.visible = false
	leave_game_requested.emit()


func _hide_settings() -> void:
	_settings_panel.visible = false


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
	# With canvas_items + expand, a 1280x720 browser window is represented by
	# roughly a 3413x1920 logical canvas.  Scaling from the logical height keeps
	# the HUD at its intended *physical* size instead of shrinking it to a tiny
	# desktop overlay.
	return clampf(viewport_size.y / 720.0, 1.0, 3.25)


func _apply_responsive_layout() -> void:
	if _root == null or _top_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var portrait := viewport_size.y > viewport_size.x
	var ui_scale := _display_scale()
	if portrait:
		_apply_portrait_layout(viewport_size, ui_scale)
	else:
		_apply_landscape_layout(viewport_size, ui_scale)
	_apply_overlay_layout(viewport_size, ui_scale, portrait)
	if _tv_spectator_mode:
		_apply_tv_spectator_layout(viewport_size, ui_scale)


func _apply_tv_spectator_layout(viewport_size: Vector2, ui_scale: float) -> void:
	_action_panel.visible = false
	_roll_button.visible = false
	_top_panel.offset_left = viewport_size.x * 0.31
	_top_panel.offset_right = -viewport_size.x * 0.31
	_top_panel.offset_top = 10.0 * ui_scale
	_top_panel.offset_bottom = 66.0 * ui_scale
	var pad := 18.0 * ui_scale
	var hud_size := Vector2(248, 124) * ui_scale
	var positions := [
		Vector2(pad, pad),
		Vector2(viewport_size.x - hud_size.x - pad, pad),
		Vector2(pad, viewport_size.y - hud_size.y - pad),
		Vector2(viewport_size.x - hud_size.x - pad, viewport_size.y - hud_size.y - pad),
	]
	_layout_player_cards(positions, hud_size, Vector2(84, 84) * ui_scale, ui_scale, 19)
	_style_common_hud(ui_scale, 22, 19, 0, Vector2(44, 38))
	_chat_button.visible = false
	_emote_button.visible = false
	_overview_button.visible = false
	_settings_button.position = Vector2(viewport_size.x - 66 * ui_scale, viewport_size.y * 0.56)


func _apply_portrait_layout(viewport_size: Vector2, ui_scale: float) -> void:
	var pad := 8.0 * ui_scale
	_top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_left = viewport_size.x * 0.13
	_top_panel.offset_right = -viewport_size.x * 0.13
	_top_panel.offset_top = pad
	_top_panel.offset_bottom = 48 * ui_scale
	_action_panel.anchor_left = 0.04
	_action_panel.anchor_right = 0.96
	_action_panel.anchor_top = 1.0
	_action_panel.anchor_bottom = 1.0
	_action_panel.offset_left = 0
	_action_panel.offset_right = 0
	_action_panel.offset_top = -114 * ui_scale
	_action_panel.offset_bottom = -6 * ui_scale
	var hud_width := 154.0 * ui_scale
	var hud_height := 86.0 * ui_scale
	var lower_y := viewport_size.y - 230 * ui_scale
	var top_y := 60.0 * ui_scale
	var positions := [Vector2(pad, top_y), Vector2(viewport_size.x - hud_width - pad, top_y), Vector2(pad, lower_y), Vector2(viewport_size.x - hud_width - pad, lower_y)]
	_layout_player_cards(positions, Vector2(hud_width, hud_height), Vector2(56, 56) * ui_scale, ui_scale, 16)
	_style_common_hud(ui_scale, 16, 14, 13, Vector2(34, 32))
	_resize_hand_cards(ui_scale, Vector2(76, 106))
	_roll_button.custom_minimum_size = Vector2(84, 84) * ui_scale
	_roll_button.size = _roll_button.custom_minimum_size
	_roll_button.position = Vector2(viewport_size.x - 98 * ui_scale, viewport_size.y - 342 * ui_scale)


func _apply_landscape_layout(viewport_size: Vector2, ui_scale: float) -> void:
	var pad := 12.0 * ui_scale
	_top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_left = viewport_size.x * 0.285
	_top_panel.offset_right = -viewport_size.x * 0.285
	_top_panel.offset_top = 8 * ui_scale
	_top_panel.offset_bottom = 62 * ui_scale
	_action_panel.anchor_left = 0.19
	_action_panel.anchor_right = 0.81
	_action_panel.anchor_top = 1.0
	_action_panel.anchor_bottom = 1.0
	_action_panel.offset_left = 0
	_action_panel.offset_right = 0
	_action_panel.offset_top = -174 * ui_scale
	_action_panel.offset_bottom = -2 * ui_scale
	var hud_size := Vector2(232, 116) * ui_scale
	var top_y := 12.0 * ui_scale
	var lower_y := viewport_size.y - hud_size.y - 12.0 * ui_scale
	var positions := [
		Vector2(pad, top_y),
		Vector2(viewport_size.x - hud_size.x - pad, top_y),
		Vector2(pad, lower_y),
		Vector2(viewport_size.x - hud_size.x - pad, lower_y),
	]
	_layout_player_cards(positions, hud_size, Vector2(78, 78) * ui_scale, ui_scale, 18)
	_style_common_hud(ui_scale, 20, 18, 17, Vector2(42, 36))
	_resize_hand_cards(ui_scale, Vector2(102, 142))
	_roll_button.custom_minimum_size = Vector2(98, 98) * ui_scale
	_roll_button.size = _roll_button.custom_minimum_size
	_roll_button.position = Vector2(viewport_size.x - 116 * ui_scale, lower_y - 112 * ui_scale)


func _layout_player_cards(positions: Array, card_size: Vector2, portrait_size: Vector2, ui_scale: float, label_size: int) -> void:
	var ids := _player_cards.keys()
	for index in ids.size():
		var card := _player_cards[ids[index]] as Control
		card.position = positions[index % 4]
		card.size = card_size
		card.custom_minimum_size = card.size
		var portrait_node := card.get_node_or_null("Margin/Box/Portrait") as TextureRect
		if portrait_node != null:
			portrait_node.custom_minimum_size = portrait_size
		for label_node in card.find_children("*", "Label", true, false):
			var label := label_node as Label
			label.add_theme_font_size_override("font_size", int((11 if label.name == "CPU" else label_size) * ui_scale))


func _style_common_hud(ui_scale: float, round_size: int, timer_size: int, waiting_size: int, history_size: Vector2) -> void:
	order_label.add_theme_font_size_override("font_size", int(round_size * ui_scale))
	_timer_label.add_theme_font_size_override("font_size", int(timer_size * ui_scale))
	waiting_label.add_theme_font_size_override("font_size", int(waiting_size * ui_scale))
	_cancel_button.custom_minimum_size = Vector2(50, 42) * ui_scale
	_cancel_button.add_theme_font_size_override("font_size", int(13 * ui_scale))
	for slot in _history_slots:
		slot.custom_minimum_size = history_size * ui_scale
		(slot.get_node("Value") as Label).add_theme_font_size_override("font_size", int(round_size * ui_scale))


func _resize_hand_cards(ui_scale: float, base_size: Vector2) -> void:
	for card_value in _hand_row.get_children():
		var card := card_value as Button
		if card == null:
			continue
		card.custom_minimum_size = base_size * ui_scale
		card.pivot_offset = Vector2(base_size.x * 0.5, base_size.y * 0.9) * ui_scale
		card.add_theme_constant_override("icon_max_width", int(base_size.x * 0.72 * ui_scale))
		card.add_theme_font_size_override("font_size", int(15 * ui_scale))


func _apply_overlay_layout(viewport_size: Vector2, ui_scale: float, portrait: bool) -> void:
	var pad := 8.0 * ui_scale
	if _chat_button != null:
		var rail_y := viewport_size.y * (0.42 if portrait else 0.31)
		var rail_step := (44 if portrait else 56) * ui_scale
		var rail_x := viewport_size.x - (56 if portrait else 66) * ui_scale
		_chat_button.position = Vector2(rail_x, rail_y)
		_emote_button.position = Vector2(rail_x, rail_y + rail_step)
		_overview_button.position = Vector2(rail_x, rail_y + rail_step * 2.0)
		_settings_button.position = Vector2(rail_x, rail_y + rail_step * 3.0)
		_chat_badge.position = Vector2(viewport_size.x - 18 * ui_scale, rail_y - 4 * ui_scale)
		for rail_button in [_chat_button, _emote_button, _overview_button, _settings_button]:
			rail_button.custom_minimum_size = Vector2(46 if portrait else 54, 46 if portrait else 54) * ui_scale
	if _chat_panel != null:
		_chat_panel.position = Vector2(pad, viewport_size.y * 0.57)
		_chat_panel.size = Vector2(viewport_size.x - pad * 2.0, viewport_size.y * 0.41)
	if _emote_panel != null:
		_emote_panel.position = Vector2(viewport_size.x - 196 * ui_scale, viewport_size.y * (0.42 if portrait else 0.31))
		_emote_panel.size = Vector2(136, 154) * ui_scale
	if _tile_face_panel != null:
		_tile_face_panel.position = Vector2(viewport_size.x * 0.5 - 115, viewport_size.y * 0.52)
		_tile_face_panel.size = Vector2(230, 108)
	if _result_panel != null:
		var result_size := Vector2(viewport_size.x * (0.84 if portrait else 0.46), viewport_size.y * (0.38 if portrait else 0.52))
		_result_panel.position = (viewport_size - result_size) * 0.5
		_result_panel.size = result_size
		_result_title.add_theme_font_size_override("font_size", int(28 * ui_scale))
		_result_reason.add_theme_font_size_override("font_size", int(13 * ui_scale))
		_result_label.add_theme_font_size_override("font_size", int(19 * ui_scale))
	if _settings_panel != null:
		var settings_size := Vector2(minf(350.0 * ui_scale, viewport_size.x - pad * 2.0), 330.0 * ui_scale)
		_settings_panel.position = (viewport_size - settings_size) * 0.5
		_settings_panel.size = settings_size
