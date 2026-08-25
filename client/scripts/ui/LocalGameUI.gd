class_name CamelLocalGameUI
extends CanvasLayer

signal new_game_requested(names: Array)
signal action_requested(action: CamelAction)
signal roll_requested(forced_die: String, forced_value: int)
signal debug_stack_requested
signal debug_next_turn_requested

const PLAYER_COLORS := [Color("ff806e"), Color("62b9ff"), Color("70cf85"), Color("f2c85b"), Color("bd8cff"), Color("ff9dcc"), Color("67d7d2"), Color("f29e62")]

var names_edit: LineEdit
var turn_label: Label
var phase_label: Label
var waiting_label: Label
var description_label: Label
var players_label: Label
var order_label: Label
var error_label: Label
var log_view: RichTextLabel
var camel_option: OptionButton
var bet_option: OptionButton
var space_spin: SpinBox
var side_option: OptionButton
var partner_option: OptionButton
var debug_die_option: OptionButton
var debug_value: SpinBox
var _action_controls: Array[Control] = []
var _root: Control
var _top_panel: PanelContainer
var _player_row: HFlowContainer
var _action_panel: PanelContainer
var _action_buttons_row: GridContainer
var _selector_row: GridContainer
var _debug_panel: PanelContainer
var _partner_button: Button
var _player_cards: Dictionary = {}
var _money_labels: Dictionary = {}
var _round_banner: PanelContainer
var _round_scoring_ui: CamelRoundScoringUI
var _presented_player_id := ""


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func set_flow_state(phase_name: String, player_name: String, description: String, input_enabled: bool) -> void:
	var friendly_phases := {
		"SETUP": "게임 준비", "TURN_START": "턴 시작", "WAITING_FOR_ACTION": "행동 선택",
		"ROLLING_DICE": "주사위 굴리는 중", "RESOLVING_ACTION": "결과 확인",
		"PLAYING_MOVEMENT_ANIMATION": "동물 이동 중", "PLAYING_EFFECT_ANIMATION": "보드 효과",
		"TURN_END": "턴 마무리", "ROUND_END": "구간 정산", "GAME_END": "게임 종료",
	}
	phase_label.text = str(friendly_phases.get(phase_name, phase_name))
	turn_label.text = "%s의 차례" % player_name if not player_name.is_empty() else "게임 준비"
	waiting_label.text = "행동을 골라 주세요" if input_enabled else "%s 행동 중 · 잠시 기다려 주세요" % player_name
	description_label.text = description
	set_action_enabled(input_enabled)


func set_action_enabled(enabled: bool) -> void:
	for control in _action_controls:
		if control is BaseButton:
			(control as BaseButton).disabled = not enabled
		elif control is SpinBox:
			(control as SpinBox).editable = enabled
		elif control is LineEdit:
			(control as LineEdit).editable = enabled


func set_presented_player(player_id: String) -> void:
	_presented_player_id = player_id


func refresh_state(rules: CamelGameRules) -> void:
	var state := rules.state
	order_label.text = "구간 %d   ·   주사위 행동 %d/5   ·   남은 %d회" % [state.leg_number, state.dice_history.size(), maxi(0, 5 - state.dice_history.size())]
	_rebuild_player_cards_if_needed(state.players)
	for index in state.players.size():
		var player := state.players[index] as Dictionary
		var player_id := str(player["id"])
		var shown_player_id := _presented_player_id if not _presented_player_id.is_empty() else str(state.current_player()["id"])
		var current := player_id == shown_player_id and state.phase != "GAME_OVER"
		var card := _player_cards[player_id] as PanelContainer
		var money_label := _money_labels[player_id] as Label
		money_label.text = "코인 %d" % int(player["money"])
		card.add_theme_stylebox_override("panel", _panel_style(Color("fff4d8") if current else Color("2d3540"), 0.96, PLAYER_COLORS[index], 4 if current else 0, 18))
		card.modulate = Color.WHITE if current else Color(0.86, 0.88, 0.9, 0.9)
		if current and not card.has_meta("bouncing"):
			card.set_meta("bouncing", true)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.035, 1.035), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "scale", Vector2.ONE, 0.18)
			tween.finished.connect(func(): card.remove_meta("bouncing"))
	partner_option.clear()
	for player in state.players:
		if str(player["id"]) != str(state.current_player()["id"]):
			partner_option.add_item(str(player["name"]))
			partner_option.set_item_metadata(partner_option.item_count - 1, player["id"])
	_partner_button.visible = state.players.size() >= 6
	partner_option.visible = state.players.size() >= 6


