class_name CamelRoundScoringUI
extends Control

const CAMEL_NAMES := {"red": "빨강", "blue": "파랑", "green": "초록", "yellow": "노랑", "purple": "보라"}
const CAMEL_COLORS := {
	"red": Color("e96d64"), "blue": Color("5798ed"), "green": Color("50bd73"),
	"yellow": Color("e8bd43"), "purple": Color("9b75d5"),
}
const PORTRAITS := {
	"red": preload("res://assets/art/portraits/red-corgi.png"),
	"blue": preload("res://assets/art/portraits/blue-kitten.png"),
	"green": preload("res://assets/art/portraits/green-rabbit.png"),
	"yellow": preload("res://assets/art/portraits/yellow-duck.png"),
	"purple": preload("res://assets/art/portraits/purple-fox.png"),
}
const PLAYER_PORTRAITS := ["red", "blue", "green", "yellow"]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _round_title: Label = $Center/Panel/Margin/Content/RoundTitle
@onready var _portrait: TextureRect = $Center/Panel/Margin/Content/PlayerRow/Portrait
@onready var _player_name: Label = $Center/Panel/Margin/Content/PlayerRow/PlayerText/PlayerName
@onready var _player_badge: Label = $Center/Panel/Margin/Content/PlayerRow/PlayerText/PlayerBadge
@onready var _item_title: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/ItemTitle
@onready var _breakdown_rows: VBoxContainer = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/BreakdownRows
@onready var _card: PanelContainer = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card
@onready var _card_portrait: TextureRect = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card/CardBox/CardPortrait
@onready var _card_caption: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card/CardBox/CardCaption
@onready var _dice_icon: TextureRect = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/DiceIcon
@onready var _item_delta: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/ItemDelta
@onready var _current_total: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/CurrentTotal
@onready var _coin_total: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/CoinTotal
@onready var _table_total: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/TableTotal
@onready var _summary: RichTextLabel = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Summary
@onready var _progress: Label = $Center/Panel/Margin/Content/Progress
@onready var _skip_button: Button = $Center/Panel/Margin/Content/Skip

var _skip := false
var _active_tween: Tween
var _local_theme: Theme
var _ui_scale := 1.0


func _ready() -> void:
	_local_theme = theme.duplicate() as Theme
	theme = _local_theme
	_skip_button.pressed.connect(_request_skip)
	get_viewport().size_changed.connect(_apply_responsive_size)
	_apply_responsive_size()


func play_round_scoring(leg_number: int, breakdowns: Array) -> void:
	_skip = false
	_skip_button.text = "빠르게 보기"
	visible = true
	_round_title.text = "ROUND %d 정산" % leg_number
	modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	await _active_tween.finished

	for player_index in breakdowns.size():
		var breakdown := breakdowns[player_index] as Dictionary
		await _play_player(player_index, breakdowns.size(), breakdown)
	await _show_round_summary(breakdowns)
	await _wait_or_skip(0.8)

	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, 0.18 if not _skip else 0.04)
	await _active_tween.finished
	visible = false


func _play_player(player_index: int, player_count: int, data: Dictionary) -> void:
	_progress.text = "%d / %d" % [player_index + 1, player_count]
	_player_name.text = str(data.get("player_name", data.get("player_id", "Player")))
	_player_badge.text = "PLAYER %d  ·  이번 라운드" % (player_index + 1)
	_portrait.texture = PORTRAITS[PLAYER_PORTRAITS[player_index % PLAYER_PORTRAITS.size()]]
	await _show_player_table(data)


