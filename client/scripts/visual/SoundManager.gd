class_name CamelSoundManager
extends Node

const SAMPLE_RATE := 22050
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _cursor := 0

func _ready() -> void:
	for unused in 8:
		var player := AudioStreamPlayer.new(); add_child(player); _players.append(player)
	for cue in ["ui", "card_select", "card_fly", "card_land", "dice_throw", "collision_small", "collision_medium", "collision_big", "walk", "jump", "land", "stack", "squash", "coin_gain", "coin_loss", "turn", "timer_warning", "round", "game"]:
		_streams[cue] = _synthesize(cue)

func play(cue: String, strength: float = 1.0) -> void:
	if not _streams.has(cue): return
	var player := _players[_cursor] as AudioStreamPlayer; _cursor = (_cursor + 1) % _players.size()
	player.stream = _streams[cue]
	player.pitch_scale = randf_range(0.94, 1.07)
	player.volume_db = linear_to_db(clampf(strength, 0.08, 1.0)) - 7.0
	player.play()

func play_collision(strength: float) -> void:
	if strength < 2.2: play("collision_small", clampf(strength / 3.0, 0.25, 0.7))
	elif strength < 5.5: play("collision_medium", clampf(strength / 6.0, 0.4, 0.85))
	else: play("collision_big", clampf(strength / 9.0, 0.55, 1.0))

func _synthesize(cue: String) -> AudioStreamWAV:
	var settings: Array = ({
		"ui": [660.0, 0.045, 0.18], "card_select": [520.0, 0.09, 0.28], "card_fly": [880.0, 0.13, 0.18], "card_land": [330.0, 0.08, 0.35],
		"dice_throw": [240.0, 0.12, 0.65], "collision_small": [920.0, 0.035, 0.48], "collision_medium": [520.0, 0.055, 0.65], "collision_big": [180.0, 0.09, 0.82],
		"walk": [380.0, 0.04, 0.25], "jump": [740.0, 0.11, 0.34], "land": [260.0, 0.07, 0.52], "stack": [460.0, 0.1, 0.4], "squash": [150.0, 0.13, 0.55],
		"coin_gain": [1040.0, 0.12, 0.24], "coin_loss": [210.0, 0.13, 0.4], "turn": [780.0, 0.16, 0.25], "timer_warning": [560.0, 0.055, 0.18], "round": [620.0, 0.28, 0.28], "game": [880.0, 0.42, 0.3],
	} as Dictionary)[cue] as Array
	var frequency := float(settings[0]); var duration := float(settings[1]); var noise := float(settings[2])
	var count := int(SAMPLE_RATE * duration); var bytes := PackedByteArray(); bytes.resize(count * 2)
	for index in count:
		var time := float(index) / SAMPLE_RATE; var envelope := pow(1.0 - float(index) / count, 2.2)
		var chirp := frequency * (1.0 + 0.2 * (1.0 - float(index) / count))
		var sample := sin(TAU * chirp * time) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		bytes.encode_s16(index * 2, int(clampf(sample * envelope, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = SAMPLE_RATE; stream.stereo = false; stream.data = bytes
	return stream
