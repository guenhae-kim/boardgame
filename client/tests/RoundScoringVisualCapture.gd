extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("99b996")
	root.add_child(background)
	var ui := (load("res://scenes/ui/RoundScoringUI.tscn") as PackedScene).instantiate() as CamelRoundScoringUI
	root.add_child(ui)
	ui.play_round_scoring(2, [
		{
			"player_id": "player_1", "player_name": "꼬부기", "money_before": 12,
			"betting_cards": [
				{"card_id": "p1_leg_2_0", "color": "red", "printed_value": 5, "value": 5, "running_total": 5, "money_after": 17},
				{"card_id": "p1_leg_2_1", "color": "blue", "printed_value": 3, "value": 3, "running_total": 8, "money_after": 20},
				{"card_id": "p1_leg_2_2", "color": "green", "printed_value": 2, "value": -1, "running_total": 7, "money_after": 19},
			],
			"card_delta": 7, "dice_roll_count": 2, "dice_reward": 2,
			"dice_running_total": 9, "round_delta": 9, "money_after": 21,
		},
		{
			"player_id": "player_2", "player_name": "친구", "money_before": 8,
			"betting_cards": [], "card_delta": 0, "dice_roll_count": 1,
			"dice_reward": 1, "dice_running_total": 1, "round_delta": 1, "money_after": 9,
		},
	])
	await create_timer(0.72).timeout
	var image := root.get_viewport().get_texture().get_image()
	var output := "/tmp/camel_round_scoring_390x844.png"
	var error := image.save_png(output)
	print("Round scoring capture: ", output, " ", error_string(error))
	quit(0 if error == OK else 1)
