extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sound := CamelSoundManager.new()
	root.add_child(sound)
	await process_frame
	var minimums := {
		"ui": 2, "card_select": 2, "card_fly": 2, "card_land": 4,
		"dice_throw": 2, "collision_small": 2, "collision_medium": 2,
		"collision_big": 2, "dice_final": 2, "walk": 3, "land": 2,
		"stack": 2, "coin_gain": 2,
	}
	for cue in minimums:
		_check(sound.variation_count(cue) >= int(minimums[cue]), "%s has physical Foley variations" % cue)
	for cue in sound.loaded_cues():
		for stream in sound._streams[cue]:
			_check(stream is AudioStreamOggVorbis, "%s uses an imported OGG asset" % cue)
			_check((stream as AudioStream).get_length() > 0.0, "%s stream has audible duration" % cue)
			_check((stream as AudioStream).get_length() <= 2.5, "%s stays a short one-shot (%.2fs)" % [cue, (stream as AudioStream).get_length()])
	_check(AudioServer.get_bus_index("BGM") >= 0, "BGM audio bus exists")
	_check(AudioServer.get_bus_index("SFX") >= 0, "SFX audio bus exists")
	_check(AudioServer.get_bus_index("UI") >= 0, "UI audio bus exists")
	_check(AudioServer.get_bus_index("Ambient") >= 0, "Ambient audio bus exists")
	var before := sound.play_count()
	sound.play_collision(0.4)
	_check(sound.play_count() == before, "tiny resting dice contact stays silent")
	sound.play_collision(7.0)
	_check(sound.play_count() == before + 1, "meaningful dice collision selects Foley")
	_check(not FileAccess.get_file_as_string("res://scripts/visual/SoundManager.gd").contains("AudioStreamWAV"), "runtime oscillator prototype is removed")
	for player in sound._players:
		(player as AudioStreamPlayer).stop()
	sound.free()
	quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	_failed = _failed or not condition
