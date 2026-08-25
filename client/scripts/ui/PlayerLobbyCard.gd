class_name CamelPlayerLobbyCard
extends PanelContainer

const PORTRAITS := [
	preload("res://assets/art/portraits/red-corgi.png"),
	preload("res://assets/art/portraits/blue-kitten.png"),
	preload("res://assets/art/portraits/green-rabbit.png"),
	preload("res://assets/art/portraits/yellow-duck.png"),
]
const SLOT_COLORS := [Color("d45c43"), Color("447ec5"), Color("4d9b70"), Color("e7a52d")]

@onready var slot_badge: Label = $Layer/SlotBadge
@onready var role_badge: Label = $Layer/RoleBadge
@onready var portrait: TextureRect = $Layer/Content/Portrait
@onready var nickname: Label = $Layer/Content/Nickname
@onready var status: Label = $Layer/Content/Status

var _occupied := false


func set_slot(index: int, player: Dictionary) -> void:
	var now_occupied := not player.is_empty()
	slot_badge.text = str(index + 1)
	slot_badge.modulate = SLOT_COLORS[index % SLOT_COLORS.size()]
	if now_occupied:
		portrait.texture = PORTRAITS[index % PORTRAITS.size()]
		portrait.modulate = Color.WHITE if bool(player.get("connected", true)) else Color(0.62, 0.62, 0.62, 0.8)
		nickname.text = str(player.get("nickname", "친구"))
		var is_host := bool(player.get("is_host", false))
		var is_cpu := bool(player.get("is_cpu", false))
		role_badge.visible = is_host or is_cpu
		role_badge.text = "HOST" if is_host else "CPU"
		status.text = "접속 완료  ✓" if bool(player.get("connected", true)) else "다시 들어오길 기다리는 중…"
		status.modulate = Color("4c8a68") if bool(player.get("connected", true)) else Color("a36e5a")
	else:
		portrait.texture = preload("res://assets/ui/paw_icon.svg")
		portrait.modulate = Color(0.48, 0.4, 0.3, 0.22)
		nickname.text = "친구를 기다리는 중…"
		role_badge.visible = false
		status.text = "빈 자리"
		status.modulate = Color(0.48, 0.4, 0.3, 0.62)
	if now_occupied and not _occupied and is_inside_tree():
		_pop_in()
	_occupied = now_occupied


func _pop_in() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.86, 0.86)
	modulate.a = 0.4
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