func _show_player_table(data: Dictionary) -> void:
	_summary.visible = false
	_card.visible = false
	_dice_icon.visible = false
	_item_delta.visible = false
	_current_total.visible = false
	_coin_total.visible = false
	_item_title.visible = true
	_item_title.text = "이번 라운드 정산 내역"
	_breakdown_rows.visible = true
	_table_total.visible = true
	_clear_breakdown_rows()

	var groups := _group_card_results(data.get("betting_cards", []) as Array)
	_add_result_group_row("first", "1등 적중 카드", groups["first"] as Array, int(groups["first_total"]), Color("e3ad35"))
	_add_result_group_row("second", "2등 적중 카드", groups["second"] as Array, int(groups["second_total"]), Color("68a5d9"))
	_add_result_group_row("other", "나머지 카드", groups["other"] as Array, int(groups["other_total"]), Color("c76b6b"))

	_add_breakdown_row(
		load("res://assets/ui/dice_icon.svg") as Texture2D,
		"주사위 진행 횟수",
		"+1 × %d회" % int(data.get("dice_roll_count", 0)),
		int(data.get("dice_reward", 0)),
		false,
		Color("d8a33d"),
	)

	_table_total.text = "카드 %s   +   주사위 %s\n이번 라운드 총합  %s 코인\n보유 코인  %d → %d" % [
		_signed(int(data.get("card_delta", 0))),
		_signed(int(data.get("dice_reward", 0))),
		_signed(int(data.get("round_delta", 0))),
		int(data.get("money_before", 0)),
		int(data.get("money_after", 0)),
	]
	_table_total.modulate.a = 0.0
	await get_tree().process_frame
	for row_value in _breakdown_rows.get_children():
		var row := row_value as Control
		row.modulate.a = 0.0
		_active_tween = create_tween()
		_active_tween.tween_property(row, "modulate:a", 1.0, 0.16 if not _skip else 0.02)
		await _active_tween.finished
		await _wait_or_skip(0.12)
	_active_tween = create_tween()
	_active_tween.tween_property(_table_total, "modulate:a", 1.0, 0.24 if not _skip else 0.03)
	await _active_tween.finished
	# Keep one player's complete calculation visible long enough to read. The
	# fast-forward button only shortens presentation; it never changes data.
	await _wait_or_skip(2.25)


func _group_card_results(cards: Array) -> Dictionary:
	var result := {
		"first": [], "second": [], "other": [],
		"first_total": 0, "second_total": 0, "other_total": 0,
	}
	for card_value in cards:
		var card := card_value as Dictionary
		var category := str(card.get("result_category", ""))
		if category.is_empty():
			# Compatibility with a game started on an older server build.
			var applied_value := int(card.get("value", 0))
			category = "first" if applied_value > 1 else ("second" if applied_value == 1 else "other")
		if not result.has(category):
			category = "other"
		(result[category] as Array).append(card)
		result["%s_total" % category] = int(result["%s_total" % category]) + int(card.get("value", 0))
	return result


func _add_result_group_row(category: String, title: String, cards: Array, total: int, accent: Color) -> void:
	var badge := "1위" if category == "first" else ("2위" if category == "second" else "실패")
	if cards.is_empty():
		_add_breakdown_row(null, title, "0장", 0, true, accent, badge)
		return
	var detail := ""
	match category:
		"first":
			var values: Array[String] = []
			for card_value in cards:
				values.append(_signed(int((card_value as Dictionary).get("value", 0))))
			detail = "%s · %d장" % ["  ".join(values), cards.size()]
		"second":
			detail = "+1 × %d장" % cards.size()
		_:
			detail = "-1 × %d장" % cards.size()
	_add_breakdown_row(null, title, detail, total, false, accent, badge)