func play_money_change(player_id: String, amount: int) -> void:
	if amount == 0 or not _money_labels.has(player_id):
		return
	var money_label := _money_labels[player_id] as Label
	var final_value := int(money_label.text.replace("코인", "").strip_edges())
	money_label.text = "코인 %d" % (final_value - amount)
	var floating := Label.new()
	floating.text = "%+d 코인" % amount
	floating.add_theme_font_size_override("font_size", 22)
	floating.modulate = Color("65d887") if amount > 0 else Color("ff7575")
	floating.position = money_label.global_position - Vector2(0, 4)
	_root.add_child(floating)
	var tween := create_tween()
	tween.tween_property(floating, "position:y", floating.position.y - 42, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(floating, "modulate:a", 0.0, 0.55)
	await tween.finished
	floating.queue_free()
	money_label.text = "코인 %d" % final_value


func show_round_complete(leg_number: int) -> void:
	_round_banner.visible = true
	(_round_banner.get_node("Label") as Label).text = "구간 %d 완료!\n베팅과 주사위 보상을 정산합니다" % leg_number
	_round_banner.scale = Vector2(0.6, 0.6)
	_round_banner.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_round_banner, "scale", Vector2.ONE, 0.3)
	tween.parallel().tween_property(_round_banner, "modulate:a", 1.0, 0.22)
	tween.tween_interval(0.75)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_round_banner, "modulate:a", 0.0, 0.25)
	await tween.finished
	_round_banner.visible = false


func show_round_scoring(leg_number: int, breakdowns: Array) -> void:
	if _round_scoring_ui == null:
		await show_round_complete(leg_number)
		return
	await _round_scoring_ui.play_round_scoring(leg_number, breakdowns)


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = not message.is_empty()


func clear_log() -> void:
	log_view.clear()


func add_log(text_value: String, color: String = "b8c0cc") -> void:
	log_view.append_text("[color=#%s]%s[/color]\n" % [color, text_value])
	log_view.scroll_to_line(maxi(0, log_view.get_line_count() - 1))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top_hud()
	_build_action_bar()
	_build_debug_panel()
	_build_round_banner()
	_build_round_scoring_ui()


func _build_round_scoring_ui() -> void:
	var scene := load("res://scenes/ui/RoundScoringUI.tscn") as PackedScene
	_round_scoring_ui = scene.instantiate() as CamelRoundScoringUI
	_root.add_child(_round_scoring_ui)


func _build_top_hud() -> void:
	_top_panel = PanelContainer.new()
	_top_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_top_panel.add_theme_stylebox_override("panel", _panel_style(Color("23323b"), 0.93, Color("f2c66d"), 2, 22))
	_root.add_child(_top_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_top_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	var turn_box := VBoxContainer.new()
	turn_box.custom_minimum_size.x = 210
	row.add_child(turn_box)
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 26)
	turn_label.modulate = Color("ffd778")
	turn_box.add_child(turn_label)
	order_label = Label.new()
	order_label.add_theme_font_size_override("font_size", 15)
	turn_box.add_child(order_label)
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.modulate = Color("8dd7df")
	turn_box.add_child(phase_label)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(header_spacer)
	var dev := Button.new()
	dev.text = "DEV"
	dev.flat = true
	dev.pressed.connect(func(): _debug_panel.visible = not _debug_panel.visible)
	row.add_child(dev)
	_player_row = HFlowContainer.new()
	_player_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_row.add_theme_constant_override("h_separation", 8)
	_player_row.add_theme_constant_override("v_separation", 6)
	content.add_child(_player_row)
	players_label = Label.new()
	players_label.visible = false


