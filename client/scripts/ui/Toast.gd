class_name CamelToast
extends Control

@onready var panel: PanelContainer = $Center/Panel
@onready var message_label: Label = $Center/Panel/Message
var _tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_message(message: String, duration := 2.2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	message_label.text = message
	visible = true
	modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)
	_tween.tween_interval(duration)
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(func(): visible = false)