func _add_breakdown_row(icon: Texture2D, title: String, detail: String, value: int, muted: bool, accent: Color = Color("d0a45b"), badge_text: String = "") -> void:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 54.0 * _ui_scale
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, 0.11) if not muted else Color(0.5, 0.45, 0.38, 0.07)
	style.border_color = Color(accent, 0.58) if not muted else Color(0.5, 0.45, 0.38, 0.24)
	style.set_border_width_all(maxi(1, roundi(1.5 * _ui_scale)))
	style.set_corner_radius_all(roundi(12.0 * _ui_scale))
	row.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", roundi(9.0 * _ui_scale))
	margin.add_theme_constant_override("margin_right", roundi(11.0 * _ui_scale))
	margin.add_theme_constant_override("margin_top", roundi(5.0 * _ui_scale))
	margin.add_theme_constant_override("margin_bottom", roundi(5.0 * _ui_scale))
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(7.0 * _ui_scale))
	margin.add_child(line)
	if not badge_text.is_empty():
		var badge := Label.new()
		badge.custom_minimum_size = Vector2(42, 34) * _ui_scale
		badge.text = badge_text
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color("fff9eb"))
		badge.add_theme_font_size_override("font_size", _scaled_font(12 if badge_text.length() > 2 else 14))
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = accent.darkened(0.12) if not muted else Color("9d9489")
		badge_style.set_corner_radius_all(roundi(9.0 * _ui_scale))
		badge.add_theme_stylebox_override("normal", badge_style)
		line.add_child(badge)
	else:
		var icon_view := TextureRect.new()
		icon_view.custom_minimum_size = Vector2(42, 42) * _ui_scale
		icon_view.texture = icon
		icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(icon_view)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", Color("493528") if not muted else Color("8b8177"))
	title_label.add_theme_font_size_override("font_size", _scaled_font(16))
	line.add_child(title_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.add_theme_color_override("font_color", Color("80664d"))
	detail_label.add_theme_font_size_override("font_size", _scaled_font(13))
	line.add_child(detail_label)
	var value_label := Label.new()
	value_label.text = _signed(value)
	value_label.custom_minimum_size.x = 48.0 * _ui_scale
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", Color("278c46") if value >= 0 else Color("c84f4f"))
	value_label.add_theme_font_size_override("font_size", _scaled_font(20))
	line.add_child(value_label)
	_breakdown_rows.add_child(row)


func _clear_breakdown_rows() -> void:
	for child in _breakdown_rows.get_children():
		child.free()


func _show_card(data: Dictionary, previous_total: int, previous_money: int) -> void:
	var color_id := str(data.get("color", "red"))
	var applied_value := int(data.get("value", 0))
	var running_total := int(data.get("running_total", previous_total))
	var money_after := int(data.get("money_after", previous_money))
	_item_title.text = "구간 베팅 카드"
	_card.visible = true
	_dice_icon.visible = false
	_card_portrait.texture = PORTRAITS.get(color_id, PORTRAITS["red"])
	_card_caption.text = "%s 카드  %d" % [CAMEL_NAMES.get(color_id, color_id), int(data.get("printed_value", 0))]
	_set_card_style(CAMEL_COLORS.get(color_id, Color("d88b63")))
	_set_delta(applied_value)
	_current_total.text = "현재 정산  %s → %s" % [_signed(previous_total), _signed(running_total)]
	_coin_total.text = "보유 코인  %d → %d" % [previous_money, money_after]
	await _pop(_card)
	await _count_coin(previous_money, money_after)
	await _wait_or_skip(0.28)


func _show_dice(data: Dictionary, previous_total: int, previous_money: int) -> void:
	var count := int(data.get("dice_roll_count", 0))
	var reward := int(data.get("dice_reward", 0))
	var running_total := int(data.get("dice_running_total", previous_total))
	var money_after := int(data.get("money_after", previous_money))
	_item_title.text = "주사위 굴리기 × %d" % count
	_card.visible = false
	_dice_icon.visible = true
	_set_delta(reward)
	_current_total.text = "현재 정산  %s → %s" % [_signed(previous_total), _signed(running_total)]
	_coin_total.text = "보유 코인  %d → %d" % [previous_money, money_after]
	await _pop(_dice_icon)
	await _count_coin(previous_money, money_after)
	await _wait_or_skip(0.32)


func _show_player_total(data: Dictionary) -> void:
	_card.visible = false
	_dice_icon.visible = false
	_item_title.visible = false
	_item_delta.visible = false
	_current_total.visible = false
	_coin_total.visible = false
	_summary.visible = true
	_summary.text = "[center][font_size=%d][b]%s[/b][/font_size]\n\n카드 정산      [color=#278c46]%s[/color]\n주사위 ×%d      [color=#278c46]%s[/color]\n────────────────\n[font_size=%d][b]이번 라운드   [color=#c47c18]%s 코인[/color][/b][/font_size]\n\n보유 코인  %d → %d[/center]" % [
		_scaled_font(21),
		str(data.get("player_name", "Player")),
		_signed(int(data.get("card_delta", 0))),
		int(data.get("dice_roll_count", 0)),
		_signed(int(data.get("dice_reward", 0))),
		_scaled_font(25),
		_signed(int(data.get("round_delta", 0))),
		int(data.get("money_before", 0)),
		int(data.get("money_after", 0)),
	]
	await _pop(_summary)
	await _wait_or_skip(0.65)


func _show_round_summary(breakdowns: Array) -> void:
	_player_name.text = "라운드 정산 완료"
	_player_badge.text = "모든 플레이어"
	_portrait.texture = null
	_card.visible = false
	_dice_icon.visible = false
	_item_title.visible = false
	_item_delta.visible = false
	_current_total.visible = false
	_coin_total.visible = false
	_breakdown_rows.visible = false
	_table_total.visible = false
	_summary.visible = true
	_progress.text = ""
	var lines: Array[String] = ["[center][font_size=%d][b]전체 결과[/b][/font_size]\n" % _scaled_font(23)]
	for data_value in breakdowns:
		var data := data_value as Dictionary
		lines.append("%s    [color=#c47c18][b]%s 코인[/b][/color]" % [str(data.get("player_name", "Player")), _signed(int(data.get("round_delta", 0)))])
	lines.append("\n잠시 후 다음 라운드가 시작됩니다.[/center]")
	_summary.text = "\n".join(lines)
	await _pop(_summary)


func _set_card_style(color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.34)
	style.set_border_width_all(4)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0.16, 0.08, 0.03, 0.28)
	style.shadow_size = 8
	_card.add_theme_stylebox_override("panel", style)


