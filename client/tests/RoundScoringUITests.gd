extends SceneTree

var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(390, 844)
	var ui := (load("res://scenes/ui/RoundScoringUI.tscn") as PackedScene).instantiate() as CamelRoundScoringUI
	root.add_child(ui)
	var breakdowns := [{
		"player_id": "player_1", "player_name": "테스트", "money_before": 3,
		"betting_cards": [{"card_id": "card", "color": "red", "printed_value": 5, "value": 5, "running_total": 5, "money_after": 8}],
		"card_delta": 5, "dice_roll_count": 2, "dice_reward": 2,
		"dice_running_total": 7, "round_delta": 7, "money_after": 10,
	}]
	ui.play_round_scoring(1, breakdowns)
	await process_frame
	_check(ui.visible, "round scoring overlay opens")
	ui._request_skip()
	var elapsed := 0.0
	while ui.visible and elapsed < 2.0:
		await create_timer(0.02).timeout
		elapsed += 0.02
	_check(not ui.visible, "fast-forward completes animation without changing result data")
	_check(int(breakdowns[0]["round_delta"]) == 7 and int(breakdowns[0]["money_after"]) == 10, "scoring UI only consumes authoritative values")
	print("Round scoring UI: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed = true
		push_error("FAIL: " + label)
