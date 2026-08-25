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
		var strength := 2.25
		var result := await dice.play_roll(die_id, 0, strength)
		elapsed_total += dice.last_roll_simulated_seconds
		print("DICE SAMPLE ", die_id, " strength=", strength, " simulated=", "%.2f" % dice.last_roll_simulated_seconds)
		_check(result in [1, 2, 3], "%s die returns a legal 1-3 face" % die_id)
		_check(dice._read_top_face() == result, "%s natural roll result comes from its actual stopped top face" % die_id)
		_check(absf(dice.die.position.x) <= 3.75 and absf(dice.die.position.z) <= 2.75 and dice.die.position.y >= -0.7, "%s die remains inside the tray at strength %.1f" % [die_id, strength])
	var average := elapsed_total / die_ids.size()
	_check(average <= 2.0, "average physical dice animation stays at or below 2.0 seconds (%.2fs)" % average)
	var synchronized_frames := dice.last_roll_frames.duplicate(true)
	var authority_face := dice._read_top_face()
	var replay_face := await dice.play_authority_replay("gray", synchronized_frames)
	_check(replay_face == authority_face, "remote replay ends on the authority's actual physical face")
	_check(dice.last_roll_frames == synchronized_frames, "remote replay does not run or overwrite an independent physics simulation")
	for forced_value in [1, 2, 3]:
		var visible_result := await dice.play_roll("blue", forced_value, 2.25)
		_check(dice._read_top_face() == visible_result, "legacy requested value %d cannot override the physical top face" % forced_value)
	print("Dice containment: ", "FAILED" if failed else "PASSED", " · average %.2fs" % average)
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