func _set_delta(value: int) -> void:
	_item_delta.text = _signed(value)
	_item_delta.modulate = Color("288c48") if value >= 0 else Color("c84f4f")


func _signed(value: int) -> String:
	return "%+d" % value


func _pop(control: Control) -> void:
	await get_tree().process_frame
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.72, 0.72)
	control.modulate.a = 0.0
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(control, "scale", Vector2.ONE, 0.2 if not _skip else 0.03)
	_active_tween.tween_property(control, "modulate:a", 1.0, 0.14 if not _skip else 0.03)
	await _active_tween.finished


func _count_coin(from_value: int, to_value: int) -> void:
	if from_value == to_value or _skip:
		_coin_total.text = "보유 코인  %d" % to_value
		return
	_active_tween = create_tween()
	_active_tween.tween_method(func(value: float): _coin_total.text = "보유 코인  %d" % roundi(value), float(from_value), float(to_value), 0.22)
	await _active_tween.finished


func _wait_or_skip(seconds: float) -> void:
	if _skip:
		return
	var elapsed := 0.0
	while elapsed < seconds and not _skip:
		elapsed += get_process_delta_time()
		await get_tree().process_frame


func _request_skip() -> void:
	_skip = true
	_skip_button.text = "빠르게 보는 중…"
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.set_speed_scale(12.0)


func _apply_responsive_size() -> void:
	var viewport_size := get_viewport_rect().size
	# The project renders a 1080x1920 logical canvas into mobile browser pixels.
	# Scale this modal from its editor-friendly 430px base so it still occupies
	# most of a 390px phone instead of becoming a tiny card in the middle.
	var responsive_scale := clampf(minf(viewport_size.x / 480.0, viewport_size.y / 760.0), 0.82, 2.35)
	_ui_scale = responsive_scale
	_local_theme.default_base_scale = responsive_scale
	_panel.custom_minimum_size.x = minf(430.0 * responsive_scale, viewport_size.x - 56.0)
	_panel.custom_minimum_size.y = minf(650.0 * responsive_scale, viewport_size.y - 112.0)
	_panel.scale = Vector2.ONE
	_round_title.add_theme_font_size_override("font_size", _scaled_font(25))
	_portrait.custom_minimum_size = Vector2(82, 82) * responsive_scale
	_player_name.add_theme_font_size_override("font_size", _scaled_font(26))
	_player_badge.add_theme_font_size_override("font_size", _scaled_font(13))
	_item_title.add_theme_font_size_override("font_size", _scaled_font(17))
	_card.custom_minimum_size = Vector2(178, 196) * responsive_scale
	_card_portrait.custom_minimum_size = Vector2(132, 128) * responsive_scale
	_card_caption.add_theme_font_size_override("font_size", _scaled_font(18))
	_dice_icon.custom_minimum_size = Vector2(132, 132) * responsive_scale
	_item_delta.add_theme_font_size_override("font_size", _scaled_font(37))
	_current_total.add_theme_font_size_override("font_size", _scaled_font(18))
	_coin_total.add_theme_font_size_override("font_size", _scaled_font(16))
	_table_total.add_theme_font_size_override("font_size", _scaled_font(20))
	_summary.add_theme_font_size_override("normal_font_size", _scaled_font(18))
	_progress.add_theme_font_size_override("font_size", _scaled_font(13))
	_skip_button.custom_minimum_size.y = 48.0 * responsive_scale
	_skip_button.add_theme_font_size_override("font_size", _scaled_font(16))
	call_deferred("_refresh_panel_pivot")


func _refresh_panel_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5


func _scaled_font(base_size: int) -> int:
	return maxi(11, roundi(float(base_size) * _ui_scale))
