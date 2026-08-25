extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var url := NetworkConfig.server_url()
	var socket := WebSocketPeer.new()
	var connect_error := socket.connect_to_url(url)
	if connect_error != OK:
		push_error("Public WSS connect call failed: " + error_string(connect_error))
		quit(1)
		return
	var elapsed := 0.0
	while socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and elapsed < 15.0:
		socket.poll()
		await create_timer(0.05).timeout
		elapsed += 0.05
	var connected := socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	print("Public editor connection: ", "PASSED" if connected else "FAILED", " · ", url)
	if connected:
		socket.close()
	quit(0 if connected else 1)
