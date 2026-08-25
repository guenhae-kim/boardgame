extends SceneTree

var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dice := CamelDiceController.new()
	root.add_child(dice)
	await process_frame
	var die_ids := ["blue", "yellow", "green", "red", "purple", "gray"]
	var elapsed_total := 0.0
	for index in die_ids.size():
		var die_id: String = str(die_ids[index])
		var strength := 3.4 if index % 2 == 1 else 1.0
		var started := Time.get_ticks_msec()
		var result := await dice.play_roll(die_id, 0, strength)
		elapsed_total += float(Time.get_ticks_msec() - started) / 1000.0
		_check(result in [1, 2, 3], "%s die returns a legal 1-3 face" % die_id)
		_check(absf(dice.die.position.x) <= 3.75 and absf(dice.die.position.z) <= 2.75 and dice.die.position.y >= -0.7, "%s die remains inside the tray at strength %.1f" % [die_id, strength])
	var average := elapsed_total / die_ids.size()
	_check(average <= 1.6, "average dice animation stays at or below 1.6 seconds (%.2fs)" % average)
	for forced_value in [1, 2, 3]:
		var visible_result := await dice.play_roll("blue", forced_value, 2.25)
		_check(visible_result == forced_value, "authoritative result %d is returned after the visible roll" % forced_value)
		_check(dice._read_top_face() == forced_value, "authoritative result %d is the actual visible top face" % forced_value)
	print("Dice containment: ", "FAILED" if failed else "PASSED", " · average %.2fs" % average)
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
