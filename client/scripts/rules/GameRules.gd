class_name CamelGameRules
extends RefCounted

const FINAL_REWARDS := [8, 5, 3, 2]

var state: CamelGameState
var _rng := RandomNumberGenerator.new()
var _forced_die := ""
var _forced_value := 0


func _init(player_names: Array = [], seed_value: int = 0) -> void:
	if not player_names.is_empty():
		start_new_game(player_names, seed_value)


func start_new_game(player_names: Array, seed_value: int = 0) -> Array:
	var names := player_names.duplicate()
	if names.size() < 2:
		names = ["Player 1", "Player 2"]
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0)
	_rng.seed = seed_value
	state = CamelGameState.new()
	state.initialize(names, seed_value)
	_setup_camels()
	state.rng_state = _rng.state
	return [
		CamelEvent.new(CamelEvent.GAME_STARTED, {"players": state.players.duplicate(true), "seed": seed_value}),
		CamelEvent.new(CamelEvent.TURN_STARTED, _turn_data()),
	]


func load_state(saved_state: CamelGameState) -> void:
	state = saved_state
	_rng.state = state.rng_state


func apply_action(player_id: String, action: CamelAction) -> Dictionary:
	var error := validate_action(player_id, action)
	if not error.is_empty():
		return {"ok": false, "error": error, "events": []}

	var events: Array = []
	match action.type:
		CamelAction.TAKE_LEG_BET:
			_take_leg_bet(player_id, str(action.data["camel"]), events)
		CamelAction.PLACE_SPECTATOR:
			_place_spectator(player_id, int(action.data["space"]), str(action.data["side"]), events)
		CamelAction.ROLL_DIE:
			_roll_die(player_id, events)
		CamelAction.FINAL_BET:
			_place_final_bet(player_id, str(action.data["camel"]), str(action.data["bet"]), events)
		CamelAction.PARTNER:
			_create_partnership(player_id, str(action.data["target_player_id"]), events)

	if state.phase == "GAME_OVER":
		state.rng_state = _rng.state
		return {"ok": true, "error": "", "events": events}

	events.append(CamelEvent.new(CamelEvent.TURN_ENDED, {
		"player_id": player_id,
		"turn": state.turn_number,
	}))
	if state.remaining_dice.size() == 1:
		_resolve_leg(events, false)
	else:
		_advance_turn(events)
	state.rng_state = _rng.state
	return {"ok": true, "error": "", "events": events}


func validate_action(player_id: String, action: CamelAction) -> String:
	if state == null:
		return "게임이 시작되지 않았습니다."
	if state.phase != "PLAYING":
		return "이미 게임이 종료되었습니다."
	if state.player_index(player_id) < 0:
		return "존재하지 않는 플레이어입니다."
	if str(state.current_player()["id"]) != player_id:
		return "현재 플레이어의 차례가 아닙니다."

	match action.type:
		CamelAction.TAKE_LEG_BET:
			var camel := str(action.data.get("camel", ""))
			if camel not in CamelGameState.RACE_CAMELS:
				return "유효한 경주 낙타 색을 선택하세요."
			if (state.betting_stacks.get(camel, []) as Array).is_empty():
				return "그 색의 구간 베팅 타일이 남아 있지 않습니다."
		CamelAction.PLACE_SPECTATOR:
			var space := int(action.data.get("space", -1))
			var side := str(action.data.get("side", ""))
			if side not in ["oasis", "mirage"]:
				return "관중 타일 면은 oasis 또는 mirage여야 합니다."
			if space < 2 or space > CamelGameState.TRACK_LENGTH:
				return "관중 타일은 1번 칸 또는 트랙 밖에 놓을 수 없습니다."
			if not state.stack_at(space).is_empty():
				return "낙타가 있는 칸에는 관중 타일을 놓을 수 없습니다."
			for tile_key in state.spectator_tiles:
				var tile := state.spectator_tiles[tile_key] as Dictionary
				if str(tile["owner_id"]) == player_id:
					continue
				var occupied := int(tile_key)
				if occupied == space or _spaces_are_adjacent(occupied, space):
					return "다른 관중 타일과 같은 칸 또는 인접한 칸에는 놓을 수 없습니다."
		CamelAction.ROLL_DIE:
			if state.remaining_dice.size() <= 1 or state.pyramid_tickets_remaining <= 0:
				return "이번 구간에 굴릴 수 있는 주사위가 없습니다."
		CamelAction.FINAL_BET:
			var camel := str(action.data.get("camel", ""))
			var bet := str(action.data.get("bet", ""))
			if camel not in CamelGameState.RACE_CAMELS:
				return "유효한 경주 낙타 색을 선택하세요."
			if bet not in ["winner", "loser"]:
				return "최종 베팅은 winner 또는 loser여야 합니다."
			if camel not in (state.player_by_id(player_id)["final_cards"] as Array):
				return "이미 사용한 최종 베팅 카드입니다."
		CamelAction.PARTNER:
			if state.players.size() < 6:
				return "파트너 행동은 6명 이상 게임에서만 사용합니다."
			var target_id := str(action.data.get("target_player_id", ""))
			if target_id == player_id or state.player_index(target_id) < 0:
				return "유효한 다른 플레이어를 선택하세요."
			var me := state.player_by_id(player_id)
			var target := state.player_by_id(target_id)
			if not bool(me["partnership_available"]) or not bool(target["partnership_available"]):
				return "둘 중 한 명의 파트너 카드가 이미 사용되었습니다."
		_:
			return "알 수 없는 행동입니다."
	return ""


