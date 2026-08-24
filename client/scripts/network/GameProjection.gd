class_name CamelGameProjection
extends RefCounted

static func public_state(state: CamelGameState) -> Dictionary:
	var result := state.to_dict()
	var public_players: Array = []
	for source in result.get("players", []):
		var player := (source as Dictionary).duplicate(true)
		player.erase("final_cards")
		public_players.append(player)
	result["players"] = public_players
	result["final_winner_bets"] = _hidden_bets(state.final_winner_bets)
	result["final_loser_bets"] = _hidden_bets(state.final_loser_bets)
	return result

static func private_states(state: CamelGameState) -> Dictionary:
	var result := {}
	for player in state.players:
		var player_id := str(player["id"])
		result[player_id] = {
			"player_id": player_id,
			"final_cards": (player["final_cards"] as Array).duplicate(),
		}
	return result

static func sanitized_events(events: Array) -> Array:
	var result: Array = []
	for source in events:
		var event_dict: Dictionary = source.to_dict() if source is CamelEvent else (source as Dictionary).duplicate(true)
		var data := (event_dict.get("data", {}) as Dictionary).duplicate(true)
		if str(event_dict.get("type", "")) == CamelEvent.FINAL_BET_PLACED:
			data.erase("camel")
		if str(event_dict.get("type", "")) == CamelEvent.GAME_STARTED:
			var players: Array = []
			for source_player in data.get("players", []):
				var player := (source_player as Dictionary).duplicate(true)
				player.erase("final_cards")
				players.append(player)
			data["players"] = players
		result.append({"type": str(event_dict.get("type", "")), "data": data})
	return result

static func state_for_client(public_data: Dictionary, private_data: Dictionary) -> CamelGameState:
	var merged := public_data.duplicate(true)
	var private_player_id := str(private_data.get("player_id", ""))
	for player in merged.get("players", []):
		if str(player.get("id", "")) == private_player_id:
			player["final_cards"] = (private_data.get("final_cards", []) as Array).duplicate()
		elif not player.has("final_cards"):
			player["final_cards"] = []
	return CamelGameState.from_dict(merged)

static func events_from_dict(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var event := value as Dictionary
		result.append(CamelEvent.new(str(event.get("type", "")), event.get("data", {}) as Dictionary))
	return result

static func _hidden_bets(values: Array) -> Array:
	var result: Array = []
	for source in values:
		var bet := source as Dictionary
		result.append({"player_id": str(bet.get("player_id", "")), "sequence": int(bet.get("sequence", 0))})
	return result
