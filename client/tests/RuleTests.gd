extends SceneTree

var passed := 0
var failed := 0


func _init() -> void:
	_test_setup_and_serialization()
	_test_invalid_action_is_atomic()
	_test_pyramid_selects_without_replacement()
	_test_stack_movement()
	_test_crazy_pair_top_moves()
	_test_oasis_and_mirage()
	_test_spectator_placement_validation()
	_test_leg_scoring_and_money_floor()
	_test_leg_scoring_breakdown_and_event_order()
	_test_six_player_partnership()
	_test_final_bet_scoring_and_tie()
	_test_online_projection_hides_private_cards()
	_test_cpu_uses_rules_until_game_end()
	_test_full_game_can_finish()
	print("\nCamel Up rules: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _rules(player_count: int = 3) -> CamelGameRules:
	var names: Array = []
	for index in player_count:
		names.append("P%d" % (index + 1))
	return CamelGameRules.new(names, 12345)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _test_setup_and_serialization() -> void:
	var rules := _rules()
	_check(rules.state.players.size() == 3, "setup creates players")
	_check(rules.state.camels.size() == 7, "setup creates seven camels")
	_check(rules.state.remaining_dice.size() == 6, "setup creates six dice")
	var restored := CamelGameState.from_dict(rules.state.to_dict())
	_check(restored.to_dict() == rules.state.to_dict(), "GameState round trip preserves full state")


func _test_invalid_action_is_atomic() -> void:
	var rules := _rules()
	var before := rules.state.to_json()
	var result := rules.apply_action("player_2", CamelAction.new(CamelAction.ROLL_DIE))
	_check(not bool(result["ok"]), "out-of-turn action is rejected")
	_check(before == rules.state.to_json(), "invalid action does not mutate state")


func _test_pyramid_selects_without_replacement() -> void:
	var rules := _rules()
	var selected: Array = []
	for unused in 5:
		var die_id := rules.choose_next_die()
		_check(die_id in rules.state.remaining_dice, "pyramid selects only a remaining die")
		_check(die_id not in selected, "pyramid does not select the same die twice in one leg")
		selected.append(die_id)
		rules.force_next_roll(die_id, 1)
		var player_id := str(rules.state.current_player()["id"])
		rules.apply_action(player_id, CamelAction.new(CamelAction.ROLL_DIE))
	_check(selected.size() == 5, "pyramid reveals five of six dice before leg scoring")


func _test_stack_movement() -> void:
	var rules := _rules()
	CamelGameDebug.force_stacks(rules, {2: ["blue", "red", "yellow"], 5: ["green"], 10: ["purple"], 15: ["white"], 14: ["black"]})
	rules.force_next_roll("red", 3)
	var result := rules.apply_action("player_1", CamelAction.new(CamelAction.ROLL_DIE))
	_check(bool(result["ok"]), "forced race die roll is valid")
	_check(rules.state.dice_history == [{"die": "red", "camel": "red", "value": 3}], "roll is recorded in serializable round dice history")
	_check(rules.state.stack_at(2) == ["blue"], "camels below moving camel stay")
	_check(rules.state.stack_at(5) == ["green", "red", "yellow"], "moving camel carries all above and lands on top")


func _test_crazy_pair_top_moves() -> void:
	var rules := _rules()
	CamelGameDebug.force_stacks(rules, {12: ["white", "black", "blue"], 3: ["red"], 4: ["yellow"], 5: ["green"], 6: ["purple"]})
	rules.force_next_roll("gray", 2)
	var result := rules.apply_action("player_1", CamelAction.new(CamelAction.ROLL_DIE))
	_check(bool(result["ok"]), "gray die roll is valid")
	_check(rules.state.camel_position("white") == 12, "lower crazy camel stays when pair directly stacked")
	_check(rules.state.camel_position("black") == 10, "top crazy camel moves regardless of gray face")
	_check(rules.state.camel_position("blue") == 10, "top crazy camel carries race camel")


func _test_oasis_and_mirage() -> void:
	var oasis := _rules()
	CamelGameDebug.force_stacks(oasis, {2: ["blue"], 4: ["red"], 6: ["yellow"], 8: ["green"], 10: ["purple"], 14: ["white"], 15: ["black"]})
	oasis.state.spectator_tiles["5"] = {"owner_id": "player_2", "side": "oasis"}
	oasis.force_next_roll("blue", 3)
	oasis.apply_action("player_1", CamelAction.new(CamelAction.ROLL_DIE))
	_check(oasis.state.stack_at(6) == ["yellow", "blue"], "oasis advances and lands on top")
	_check(int(oasis.state.player_by_id("player_2")["money"]) == 4, "spectator owner earns one")

	var mirage := _rules()
	CamelGameDebug.force_stacks(mirage, {2: ["blue"], 4: ["red"], 6: ["yellow"], 8: ["green"], 10: ["purple"], 14: ["white"], 15: ["black"]})
	mirage.state.spectator_tiles["5"] = {"owner_id": "player_2", "side": "mirage"}
	mirage.force_next_roll("blue", 3)
	mirage.apply_action("player_1", CamelAction.new(CamelAction.ROLL_DIE))
	_check(mirage.state.stack_at(4) == ["blue", "red"], "mirage moves backward and inserts underneath")


func _test_leg_scoring_and_money_floor() -> void:
	var rules := _rules()
	CamelGameDebug.force_stacks(rules, {8: ["blue"], 7: ["red"], 6: ["yellow"], 5: ["green"], 4: ["purple"], 14: ["white"], 15: ["black"]})
	rules.state.player_by_id("player_1")["leg_tickets"] = [{"camel": "blue", "value": 5}, {"camel": "purple", "value": 2}]
	rules.state.player_by_id("player_1")["pyramid_tickets"] = 2
	rules.state.player_by_id("player_2")["money"] = 0
	rules.state.player_by_id("player_2")["leg_tickets"] = [{"camel": "purple", "value": 2}]
	rules.debug_resolve_leg()
	_check(int(rules.state.player_by_id("player_1")["money"]) == 9, "leg tickets and pyramid tickets score correctly")
	_check(int(rules.state.player_by_id("player_2")["money"]) == 0, "money never drops below zero")
	_check(rules.state.leg_number == 2 and rules.state.remaining_dice.size() == 6, "new leg resets dice and advances leg")


func _test_leg_scoring_breakdown_and_event_order() -> void:
	var rules := _rules()
	CamelGameDebug.force_stacks(rules, {8: ["blue"], 7: ["red"], 6: ["yellow"], 5: ["green"], 4: ["purple"], 14: ["white"], 15: ["black"]})
	rules.state.player_by_id("player_1")["leg_tickets"] = [{"camel": "blue", "value": 5}, {"camel": "purple", "value": 2}]
	rules.state.player_by_id("player_1")["pyramid_tickets"] = 2
	var events := rules.debug_resolve_leg()
	var leg_event: CamelEvent
	var leg_index := -1
	var first_money_index := -1
	for index in events.size():
		var event := events[index] as CamelEvent
		if event.type == CamelEvent.LEG_ENDED:
			leg_event = event
			leg_index = index
		if first_money_index < 0 and event.type == CamelEvent.MONEY_CHANGED:
			first_money_index = index
	_check(leg_event != null, "leg end publishes authoritative scoring breakdown")
	_check(leg_index >= 0 and first_money_index > leg_index, "detailed scoring presentation precedes legacy money events")
	var breakdowns := leg_event.data.get("scoring", []) as Array
	var player_one := breakdowns[0] as Dictionary
	var cards := player_one.get("betting_cards", []) as Array
	_check(cards.size() == 2, "breakdown contains each acquired betting card")
	_check(int((cards[0] as Dictionary)["value"]) == 5 and int((cards[1] as Dictionary)["value"]) == -1, "betting card outcomes come from race order rules")
	_check(str((cards[0] as Dictionary)["result_category"]) == "first" and int((cards[0] as Dictionary)["finish_rank"]) == 1, "breakdown labels first-place ticket outcome authoritatively")
	_check(str((cards[1] as Dictionary)["result_category"]) == "other" and int((cards[1] as Dictionary)["finish_rank"]) == 5, "breakdown labels losing ticket outcome authoritatively")
	_check(int(player_one["dice_roll_count"]) == 2 and int(player_one["dice_reward"]) == 2, "dice action count pays one coin per roll")
	_check(int(player_one["round_delta"]) == 6, "round delta contains only betting cards and dice reward")
	_check(not player_one.has("spectator") and not player_one.has("final_bets"), "round breakdown excludes immediate spectator and final prediction scoring")

	var last_roll := _rules()
	CamelGameDebug.force_stacks(last_roll, {2: ["blue"], 4: ["red"], 6: ["yellow"], 8: ["green"], 10: ["purple"], 14: ["white"], 15: ["black"]})
	last_roll.state.remaining_dice = ["blue", "gray"]
	last_roll.state.pyramid_tickets_remaining = 1
	last_roll.force_next_roll("blue", 1)
	var result := last_roll.apply_action("player_1", CamelAction.new(CamelAction.ROLL_DIE))
	var types: Array = []
	for event_value in result.get("events", []):
		types.append((event_value as CamelEvent).type)
	_check(types.find(CamelEvent.DIE_ROLLED) < types.find(CamelEvent.CAMEL_MOVED), "last die result is emitted before piece movement")
	_check(types.find(CamelEvent.CAMEL_MOVED) < types.find(CamelEvent.TURN_ENDED), "piece movement completes before turn-end presentation")
	_check(types.find(CamelEvent.TURN_ENDED) < types.find(CamelEvent.LEG_ENDED), "round scoring starts only after turn-end overview event")


func _test_spectator_placement_validation() -> void:
	var rules := _rules()
	CamelGameDebug.force_stacks(rules, {2: ["blue"], 4: ["red"], 6: ["yellow"], 8: ["green"], 10: ["purple"], 14: ["white"], 15: ["black"]})
	var occupied := rules.apply_action("player_1", CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": 4, "side": "oasis"}))
	_check(not bool(occupied["ok"]), "spectator tile rejects camel-occupied space")
	var first := rules.apply_action("player_1", CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": 12, "side": "oasis"}))
	_check(bool(first["ok"]), "spectator tile accepts legal empty space")
	var adjacent := rules.apply_action("player_2", CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": 11, "side": "mirage"}))
	_check(not bool(adjacent["ok"]), "spectator tile rejects space adjacent to another tile")


func _test_six_player_partnership() -> void:
	var rules := _rules(6)
	CamelGameDebug.force_stacks(rules, {8: ["blue"], 7: ["red"], 6: ["yellow"], 5: ["green"], 4: ["purple"], 14: ["white"], 15: ["black"]})
	rules.state.player_by_id("player_1")["leg_tickets"] = [{"camel": "blue", "value": 5}]
	rules.state.player_by_id("player_2")["pyramid_tickets"] = 2
	rules.state.player_by_id("player_1")["partner_with"] = "player_2"
	rules.state.player_by_id("player_2")["partner_with"] = "player_1"
	rules.debug_resolve_leg()
	_check(int(rules.state.player_by_id("player_1")["money"]) == 9, "partner copies one best positive pyramid ticket reward")
	_check(int(rules.state.player_by_id("player_2")["money"]) == 10, "partner copies one best positive leg betting ticket reward")
	_check(str(rules.state.player_by_id("player_1")["partner_with"]).is_empty(), "partnership resets after leg")


func _test_final_bet_scoring_and_tie() -> void:
	var rules := _rules(2)
	CamelGameDebug.force_stacks(rules, {17: ["blue"], 10: ["red"], 8: ["yellow"], 6: ["green"], 2: ["purple"], 14: ["white"], 15: ["black"]})
	rules.state.final_winner_bets = [{"player_id": "player_1", "camel": "blue"}, {"player_id": "player_2", "camel": "red"}]
	rules.state.final_loser_bets = [{"player_id": "player_2", "camel": "purple"}, {"player_id": "player_1", "camel": "purple"}]
	rules.debug_resolve_game("test")
	_check(int(rules.state.player_by_id("player_1")["money"]) == 16, "correct early winner and later loser bets use 8/5 rewards")
	_check(int(rules.state.player_by_id("player_2")["money"]) == 10, "wrong bet loses one and correct first loser bet gains eight")
	_check(rules.state.phase == "GAME_OVER", "final scoring ends game")
	var tied := _rules(2)
	CamelGameDebug.force_stacks(tied, {17: ["blue"], 10: ["red"], 8: ["yellow"], 6: ["green"], 2: ["purple"], 14: ["white"], 15: ["black"]})
	tied.debug_resolve_game("tie_test")
	_check(tied.state.winners == ["player_1", "player_2"], "equal richest players share victory")


func _test_online_projection_hides_private_cards() -> void:
	var rules := _rules(2)
	rules.state.final_winner_bets = [{"player_id": "player_1", "camel": "red", "sequence": 1}]
	var public := CamelGameProjection.public_state(rules.state)
	_check(not (public["players"][0] as Dictionary).has("final_cards"), "public state omits every player's private hand")
	_check(not (public["final_winner_bets"][0] as Dictionary).has("camel"), "public prediction stack omits hidden animal")
	var private := CamelGameProjection.private_states(rules.state)
	var client_state := CamelGameProjection.state_for_client(public, private["player_2"])
	_check((client_state.player_by_id("player_2")["final_cards"] as Array).size() == 5, "recipient receives only its own private hand")
	_check((client_state.player_by_id("player_1")["final_cards"] as Array).is_empty(), "recipient cannot reconstruct another player's hand")


func _test_cpu_uses_rules_until_game_end() -> void:
	var rules := _rules(4)
	for player in rules.state.players: player["is_cpu"] = true
	var cpu := CamelCPUController.new(); cpu._rng.seed = 4242
	var turns := 0
	var all_legal := true
	while rules.state.phase == "PLAYING" and turns < 500:
		var player_id := str(rules.state.current_player()["id"])
		var action := cpu.choose_action(rules, player_id)
		var result := rules.apply_action(player_id, action)
		if not bool(result.get("ok", false)): all_legal = false; break
		turns += 1
	_check(all_legal, "CPU submits only actions validated by the shared GameRules")
	_check(rules.state.phase == "GAME_OVER", "four CPU-compatible players can finish a complete game")


func _test_full_game_can_finish() -> void:
	var rules := _rules(4)
	var actions := 0
	while rules.state.phase == "PLAYING" and actions < 500:
		var player_id := str(rules.state.current_player()["id"])
		var result := rules.apply_action(player_id, CamelAction.new(CamelAction.ROLL_DIE))
		_check(bool(result["ok"]), "autoplay roll %d accepted" % actions)
		actions += 1
	_check(rules.state.phase == "GAME_OVER", "deterministic autoplay reaches game end")
	_check(not rules.state.winners.is_empty(), "game end computes at least one winner")