func get_race_order() -> Array:
	var order := CamelGameState.RACE_CAMELS.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool:
		var position_a := state.camel_position(a)
		var position_b := state.camel_position(b)
		if position_a != position_b:
			return position_a > position_b
		var stack := state.stack_at(position_a)
		return stack.find(a) > stack.find(b)
	)
	return order


func available_actions(player_id: String) -> Array:
	if state == null or state.phase != "PLAYING" or str(state.current_player()["id"]) != player_id:
		return []
	var result: Array = []
	for camel in CamelGameState.RACE_CAMELS:
		if not (state.betting_stacks[camel] as Array).is_empty():
			result.append(CamelAction.new(CamelAction.TAKE_LEG_BET, {"camel": camel}))
	if state.remaining_dice.size() > 1:
		result.append(CamelAction.new(CamelAction.ROLL_DIE))
	for camel in state.player_by_id(player_id)["final_cards"]:
		result.append(CamelAction.new(CamelAction.FINAL_BET, {"camel": camel, "bet": "winner"}))
		result.append(CamelAction.new(CamelAction.FINAL_BET, {"camel": camel, "bet": "loser"}))
	return result


func force_next_roll(die_id: String, value: int) -> void:
	_forced_die = die_id
	_forced_value = clampi(value, 1, 3)


func choose_next_die() -> String:
	if state == null or state.remaining_dice.size() <= 1:
		return ""
	return str(state.remaining_dice[_rng.randi_range(0, state.remaining_dice.size() - 1)])


func debug_resolve_leg() -> Array:
	var events: Array = []
	_resolve_leg(events, false)
	return events


func debug_resolve_game(reason: String = "debug") -> Array:
	var events: Array = []
	_finish_game(reason, events)
	return events


func _setup_camels() -> void:
	for camel in CamelGameState.RACE_CAMELS:
		_add_to_stack(camel, _rng.randi_range(1, 3))
	var first_color: String = str(CamelGameState.CRAZY_CAMELS[_rng.randi_range(0, 1)])
	var second_color: String = "black" if first_color == "white" else "white"
	_add_to_stack(first_color, 17 - _rng.randi_range(1, 3))
	_add_to_stack(second_color, 17 - _rng.randi_range(1, 3))


func _add_to_stack(camel_id: String, position: int) -> void:
	var stack := state.stack_at(position)
	stack.append(camel_id)
	state.set_stack(position, stack)


