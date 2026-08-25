class_name CamelJoinRoomSheet
extends Control

signal join_requested(room_code: String)

@onready var sheet: PanelContainer = $Sheet
@onready var room_code_input: LineEdit = $Sheet/Margin/Content/RoomCode
@onready var join_button: Button = $Sheet/Margin/Content/JoinButton


func _ready() -> void:
	visible = false
	$Dim.gui_input.connect(_on_dim_input)
	$Sheet/Margin/Content/CancelButton.pressed.connect(hide_sheet)
	join_button.pressed.connect(_submit)
	room_code_input.text_submitted.connect(func(_value: String): _submit())
	room_code_input.text_changed.connect(func(value: String):
		var cleaned := value.to_upper()
		if cleaned != value:
			room_code_input.text = cleaned
			room_code_input.caret_column = cleaned.length()
		join_button.disabled = cleaned.strip_edges().length() != 4
	)


func show_sheet() -> void:
	visible = true
	modulate.a = 0.0
	await get_tree().process_frame
	var rest_y := sheet.position.y
	sheet.position.y = rest_y + 140.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	tween.tween_property(sheet, "position:y", rest_y, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	room_code_input.grab_focus()


func hide_sheet() -> void:
	if not visible:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.tween_property(sheet, "position:y", sheet.position.y + 100.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false


func clear_code() -> void:
	room_code_input.clear()
	join_button.disabled = true


func _submit() -> void:
	var code := room_code_input.text.strip_edges().to_upper()
	if code.length() == 4:
		join_requested.emit(code)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_sheet()
