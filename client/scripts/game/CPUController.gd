class_name CamelCPUController
extends RefCounted

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func choose_action(rules: CamelGameRules, player_id: String) -> CamelAction:
	var legal := rules.available_actions(player_id)
	var spectator := _spectator_action(rules, player_id)
	if spectator != null:
		legal.append(spectator)
	if legal.is_empty():
		return CamelAction.new()
	for action in legal:
		if (action as CamelAction).type == CamelAction.ROLL_DIE and _rng.randf() < 0.52:
			return action
	var order := rules.get_race_order()
	for action in legal:
		var candidate := action as CamelAction
		if candidate.type == CamelAction.TAKE_LEG_BET and str(candidate.data.get("camel", "")) == str(order[0]):
			return candidate
	return legal[_rng.randi_range(0, legal.size() - 1)] as CamelAction

func _spectator_action(rules: CamelGameRules, player_id: String) -> CamelAction:
	var spaces: Array[int] = []
	for space in range(2, CamelGameState.TRACK_LENGTH + 1):
		var action := CamelAction.new(CamelAction.PLACE_SPECTATOR, {
			"space": space,
			"side": "oasis" if _rng.randf() < 0.5 else "mirage",
		})
		if rules.validate_action(player_id, action).is_empty():
			spaces.append(space)
	if spaces.is_empty() or _rng.randf() > 0.18:
		return null
	var space := spaces[_rng.randi_range(0, spaces.size() - 1)]
	return CamelAction.new(CamelAction.PLACE_SPECTATOR, {"space": space, "side": "oasis" if _rng.randf() < 0.5 else "mirage"})
