class_name CamelGameDebug
extends RefCounted

const ENABLED := true


static func force_roll(rules: CamelGameRules, die_id: String, value: int) -> Dictionary:
	if not ENABLED:
		return {"ok": false, "error": "Debug mode is disabled.", "events": []}
	rules.force_next_roll(die_id, value)
	return rules.apply_action(str(rules.state.current_player()["id"]), CamelAction.new(CamelAction.ROLL_DIE))


static func force_stacks(rules: CamelGameRules, stacks: Dictionary) -> CamelEvent:
	if not ENABLED:
		return CamelEvent.new()
	rules.state.stacks.clear()
	for camel_id in rules.state.camels:
		(rules.state.camels[camel_id] as Dictionary)["position"] = 0
	for position in stacks:
		rules.state.set_stack(int(position), stacks[position] as Array)
	return CamelEvent.new(CamelEvent.DEBUG_STATE_CHANGED, {"kind": "force_stacks"})


static func change_money(rules: CamelGameRules, player_id: String, amount: int) -> CamelEvent:
	if not ENABLED:
		return CamelEvent.new()
	var player := rules.state.player_by_id(player_id)
	player["money"] = maxi(0, int(player["money"]) + amount)
	return CamelEvent.new(CamelEvent.DEBUG_STATE_CHANGED, {"kind": "money", "player_id": player_id, "money": player["money"]})


static func prepare_finish(rules: CamelGameRules) -> CamelEvent:
	return force_stacks(rules, {
		14: ["yellow"], 15: ["blue", "red"], 12: ["green"], 10: ["purple"],
		4: ["white"], 7: ["black"],
	})


static func force_end_leg(rules: CamelGameRules) -> Array:
	if not ENABLED:
		return []
	return rules.debug_resolve_leg()


static func force_end_game(rules: CamelGameRules) -> Array:
	if not ENABLED:
		return []
	return rules.debug_resolve_game("debug")


static func force_next_player(rules: CamelGameRules) -> CamelEvent:
	if not ENABLED or rules.state.phase != "PLAYING":
		return CamelEvent.new()
	rules.state.current_player_index = (rules.state.current_player_index + 1) % rules.state.players.size()
	rules.state.turn_number += 1
	return CamelEvent.new(CamelEvent.DEBUG_STATE_CHANGED, {
		"kind": "next_player",
		"player_id": rules.state.current_player()["id"],
	})


static func dump_state(rules: CamelGameRules) -> String:
	return rules.state.to_json()
