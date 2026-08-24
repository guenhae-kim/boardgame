class_name CamelAction
extends RefCounted

const TAKE_LEG_BET := "TAKE_LEG_BET"
const PLACE_SPECTATOR := "PLACE_SPECTATOR"
const ROLL_DIE := "ROLL_DIE"
const FINAL_BET := "FINAL_BET"
const PARTNER := "PARTNER"

var type: String
var data: Dictionary

func _init(action_type: String = "", action_data: Dictionary = {}) -> void:
	type = action_type
	data = action_data.duplicate(true)

func to_dict() -> Dictionary:
	return {"type": type, "data": data.duplicate(true)}

static func from_dict(value: Dictionary) -> CamelAction:
	return CamelAction.new(str(value.get("type", "")), value.get("data", {}) as Dictionary)
