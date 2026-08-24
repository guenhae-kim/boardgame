class_name CamelGameEventQueue
extends RefCounted

var _events: Array = []
var is_playing := false


func enqueue_all(events: Array) -> void:
	_events.append_array(events)


func clear() -> void:
	_events.clear()
	is_playing = false


func is_empty() -> bool:
	return _events.is_empty()


func play_all(handler: Callable) -> void:
	is_playing = true
	while not _events.is_empty():
		var event: CamelEvent = _events.pop_front() as CamelEvent
		await handler.call(event)
	is_playing = false
