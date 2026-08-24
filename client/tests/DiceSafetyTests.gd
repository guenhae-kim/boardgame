extends SceneTree

var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dice := CamelDiceController.new()
	root.add_child(dice)
	await process_frame
	var die_ids := ["blue", "yellow", "green", "red", "purple", "gray"]
	for index in die_ids.size():
		var die_id: String = str(die_ids[index])
		var strength := 3.4 if index % 2 == 1 else 1.0
		var result := await dice.play_roll(die_id, 0, strength)
		_check(result in [1, 2, 3], "%s die returns a legal 1-3 face" % die_id)
		_check(absf(dice.die.position.x) <= 3.75 and absf(dice.die.position.z) <= 2.75 and dice.die.position.y >= -0.7, "%s die remains inside the tray at strength %.1f" % [die_id, strength])
	print("Dice containment: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
