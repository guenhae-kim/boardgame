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
@onready var _card: PanelContainer = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card
@onready var _card_portrait: TextureRect = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card/CardBox/CardPortrait
@onready var _card_caption: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/Card/CardBox/CardCaption
@onready var _dice_icon: TextureRect = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/DiceIcon
@onready var _item_delta: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/ItemDelta
@onready var _current_total: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/CurrentTotal
@onready var _coin_total: Label = $Center/Panel/Margin/Content/Stage/StageMargin/StageContent/CoinTotal
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
	_summary.visible = false
	_card.visible = false
	_dice_icon.visible = false
	_item_title.visible = true
	_item_delta.visible = true
	_current_total.visible = true
	_coin_total.visible = true
	var running_before := 0
	var money_cursor := int(data.get("money_before", 0))
	var cards := data.get("betting_cards", []) as Array
	for card_data_value in cards:
		var card_data := card_data_value as Dictionary
		await _show_card(card_data, running_before, money_cursor)
		running_before = int(card_data.get("running_total", running_before))
		money_cursor = int(card_data.get("money_after", money_cursor))

	await _show_dice(data, running_before, money_cursor)
	await _show_player_total(data)


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
	_portrait.custom_minimum_size = Vector2(66, 66) * responsive_scale
	_player_name.add_theme_font_size_override("font_size", _scaled_font(22))
	_player_badge.add_theme_font_size_override("font_size", _scaled_font(13))
	_item_title.add_theme_font_size_override("font_size", _scaled_font(17))
	_card.custom_minimum_size = Vector2(178, 196) * responsive_scale
	_card_portrait.custom_minimum_size = Vector2(132, 128) * responsive_scale
	_card_caption.add_theme_font_size_override("font_size", _scaled_font(18))
	_dice_icon.custom_minimum_size = Vector2(132, 132) * responsive_scale
	_item_delta.add_theme_font_size_override("font_size", _scaled_font(37))
	_current_total.add_theme_font_size_override("font_size", _scaled_font(18))
	_coin_total.add_theme_font_size_override("font_size", _scaled_font(16))
	_summary.add_theme_font_size_override("normal_font_size", _scaled_font(18))
	_progress.add_theme_font_size_override("font_size", _scaled_font(13))
	_skip_button.custom_minimum_size.y = 48.0 * responsive_scale
	_skip_button.add_theme_font_size_override("font_size", _scaled_font(16))
	call_deferred("_refresh_panel_pivot")


func _refresh_panel_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5


func _scaled_font(base_size: int) -> int:
	return maxi(11, roundi(float(base_size) * _ui_scale))