func _take_leg_bet(player_id: String, camel: String, events: Array) -> void:
	var stack := state.betting_stacks[camel] as Array
	var value := int(stack.pop_back())
	(state.player_by_id(player_id)["leg_tickets"] as Array).append({"camel": camel, "value": value})
	events.append(CamelEvent.new(CamelEvent.LEG_BET_TAKEN, {"player_id": player_id, "camel": camel, "value": value}))


func _place_spectator(player_id: String, space: int, side: String, events: Array) -> void:
	for key in state.spectator_tiles.keys():
		if str((state.spectator_tiles[key] as Dictionary)["owner_id"]) == player_id:
			state.spectator_tiles.erase(key)
			break
	state.spectator_tiles[str(space)] = {"owner_id": player_id, "side": side}
	events.append(CamelEvent.new(CamelEvent.SPECTATOR_PLACED, {"player_id": player_id, "space": space, "side": side}))


func _place_final_bet(player_id: String, camel: String, bet: String, events: Array) -> void:
	var player := state.player_by_id(player_id)
	(player["final_cards"] as Array).erase(camel)
	var record := {"player_id": player_id, "camel": camel, "sequence": state.turn_number}
	if bet == "winner":
		state.final_winner_bets.append(record)
	else:
		state.final_loser_bets.append(record)
	events.append(CamelEvent.new(CamelEvent.FINAL_BET_PLACED, {"player_id": player_id, "camel": camel, "bet": bet}))


func _create_partnership(player_id: String, target_id: String, events: Array) -> void:
	var me := state.player_by_id(player_id)
	var target := state.player_by_id(target_id)
	me["partner_with"] = target_id
	target["partner_with"] = player_id
	me["partnership_available"] = false
	target["partnership_available"] = false
	events.append(CamelEvent.new(CamelEvent.PARTNERSHIP_CREATED, {"player_a": player_id, "player_b": target_id}))


func _roll_die(player_id: String, events: Array) -> void:
	var die_id: String
	var value: int
	if not _forced_die.is_empty() and _forced_die in state.remaining_dice:
		die_id = _forced_die
		value = _forced_value
		_forced_die = ""
		_forced_value = 0
	else:
		die_id = str(state.remaining_dice[_rng.randi_range(0, state.remaining_dice.size() - 1)])
		value = _rng.randi_range(1, 3)
	state.remaining_dice.erase(die_id)
	state.pyramid_tickets_remaining -= 1
	state.last_roller_index = state.current_player_index
	state.player_by_id(player_id)["pyramid_tickets"] = int(state.player_by_id(player_id)["pyramid_tickets"]) + 1
	events.append(CamelEvent.new(CamelEvent.PYRAMID_TICKET_TAKEN, {"player_id": player_id}))
	var camel_id := die_id
	if die_id == "gray":
		camel_id = CamelGameState.CRAZY_CAMELS[_rng.randi_range(0, 1)]
	state.dice_history.append({"die": die_id, "camel": camel_id, "value": value})
	events.append(CamelEvent.new(CamelEvent.DIE_ROLLED, {"player_id": player_id, "die": die_id, "camel": camel_id, "value": value}))
	_move_camel(camel_id, value, events)


