class_name CamelSoundManager
extends Node

const CUE_PATHS := {
	"ui": ["res://assets/audio/sfx/ui/ui_tap_01.ogg", "res://assets/audio/sfx/ui/ui_tap_02.ogg"],
	"card_select": ["res://assets/audio/sfx/cards/card_select_01.ogg", "res://assets/audio/sfx/cards/card_select_02.ogg"],
	"card_fly": ["res://assets/audio/sfx/cards/card_slide_01.ogg", "res://assets/audio/sfx/cards/card_slide_02.ogg"],
	"card_land": ["res://assets/audio/sfx/cards/card_place_01.ogg", "res://assets/audio/sfx/cards/card_place_02.ogg", "res://assets/audio/sfx/cards/card_place_03.ogg", "res://assets/audio/sfx/cards/card_place_04.ogg"],
	"dice_throw": ["res://assets/audio/sfx/dice/dice_shake_01.ogg", "res://assets/audio/sfx/dice/dice_shake_02.ogg"],
	"collision_small": ["res://assets/audio/sfx/dice/dice_hit_soft_01.ogg", "res://assets/audio/sfx/dice/dice_hit_soft_02.ogg"],
	"collision_medium": ["res://assets/audio/sfx/dice/dice_hit_medium_01.ogg", "res://assets/audio/sfx/dice/dice_hit_medium_02.ogg"],
	"collision_big": ["res://assets/audio/sfx/dice/dice_hit_hard_01.ogg", "res://assets/audio/sfx/dice/dice_hit_hard_02.ogg"],
	"dice_final": ["res://assets/audio/sfx/dice/dice_final_01.ogg", "res://assets/audio/sfx/dice/dice_final_02.ogg"],
	"walk": ["res://assets/audio/sfx/pieces/piece_hop_01.ogg", "res://assets/audio/sfx/pieces/piece_hop_02.ogg", "res://assets/audio/sfx/pieces/piece_hop_03.ogg"],
	"jump": ["res://assets/audio/sfx/pieces/piece_hop_01.ogg", "res://assets/audio/sfx/pieces/piece_hop_02.ogg"],
	"land": ["res://assets/audio/sfx/pieces/piece_land_01.ogg", "res://assets/audio/sfx/pieces/piece_land_02.ogg"],
	"stack": ["res://assets/audio/sfx/pieces/piece_stack_01.ogg", "res://assets/audio/sfx/pieces/piece_stack_02.ogg"],
	"squash": ["res://assets/audio/sfx/pieces/piece_stack_01.ogg", "res://assets/audio/sfx/pieces/piece_stack_02.ogg"],
	"coin_gain": ["res://assets/audio/sfx/coins/coin_gain_01.ogg", "res://assets/audio/sfx/coins/coin_gain_02.ogg"],
	"coin_loss": ["res://assets/audio/sfx/coins/coin_spend_01.ogg", "res://assets/audio/sfx/coins/coin_spend_02.ogg"],
	# Secondary notifications intentionally reuse quiet physical Foley. There are
	# no generated oscillators or electronic placeholder tones.
	"turn": ["res://assets/audio/sfx/ui/ui_tap_01.ogg", "res://assets/audio/sfx/coins/coin_gain_01.ogg"],
	"timer_warning": ["res://assets/audio/sfx/ui/ui_tap_02.ogg"],
	"round": ["res://assets/audio/sfx/coins/coin_gain_01.ogg", "res://assets/audio/sfx/coins/coin_gain_02.ogg"],
	"game": ["res://assets/audio/sfx/coins/coin_gain_01.ogg", "res://assets/audio/sfx/coins/coin_gain_02.ogg"],
}

const BASE_VOLUME_DB := {
	"ui": -15.0, "card_select": -13.0, "card_fly": -14.0, "card_land": -11.0,
	"dice_throw": -12.0, "collision_small": -18.0, "collision_medium": -14.0,
	"collision_big": -11.0, "dice_final": -10.0, "walk": -16.0, "jump": -15.0,
	"land": -12.0, "stack": -10.0, "squash": -11.0, "coin_gain": -13.0,
	"coin_loss": -15.0, "turn": -14.0, "timer_warning": -17.0,
	"round": -12.0, "game": -11.0,
}

const UI_CUES := {"ui": true, "card_select": true, "timer_warning": true}

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_variation: Dictionary = {}
var _cursor := 0
var _last_collision_msec := 0
var _play_count := 0


func _ready() -> void:
	for unused in 12:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	for cue in CUE_PATHS:
		var variations: Array[AudioStream] = []
		for path in CUE_PATHS[cue]:
			var stream := load(str(path)) as AudioStream
			if stream != null:
				variations.append(stream)
			else:
				push_error("SFX import failed: %s" % path)
		_streams[cue] = variations


func play(cue: String, strength: float = 1.0) -> void:
	var variations := _streams.get(cue, []) as Array
	if variations.is_empty() or _players.is_empty():
		return
	var index := randi_range(0, variations.size() - 1)
	if variations.size() > 1 and index == int(_last_variation.get(cue, -1)):
		index = (index + 1) % variations.size()
	_last_variation[cue] = index
	var player := _players[_cursor] as AudioStreamPlayer
	_cursor = (_cursor + 1) % _players.size()
	player.stream = variations[index] as AudioStream
	player.bus = "UI" if UI_CUES.has(cue) else "SFX"
	player.pitch_scale = randf_range(0.97, 1.03)
	var strength_db := linear_to_db(clampf(strength, 0.12, 1.0))
	player.volume_db = float(BASE_VOLUME_DB.get(cue, -13.0)) + strength_db + randf_range(-1.0, 1.0)
	player.play()
	_play_count += 1


func play_collision(strength: float) -> void:
	# Ignore tiny resting contacts and rate-limit rapid physics callbacks so a
	# tumbling die sounds like distinct hits, not a machine gun.
	if strength < 1.45:
		return
	var now := Time.get_ticks_msec()
	if now - _last_collision_msec < 72:
		return
	_last_collision_msec = now
	if strength < 3.2:
		play("collision_small", remap(clampf(strength, 1.45, 3.2), 1.45, 3.2, 0.28, 0.62))
	elif strength < 6.0:
		play("collision_medium", remap(strength, 3.2, 6.0, 0.48, 0.82))
	else:
		play("collision_big", clampf(strength / 9.0, 0.65, 1.0))


func variation_count(cue: String) -> int:
	return (_streams.get(cue, []) as Array).size()


func loaded_cues() -> Array:
	return _streams.keys()


func play_count() -> int:
	return _play_count
