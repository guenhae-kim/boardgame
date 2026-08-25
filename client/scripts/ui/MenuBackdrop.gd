class_name CamelMenuBackdrop
extends Control

@onready var city_art: TextureRect = $CityArt


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_start_ambient_motion")


func _start_ambient_motion() -> void:
	# A very small parallax breath keeps the menu alive without spending a second
	# 3D viewport on mobile Web. Gameplay keeps the real Path3D cars/signals.
	city_art.pivot_offset = city_art.size * 0.5
	var tween := create_tween().set_loops()
	tween.tween_property(city_art, "scale", Vector2(1.035, 1.035), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(city_art, "position:y", city_art.position.y - 9.0, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(city_art, "scale", Vector2.ONE, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(city_art, "position:y", city_art.position.y, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
