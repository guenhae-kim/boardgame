class_name CamelGameState
extends RefCounted

const RACE_CAMELS := ["blue", "yellow", "green", "red", "purple"]
const CRAZY_CAMELS := ["white", "black"]
const TRACK_LENGTH := 16

var players: Array = []
var camels: Dictionary = {}
var stacks: Dictionary = {}
var spectator_tiles: Dictionary = {}
var betting_stacks: Dictionary = {}
var remaining_dice: Array = []
var dice_history: Array = []
var pyramid_tickets_remaining := 5
var final_winner_bets: Array = []
var final_loser_bets: Array = []

var current_player_index := 0
var starting_player_index := 0
var last_roller_index := -1
var leg_number := 1
var turn_number := 1
var phase := "PLAYING"
var game_end_reason := ""
var winners: Array = []
var rng_state := 0

func initialize(player_names: Array, seed_value: int) -> void:
	players.clear()
	for index in player_names.size():
		players.append({
			"id": "player_%d" % (index + 1),
			"name": str(player_names[index]).strip_edges().left(20),
			"character_id": index,
			"money": 3,
			"leg_tickets": [],
			"pyramid_tickets": 0,
			"final_cards": RACE_CAMELS.duplicate(),
			"partner_with": "",
			"partnership_available": true,
		})
	camels.clear()
	for color in RACE_CAMELS:
		camels[color] = {"color": color, "kind": "race", "position": 0}
	for color in CRAZY_CAMELS:
		camels[color] = {"color": color, "kind": "crazy", "position": 0}
	stacks.clear()
	spectator_tiles.clear()
	reset_leg_components()
	final_winner_bets.clear()
	final_loser_bets.clear()
	current_player_index = 0
	starting_player_index = 0
	last_roller_index = -1
	leg_number = 1
	turn_number = 1
	phase = "PLAYING"
	game_end_reason = ""
	winners.clear()
	rng_state = seed_value

func reset_leg_components() -> void:
	betting_stacks.clear()
	for color in RACE_CAMELS:
		# The last element is the top ticket: 5, then 3, then 2, then 2.
		betting_stacks[color] = [2, 2, 3, 5]
	remaining_dice = RACE_CAMELS.duplicate()
	remaining_dice.append("gray")
	dice_history.clear()
	pyramid_tickets_remaining = 5

func current_player() -> Dictionary:
	return players[current_player_index]

func player_by_id(player_id: String) -> Dictionary:
	for player in players:
		if str(player["id"]) == player_id:
			return player
	return {}

func player_index(player_id: String) -> int:
	for index in players.size():
		if str(players[index]["id"]) == player_id:
			return index
	return -1

func stack_at(position: int) -> Array:
	return stacks.get(str(position), []) as Array

func set_stack(position: int, camel_ids: Array) -> void:
	var key := str(position)
	if camel_ids.is_empty():
		stacks.erase(key)
		return
	stacks[key] = camel_ids.duplicate()
	for camel_id in camel_ids:
		(camels[str(camel_id)] as Dictionary)["position"] = position

func camel_position(camel_id: String) -> int:
	return int((camels.get(camel_id, {}) as Dictionary).get("position", 0))

func to_dict() -> Dictionary:
	return {
		"players": players.duplicate(true),
		"camels": camels.duplicate(true),
		"stacks": stacks.duplicate(true),
		"spectator_tiles": spectator_tiles.duplicate(true),
		"betting_stacks": betting_stacks.duplicate(true),
		"remaining_dice": remaining_dice.duplicate(),
		"dice_history": dice_history.duplicate(true),
		"pyramid_tickets_remaining": pyramid_tickets_remaining,
		"final_winner_bets": final_winner_bets.duplicate(true),
		"final_loser_bets": final_loser_bets.duplicate(true),
		"current_player_index": current_player_index,
		"starting_player_index": starting_player_index,
		"last_roller_index": last_roller_index,
		"leg_number": leg_number,
		"turn_number": turn_number,
		"phase": phase,
		"game_end_reason": game_end_reason,
		"winners": winners.duplicate(),
		"rng_state": rng_state,
	}

func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")

static func from_dict(value: Dictionary) -> CamelGameState:
	var result := CamelGameState.new()
	result.players = (value.get("players", []) as Array).duplicate(true)
	result.camels = (value.get("camels", {}) as Dictionary).duplicate(true)
	result.stacks = (value.get("stacks", {}) as Dictionary).duplicate(true)
	result.spectator_tiles = (value.get("spectator_tiles", {}) as Dictionary).duplicate(true)
	result.betting_stacks = (value.get("betting_stacks", {}) as Dictionary).duplicate(true)
	result.remaining_dice = (value.get("remaining_dice", []) as Array).duplicate()
	result.dice_history = (value.get("dice_history", []) as Array).duplicate(true)
	result.pyramid_tickets_remaining = int(value.get("pyramid_tickets_remaining", 5))
	result.final_winner_bets = (value.get("final_winner_bets", []) as Array).duplicate(true)
	result.final_loser_bets = (value.get("final_loser_bets", []) as Array).duplicate(true)
	result.current_player_index = int(value.get("current_player_index", 0))
	result.starting_player_index = int(value.get("starting_player_index", 0))
	result.last_roller_index = int(value.get("last_roller_index", -1))
	result.leg_number = int(value.get("leg_number", 1))
	result.turn_number = int(value.get("turn_number", 1))
	result.phase = str(value.get("phase", "PLAYING"))
	result.game_end_reason = str(value.get("game_end_reason", ""))
	result.winners = (value.get("winners", []) as Array).duplicate()
	result.rng_state = int(value.get("rng_state", 0))
	return result
