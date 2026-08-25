class_name CamelRoomLobbyUI
extends CanvasLayer

signal start_requested(fill_cpu: bool)
signal cpu_count_requested(count: int)

@onready var root: Control = $Root
@onready var _root: Control = $Root # Compatibility for existing flow diagnostics.
@onready var room_label: Label = $Root/LobbyPanel/Margin/Content/RoomCodePanel/CodeRow/CodeBlock/RoomCode
@onready var copy_button: Button = $Root/LobbyPanel/Margin/Content/RoomCodePanel/CodeRow/CopyButton
@onready var slots: Array[CamelPlayerLobbyCard] = [
	$Root/LobbyPanel/Margin/Content/Slots/Slot1,
	$Root/LobbyPanel/Margin/Content/Slots/Slot2,
	$Root/LobbyPanel/Margin/Content/Slots/Slot3,
	$Root/LobbyPanel/Margin/Content/Slots/Slot4,
]
@onready var host_controls: VBoxContainer = $Root/LobbyPanel/Margin/Content/HostControls
@onready var fill_cpu: CheckButton = $Root/LobbyPanel/Margin/Content/HostControls/CpuPanel/FillCpu
@onready var start_button: Button = $Root/LobbyPanel/Margin/Content/HostControls/StartButton
@onready var guest_hint: Label = $Root/LobbyPanel/Margin/Content/GuestHint
@onready var toast: CamelToast = $Root/Toast

var _room_code := ""


func _ready() -> void:
	copy_button.pressed.connect(_copy_room_code)
	start_button.pressed.connect(func(): start_requested.emit(fill_cpu.button_pressed))
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.3)
	for index in slots.size():
		slots[index].set_slot(index, {})


func update_lobby(payload: Dictionary, local_player_id: String) -> void:
	_room_code = str(payload.get("room_code", "----"))
	room_label.text = _room_code
	var players := payload.get("players", []) as Array
	for index in slots.size():
		var player := players[index] as Dictionary if index < players.size() else {}
		slots[index].set_slot(index, player)
	var is_host := str(payload.get("host_player_id", "")) == local_player_id
	var started := bool(payload.get("started", false))
	host_controls.visible = is_host and not started
	guest_hint.visible = not is_host and not started
	start_button.disabled = started


func show_game() -> void:
	if not root.visible:
		return
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.24)
	await tween.finished
	root.visible = false


func _copy_room_code() -> void:
	DisplayServer.clipboard_set(_room_code)
	toast.show_message("방 코드 복사 완료!")
