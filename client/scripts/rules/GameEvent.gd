class_name CamelEvent
extends RefCounted

const GAME_STARTED := "GAME_STARTED"
const TURN_STARTED := "TURN_STARTED"
const TURN_ENDED := "TURN_ENDED"
const LEG_BET_TAKEN := "LEG_BET_TAKEN"
const SPECTATOR_PLACED := "SPECTATOR_PLACED"
const PYRAMID_TICKET_TAKEN := "PYRAMID_TICKET_TAKEN"
const DIE_ROLLED := "DIE_ROLLED"
const CAMEL_MOVED := "CAMEL_MOVED"
const CAMELS_STACKED := "CAMELS_STACKED"
const SPECTATOR_TRIGGERED := "SPECTATOR_TRIGGERED"
const MONEY_CHANGED := "MONEY_CHANGED"
const FINAL_BET_PLACED := "FINAL_BET_PLACED"
const PARTNERSHIP_CREATED := "PARTNERSHIP_CREATED"
const LEG_ENDED := "LEG_ENDED"
const LEG_SCORING := "LEG_SCORING"
const GAME_END_TRIGGERED := "GAME_END_TRIGGERED"
const FINAL_BET_SCORING := "FINAL_BET_SCORING"
const GAME_ENDED := "GAME_ENDED"
const DEBUG_STATE_CHANGED := "DEBUG_STATE_CHANGED"

var type: String
var data: Dictionary

func _init(event_type: String = "", event_data: Dictionary = {}) -> void:
	type = event_type
	data = event_data.duplicate(true)

func to_dict() -> Dictionary:
	return {"type": type, "data": data.duplicate(true)}