func _build_action_bar() -> void:
	_action_panel = PanelContainer.new()
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_action_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff5dd"), 0.97, Color("cf8d57"), 3, 24))
	_root.add_child(_action_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	_action_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var status_row := HBoxContainer.new()
	content.add_child(status_row)
	waiting_label = Label.new()
	waiting_label.add_theme_font_size_override("font_size", 18)
	waiting_label.modulate = Color("4b3528")
	status_row.add_child(waiting_label)
	description_label = Label.new()
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	description_label.modulate = Color("765a48")
	status_row.add_child(description_label)
	error_label = Label.new()
	error_label.modulate = Color("d64d4d")
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.visible = false
	content.add_child(error_label)
	_selector_row = GridContainer.new()
	_selector_row.columns = 5
	_selector_row.add_theme_constant_override("h_separation", 8)
	_selector_row.add_theme_constant_override("v_separation", 6)
	content.add_child(_selector_row)
	camel_option = _option(CamelGameState.RACE_CAMELS)
	_selector_row.add_child(_labeled_control("동물 색", camel_option))
	bet_option = _option(["1등", "꼴등"])
	_selector_row.add_child(_labeled_control("예측", bet_option))
	space_spin = SpinBox.new()
	space_spin.min_value = 2
	space_spin.max_value = 16
	space_spin.value = 8
	_selector_row.add_child(_labeled_control("관중 칸", space_spin))
	side_option = _option(["오아시스 +1", "신기루 -1"])
	_selector_row.add_child(_labeled_control("타일 면", side_option))
	partner_option = OptionButton.new()
	_selector_row.add_child(_labeled_control("파트너", partner_option))
	for control in [camel_option, bet_option, space_spin, side_option, partner_option]:
		_track(control)
	_action_buttons_row = GridContainer.new()
	_action_buttons_row.columns = 6
	_action_buttons_row.add_theme_constant_override("h_separation", 8)
	_action_buttons_row.add_theme_constant_override("v_separation", 8)
	content.add_child(_action_buttons_row)
	_action_buttons_row.add_child(_action_button("● 주사위", _request_roll, Color("e7a83e")))
	_action_buttons_row.add_child(_action_button("◆ 구간 베팅", _request_leg_bet, Color("e06b62")))
	_action_buttons_row.add_child(_action_button("★ 1등 예측", func(): _request_final_bet("winner"), Color("e5b94f")))
	_action_buttons_row.add_child(_action_button("▼ 꼴등 예측", func(): _request_final_bet("loser"), Color("7d6dae")))
	_action_buttons_row.add_child(_action_button("+ 관중 타일", _request_tile, Color("55a89c")))
	_partner_button = _action_button("↔ 파트너", _request_partner, Color("6e9ac8"))
	_action_buttons_row.add_child(_partner_button)


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_debug_panel.position = Vector2(-360, -250)
	_debug_panel.size = Vector2(340, 500)
	_debug_panel.add_theme_stylebox_override("panel", _panel_style(Color("172027"), 0.97, Color("6fb2bf"), 2, 16))
	_root.add_child(_debug_panel)
	var box := VBoxContainer.new()
	_debug_panel.add_child(box)
	names_edit = LineEdit.new()
	names_edit.text = "Player 1, Player 2, Player 3"
	box.add_child(names_edit)
	box.add_child(_simple_button("새 게임 / Reset", _request_new_game))
	debug_die_option = _option(CamelGameState.RACE_CAMELS + ["gray"])
	box.add_child(debug_die_option)
	debug_value = SpinBox.new()
	debug_value.min_value = 1
	debug_value.max_value = 3
	debug_value.value = 3
	box.add_child(debug_value)
	box.add_child(_simple_button("강제 3D 주사위", _request_debug_roll))
	box.add_child(_simple_button("3단 스택 상황", func(): debug_stack_requested.emit()))
	box.add_child(_simple_button("다음 플레이어", func(): debug_next_turn_requested.emit()))
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_view)


func _build_round_banner() -> void:
	_round_banner = PanelContainer.new()
	_round_banner.name = "RoundBanner"
	_round_banner.visible = false
	_round_banner.set_anchors_preset(Control.PRESET_CENTER)
	_round_banner.position = Vector2(-230, -75)
	_round_banner.size = Vector2(460, 150)
	_round_banner.pivot_offset = _round_banner.size * 0.5
	_round_banner.add_theme_stylebox_override("panel", _panel_style(Color("fff0b3"), 0.98, Color("df9848"), 5, 28))
	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.modulate = Color("5e3d27")
	_round_banner.add_child(label)
	_root.add_child(_round_banner)