func _move_camel(requested_camel: String, value: int, events: Array) -> void:
	var source := state.camel_position(requested_camel)
	var source_stack := state.stack_at(source)
	var moving_camel := requested_camel
	if requested_camel in CamelGameState.CRAZY_CAMELS:
		var white_index := source_stack.find("white")
		var black_index := source_stack.find("black")
		if white_index >= 0 and black_index >= 0 and absi(white_index - black_index) == 1:
			moving_camel = str(source_stack[maxi(white_index, black_index)])
	var moving_index := source_stack.find(moving_camel)
	var moving_unit := source_stack.slice(moving_index)
	state.set_stack(source, source_stack.slice(0, moving_index))
	var direction := -1 if moving_camel in CamelGameState.CRAZY_CAMELS else 1
	var destination := source + direction * value
	_land_unit(destination, moving_unit, false)
	events.append(CamelEvent.new(CamelEvent.CAMEL_MOVED, {
		"requested_camel": requested_camel,
		"moving_camel": moving_camel,
		"camels": moving_unit.duplicate(),
		"from": source,
		"to": destination,
		"direction": direction,
		"destination_stack": state.stack_at(destination).duplicate(),
	}))
	_emit_stack_event(destination, events)

	if destination >= 1 and destination <= CamelGameState.TRACK_LENGTH and state.spectator_tiles.has(str(destination)):
		var tile := state.spectator_tiles[str(destination)] as Dictionary
		_change_money(str(tile["owner_id"]), 1, "spectator", events)
		var tile_side := str(tile["side"])
		var tile_destination := destination + direction * (1 if tile_side == "oasis" else -1)
		# The whole unit that just moved is moved again. Mirage puts it underneath.
		var landed_stack := state.stack_at(destination)
		var unit_start := _find_subarray(landed_stack, moving_unit)
		if unit_start >= 0:
			landed_stack = landed_stack.slice(0, unit_start)
			state.set_stack(destination, landed_stack)
			_land_unit(tile_destination, moving_unit, tile_side == "mirage")
			events.append(CamelEvent.new(CamelEvent.SPECTATOR_TRIGGERED, {
				"owner_id": str(tile["owner_id"]), "side": tile_side,
				"from": destination, "to": tile_destination, "camels": moving_unit.duplicate(),
				"direction": direction,
				"destination_stack": state.stack_at(tile_destination).duplicate(),
			}))
			_emit_stack_event(tile_destination, events)
			destination = tile_destination

	if (direction > 0 and destination > CamelGameState.TRACK_LENGTH) or (direction < 0 and destination < 1):
		_finish_game("finish_crossed", events)


func _land_unit(position: int, moving_unit: Array, underneath: bool) -> void:
	var destination_stack := state.stack_at(position)
	if underneath:
		destination_stack = moving_unit + destination_stack
	else:
		destination_stack.append_array(moving_unit)
	state.set_stack(position, destination_stack)


func _emit_stack_event(position: int, events: Array) -> void:
	var stack := state.stack_at(position)
	if stack.size() > 1:
		events.append(CamelEvent.new(CamelEvent.CAMELS_STACKED, {"position": position, "bottom_to_top": stack.duplicate()}))


func _find_subarray(haystack: Array, needle: Array) -> int:
	if needle.is_empty() or needle.size() > haystack.size():
		return -1
	for start in range(haystack.size() - needle.size() + 1):
		if haystack.slice(start, start + needle.size()) == needle:
			return start
	return -1


func _resolve_leg(events: Array, game_is_ending: bool) -> void:
	var order := get_race_order()
	events.append(CamelEvent.new(CamelEvent.LEG_ENDED, {"leg": state.leg_number, "order": order.duplicate(), "dice_history": state.dice_history.duplicate(true)}))
	for player in state.players:
		var player_id := str(player["id"])
		for ticket in player["leg_tickets"]:
			var rank := order.find(str(ticket["camel"]))
			var reward := int(ticket["value"]) if rank == 0 else (1 if rank == 1 else -1)
			_change_money(player_id, reward, "leg_bet", events)
			events.append(CamelEvent.new(CamelEvent.LEG_SCORING, {"player_id": player_id, "source": "leg_bet", "camel": ticket["camel"], "reward": reward}))
		var pyramid_reward := int(player["pyramid_tickets"])
		if pyramid_reward > 0:
			_change_money(player_id, pyramid_reward, "pyramid", events)
			events.append(CamelEvent.new(CamelEvent.LEG_SCORING, {"player_id": player_id, "source": "pyramid", "reward": pyramid_reward}))

	# In 6+ games, each partner independently copies the best positive ticket reward.
	if state.players.size() >= 6:
		for player in state.players:
			var partner_id := str(player["partner_with"])
			if partner_id.is_empty():
				continue
			var bonus := _best_positive_leg_reward(state.player_by_id(partner_id), order)
			if bonus > 0:
				_change_money(str(player["id"]), bonus, "partnership", events)
				events.append(CamelEvent.new(CamelEvent.LEG_SCORING, {"player_id": player["id"], "source": "partnership", "partner_id": partner_id, "reward": bonus}))

	if game_is_ending:
		_clear_leg_player_state()
		state.spectator_tiles.clear()
		return
	var next_starter := state.last_roller_index
	if next_starter < 0:
		next_starter = state.current_player_index
	next_starter = (next_starter + 1) % state.players.size()
	_clear_leg_player_state()
	state.spectator_tiles.clear()
	state.reset_leg_components()
	state.leg_number += 1
	state.starting_player_index = next_starter
	state.current_player_index = next_starter
	state.last_roller_index = -1
	state.turn_number += 1
	events.append(CamelEvent.new(CamelEvent.TURN_STARTED, _turn_data()))


