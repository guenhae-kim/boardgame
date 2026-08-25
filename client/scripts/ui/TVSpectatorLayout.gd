class_name CamelTVSpectatorLayout
extends Control

signal fullscreen_changed(enabled: bool)

@onready var fullscreen_button: Button = $SafeArea/FullscreenButton
@onready var live_badge: Label = $SafeArea/LiveBadge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fullscreen_button.mouse_filter = Control.MOUSE_FILTER_STOP
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	get_viewport().size_changed.connect(_apply_layout)
	_refresh_button()
	_apply_layout()


func _toggle_fullscreen() -> void:
	var entering := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if entering else DisplayServer.WINDOW_MODE_WINDOWED)
	_refresh_button()
	fullscreen_changed.emit(entering)


func _refresh_button() -> void:
	fullscreen_button.text = "전체 화면 종료" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "⛶  전체 화면으로 보기"


func _apply_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var scale := clampf(viewport_size.y / 720.0, 1.0, 3.25)
	var button_size := Vector2(210, 54) * scale
	fullscreen_button.size = button_size
	fullscreen_button.position = Vector2((viewport_size.x - button_size.x) * 0.5, viewport_size.y - button_size.y - 12.0 * scale)
	fullscreen_button.add_theme_font_size_override("font_size", int(17 * scale))
	live_badge.size = Vector2(150, 38) * scale
	live_badge.position = Vector2(viewport_size.x * 0.235, 10.0 * scale)
	live_badge.add_theme_font_size_override("font_size", int(18 * scale))