func _rebuild_player_cards_if_needed(players: Array) -> void:
	if _player_cards.size() == players.size():
		return
	for child in _player_row.get_children():
		child.queue_free()
	_player_cards.clear()
	_money_labels.clear()
	for index in players.size():
		var player := players[index] as Dictionary
		var player_id := str(player["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(125, 64)
		card.pivot_offset = Vector2(62, 32)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(margin)
		var box := VBoxContainer.new()
		margin.add_child(box)
		var name := Label.new()
		name.text = "● " + str(player["name"])
		name.modulate = PLAYER_COLORS[index]
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(name)
		var money := Label.new()
		money.add_theme_font_size_override("font_size", 19)
		money.modulate = Color("ffd36b")
		box.add_child(money)
		_player_row.add_child(card)
		_player_cards[player_id] = card
		_money_labels[player_id] = money


func _apply_responsive_layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var portrait := size.y > size.x
	_top_panel.anchor_left = 0.03
	_top_panel.anchor_right = 0.97
	_top_panel.anchor_top = 0.02
	_top_panel.anchor_bottom = 0.02
	_top_panel.offset_left = 0
	_top_panel.offset_right = 0
	_top_panel.offset_top = 0
	_top_panel.offset_bottom = 300 if portrait else 148
	_action_panel.anchor_left = 0.03 if portrait else 0.12
	_action_panel.anchor_right = 0.97 if portrait else 0.88
	_action_panel.anchor_top = 1.0
	_action_panel.anchor_bottom = 1.0
	_action_panel.offset_left = 0
	_action_panel.offset_right = 0
	_action_panel.offset_top = -820 if portrait else -205
	_action_panel.offset_bottom = -14
	_action_buttons_row.columns = 2 if portrait else 6
	_selector_row.columns = 2 if portrait else 5
	_selector_row.visible = true
	turn_label.add_theme_font_size_override("font_size", 52 if portrait else 26)
	order_label.add_theme_font_size_override("font_size", 31 if portrait else 15)
	phase_label.add_theme_font_size_override("font_size", 27 if portrait else 12)
	waiting_label.add_theme_font_size_override("font_size", 42 if portrait else 18)
	description_label.add_theme_font_size_override("font_size", 30 if portrait else 16)
	for child in _action_buttons_row.get_children():
		var button := child as Button
		if button != null:
			button.custom_minimum_size.y = 118 if portrait else 52
			button.add_theme_font_size_override("font_size", 40 if portrait else 18)
	for child in _selector_row.get_children():
		var field := child as Control
		if field == null:
			continue
		field.custom_minimum_size.y = 112 if portrait else 0
		var field_labels := field.find_children("*", "Label", true, false)
		for field_label in field_labels:
			(field_label as Label).add_theme_font_size_override("font_size", 27 if portrait else 14)
	for selector in [camel_option, bet_option, space_spin, side_option, partner_option]:
		(selector as Control).custom_minimum_size.y = 72 if portrait else 0
		(selector as Control).add_theme_font_size_override("font_size", 29 if portrait else 16)
	for card in _player_cards.values():
		var player_card := card as PanelContainer
		player_card.custom_minimum_size = Vector2(285, 130) if portrait else Vector2(125, 64)
		var card_labels := player_card.find_children("*", "Label", true, false)
		for index in card_labels.size():
			(card_labels[index] as Label).add_theme_font_size_override("font_size", (32 if index == 0 else 38) if portrait else (16 if index == 0 else 19))


func _request_new_game() -> void:
	var names: Array = []
	for raw_name in names_edit.text.split(","):
		var clean := str(raw_name).strip_edges()
		if not clean.is_empty() and names.size() < 8:
			names.append(clean)
	new_game_requested.emit(names)


func _request_roll() -> void:
	roll_requested.emit("", 0)


func _request_debug_roll() -> void:
	var die := str((CamelGameState.RACE_CAMELS + ["gray"])[debug_die_option.selected])
	roll_requested.emit(die, int(debug_value.value))


func _request_leg_bet() -> void:
	action_requested.emit(CamelAction.new(CamelAction.TAKE_LEG_BET, {"camel": CamelGameState.RACE_CAMELS[camel_option.selected]}))


func _request_final_bet(bet_type: String = "") -> void:
	if bet_type.is_empty():
		bet_type = "winner" if bet_option.selected == 0 else "loser"
	action_requested.emit(CamelAction.new(CamelAction.FINAL_BET, {"camel": CamelGameState.RACE_CAMELS[camel_option.selected], "bet": bet_type}))


func _request_tile() -> void:
	action_requested.emit(CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": int(space_spin.value), "side": "oasis" if side_option.selected == 0 else "mirage"}))


func _request_partner() -> void:
	if partner_option.item_count > 0:
		action_requested.emit(CamelAction.new(CamelAction.PARTNER, {"target_player_id": partner_option.get_item_metadata(partner_option.selected)}))


func _action_button(text_value: String, callback: Callable, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(132, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(color, 1.0))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.1), 1.0))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.12), 1.0))
	button.add_theme_stylebox_override("disabled", _button_style(Color("92989c"), 0.65))
	button.pressed.connect(callback)
	_track(button)
	return button


func _simple_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	return button


func _track(control: Control) -> void:
	if control not in _action_controls:
		_action_controls.append(control)


func _option(items: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(110, 38)
	option.add_theme_color_override("font_color", Color("5b4638"))
	option.add_theme_color_override("font_hover_color", Color("3e3028"))
	option.add_theme_stylebox_override("normal", _button_style(Color("eadfc5"), 1.0))
	option.add_theme_stylebox_override("hover", _button_style(Color("f5e9cc"), 1.0))
	for item in items:
		option.add_item(str(item))
	return option


func _labeled_control(title: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	label.modulate = Color("775b49")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	box.add_child(control)
	return box


func _panel_style(color: Color, alpha: float, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, alpha)
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 8
	return style


func _button_style(color: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, alpha)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 5
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style