func _best_positive_leg_reward(player: Dictionary, order: Array) -> int:
	var best := 1 if int(player["pyramid_tickets"]) > 0 else 0
	for ticket in player["leg_tickets"]:
		var rank := order.find(str(ticket["camel"]))
		var reward := int(ticket["value"]) if rank == 0 else (1 if rank == 1 else -1)
		best = maxi(best, reward)
	return best


func _clear_leg_player_state() -> void:
	for player in state.players:
		player["leg_tickets"] = []
		player["pyramid_tickets"] = 0
		player["partner_with"] = ""
		player["partnership_available"] = true


func _finish_game(reason: String, events: Array) -> void:
	if state.phase == "GAME_OVER":
		return
	state.phase = "SCORING"
	state.game_end_reason = reason
	events.append(CamelEvent.new(CamelEvent.GAME_END_TRIGGERED, {"reason": reason}))
	_resolve_leg(events, true)
	var order := get_race_order()
	_score_final_pile(state.final_winner_bets, str(order[0]), "winner", events)
	_score_final_pile(state.final_loser_bets, str(order[-1]), "loser", events)
	var richest := -1
	for player in state.players:
		richest = maxi(richest, int(player["money"]))
	state.winners.clear()
	for player in state.players:
		if int(player["money"]) == richest:
			state.winners.append(str(player["id"]))
	state.phase = "GAME_OVER"
	events.append(CamelEvent.new(CamelEvent.GAME_ENDED, {"winners": state.winners.duplicate(), "money": richest, "race_order": order}))


func _score_final_pile(pile: Array, correct_camel: String, bet_type: String, events: Array) -> void:
	var correct_index := 0
	for bet in pile:
		var correct := str(bet["camel"]) == correct_camel
		var reward := -1
		if correct:
			reward = FINAL_REWARDS[correct_index] if correct_index < FINAL_REWARDS.size() else 1
			correct_index += 1
		_change_money(str(bet["player_id"]), reward, "final_%s" % bet_type, events)
		events.append(CamelEvent.new(CamelEvent.FINAL_BET_SCORING, {"player_id": bet["player_id"], "bet": bet_type, "camel": bet["camel"], "correct_camel": correct_camel, "reward": reward}))


func _change_money(player_id: String, amount: int, reason: String, events: Array) -> void:
	var player := state.player_by_id(player_id)
	var before := int(player["money"])
	player["money"] = maxi(0, before + amount)
	events.append(CamelEvent.new(CamelEvent.MONEY_CHANGED, {"player_id": player_id, "before": before, "requested_change": amount, "after": player["money"], "reason": reason}))


func _advance_turn(events: Array) -> void:
	state.current_player_index = (state.current_player_index + 1) % state.players.size()
	state.turn_number += 1
	events.append(CamelEvent.new(CamelEvent.TURN_STARTED, _turn_data()))


func _turn_data() -> Dictionary:
	return {"player_id": state.current_player()["id"], "player_name": state.current_player()["name"], "turn": state.turn_number, "leg": state.leg_number}


func _spaces_are_adjacent(a: int, b: int) -> bool:
	var distance := absi(a - b)
	return distance == 1 or distance == CamelGameState.TRACK_LENGTH - 1
