class_name CamelBoardVisual
extends Node3D

signal movement_step_changed(world_position: Vector3)
signal board_target_pressed(target_type: String, target_id: String)

const CAMEL_COLORS := {
	"blue": Color("3887ff"), "yellow": Color("ffd447"), "green": Color("43c86f"),
	"red": Color("ef5350"), "purple": Color("a66cff"), "white": Color("f4f0df"),
	"black": Color("24262d"),
}
const PIECE_HEIGHT := 0.68
const TARGET_ARROW := preload("res://assets/third_party/kenney/ui/target_arrow.png")

var piece_visuals: Dictionary = {}
var _tile_nodes: Array = []
var _bet_stack_roots: Dictionary = {}
var _bet_card_nodes: Dictionary = {}
var _prediction_roots: Dictionary = {}
var _prediction_cards: Dictionary = {"winner": [], "loser": []}
var _history_nodes: Array = []
var _history_slots: Array = []
var _interaction_meshes: Dictionary = {}
var _enabled_targets: Dictionary = {}
var _interaction_base_scales: Dictionary = {}
var _interaction_base_positions: Dictionary = {}
var _interaction_markers: Dictionary = {}
var _highlight_time := 0.0


func _ready() -> void:
	_build_board()
	_build_pieces()
	set_process(true)


func _process(delta: float) -> void:
	_highlight_time += delta
	var pulse := 1.0 + sin(_highlight_time * 5.5) * 0.055
	for key in _interaction_meshes:
		var mesh := _interaction_meshes[key] as MeshInstance3D
		var enabled := _enabled_targets.has(key)
		var base_scale := _interaction_base_scales.get(key, Vector3.ONE) as Vector3
		var base_position := _interaction_base_positions.get(key, mesh.position) as Vector3
		mesh.scale = base_scale * (1.13 * pulse if enabled else 1.0)
		mesh.position = base_position + (Vector3.UP * (0.14 + sin(_highlight_time * 5.5) * 0.05) if enabled else Vector3.ZERO)
		var marker := _interaction_markers.get(key) as Sprite3D
		if marker != null:
			marker.visible = enabled
			marker.position.y = 1.18 + sin(_highlight_time * 5.5) * 0.13


func sync_state(state: CamelGameState) -> void:
	if state == null:
		return
	for camel_id in piece_visuals:
		var position := state.camel_position(str(camel_id))
		var stack := state.stack_at(position)
		var level := maxi(0, stack.find(camel_id))
		(piece_visuals[camel_id] as CamelPieceVisual).position = piece_position(position, level)
		(piece_visuals[camel_id] as CamelPieceVisual).play_idle()
	_refresh_tiles(state)
	_rebuild_bet_stacks(state)
	_rebuild_predictions(state)
	_sync_dice_history(state.dice_history)


func bet_stack_position(camel_id: String) -> Vector3:
	if _bet_stack_roots.has(camel_id):
		return (_bet_stack_roots[camel_id] as Node3D).global_position
	return Vector3.ZERO


func prediction_position(bet_type: String) -> Vector3:
	if _prediction_roots.has(bet_type):
		return (_prediction_roots[bet_type] as Node3D).global_position
	return Vector3.ZERO


func dice_history_position() -> Vector3:
	return global_position + Vector3(0, 0.3, 2.35)


func show_reaction(player_id: String, text: String, state: CamelGameState) -> void:
	var player_index := 0
	for index in state.players.size():
		if str((state.players[index] as Dictionary).get("id", "")) == player_id:
			player_index = index
			break
	var camel_id := str(CamelGameState.RACE_CAMELS[player_index % CamelGameState.RACE_CAMELS.size()])
	if not piece_visuals.has(camel_id):
		return
	var bubble := Label3D.new()
	bubble.text = text.left(24)
	bubble.font_size = 54
	bubble.outline_size = 12
	bubble.modulate = Color("fff4d8")
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position = (piece_visuals[camel_id] as Node3D).position + Vector3(0, 1.65, 0)
	add_child(bubble)
	var tween := create_tween()
	tween.tween_property(bubble, "position:y", bubble.position.y + 0.35, 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(2.0)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.25)
	await tween.finished
	bubble.queue_free()


func set_interaction(target_type: String = "", valid_ids: Array = []) -> void:
	_enabled_targets.clear()
	for target_id in valid_ids:
		_enabled_targets["%s:%s" % [target_type, str(target_id)]] = true
	for key in _interaction_meshes:
		var mesh := _interaction_meshes[key] as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		var enabled := _enabled_targets.has(key)
		material.emission_enabled = enabled
		material.emission = material.albedo_color.lightened(0.18)
		material.emission_energy_multiplier = 0.62 if enabled else 0.0


func play_take_bet(data: Dictionary) -> void:
	var camel_id := str(data.get("camel", ""))
	var cards := _bet_card_nodes.get(camel_id, []) as Array
	if cards.is_empty():
		await get_tree().create_timer(0.2).timeout
		return
	var card := cards.pop_back() as Node3D
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position:y", card.position.y + 0.9, 0.18)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "global_position", Vector3(0, 5.0, 8.0), 0.36)
	tween.parallel().tween_property(card, "scale", Vector3.ZERO, 0.36)
	await tween.finished
	card.queue_free()


func play_prediction_card(data: Dictionary) -> void:
	var bet_type := str(data.get("bet", "winner"))
	var root := _prediction_roots.get(bet_type) as Node3D
	if root == null:
		return
	var card := _create_face_down_card(str(data.get("player_id", "")))
	add_child(card)
	card.global_position = Vector3(0, 4.5, 7.0)
	var target := root.global_position + Vector3(0, 0.3 + _prediction_cards[bet_type].size() * 0.1, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "global_position", target, 0.48)
	tween.parallel().tween_property(card, "rotation", Vector3(0, randf_range(-0.12, 0.12), 0), 0.48)
	await tween.finished
	_prediction_cards[bet_type].append(card)


func play_spectator_placed(data: Dictionary) -> void:
	var token := _create_spectator_token(str(data.get("player_id", "")), str(data.get("side", "oasis")))
	add_child(token)
	token.position = Vector3(0, 3.8, 7.0)
	var target := track_point(int(data.get("space", 2))) + Vector3(0, 0.34, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(token, "position", target + Vector3(0, 0.65, 0), 0.36)
	tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(token, "position", target, 0.18)
	await tween.finished
	token.queue_free()


func play_dice_history(die_id: String, value: int, from_global: Vector3) -> void:
	if _history_nodes.size() >= 5:
		return
	var die_visual := _create_history_die(die_id, value)
	add_child(die_visual)
	die_visual.global_position = from_global
	die_visual.scale = Vector3.ONE
	var target := _history_slots[_history_nodes.size()] as Vector3
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(die_visual, "position", target + Vector3(0, 0.8, 0), 0.38)
	tween.parallel().tween_property(die_visual, "scale", Vector3.ONE * 0.62, 0.38)
	tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(die_visual, "position", target, 0.18)
	await tween.finished
	_history_nodes.append(die_visual)


func clear_dice_history() -> void:
	if _history_nodes.is_empty():
		return
	var tween := create_tween().set_parallel(true)
	for node in _history_nodes:
		tween.tween_property(node, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tween.finished
	for node in _history_nodes:
		node.queue_free()
	_history_nodes.clear()


func play_move(data: Dictionary) -> void:
	var moving_ids := data.get("camels", []) as Array
	var source := int(data.get("from", 1))
	var destination := int(data.get("to", source))
	var direction := int(data.get("direction", 1))
	var destination_stack := data.get("destination_stack", moving_ids) as Array
	var base_level := maxi(0, destination_stack.size() - moving_ids.size())
	var step := source + direction
	while (direction > 0 and step <= destination) or (direction < 0 and step >= destination):
		movement_step_changed.emit(track_point(step))
		var is_last := step == destination
		var targets: Array = []
		for index in moving_ids.size():
			var level := base_level + index if is_last else index
			targets.append(piece_position(step, level))
		await _move_group(moving_ids, targets, 0.3 if is_last and base_level > 0 else 0.22, 1.0 if is_last and base_level > 0 else 0.32)
		step += direction
	for camel_id in moving_ids:
		await (piece_visuals[str(camel_id)] as CamelPieceVisual).play_land()


func play_spectator_move(data: Dictionary) -> void:
	var moving_ids := data.get("camels", []) as Array
	var destination := int(data.get("to", 1))
	var destination_stack := data.get("destination_stack", moving_ids) as Array
	var underneath := str(data.get("side", "")) == "mirage"
	var base_level := 0 if underneath else maxi(0, destination_stack.size() - moving_ids.size())
	var targets: Array = []
	for index in moving_ids.size():
		targets.append(piece_position(destination, base_level + index))
	await _move_group(moving_ids, targets, 0.42, 1.15)


func play_stack(data: Dictionary) -> void:
	var stack := data.get("bottom_to_top", []) as Array
	if stack.size() < 2:
		return
	for index in stack.size():
		var piece := piece_visuals[str(stack[index])] as CamelPieceVisual
		if index < stack.size() - 1:
			await piece.play_squashed()
		else:
			await piece.play_happy()


func play_reward(piece_id: String = "") -> void:
	if not piece_id.is_empty() and piece_visuals.has(piece_id):
		await (piece_visuals[piece_id] as CamelPieceVisual).play_happy()
	else:
		await get_tree().create_timer(0.25).timeout


func track_point(position: int) -> Vector3:
	var display_position := clampi(position, 1, CamelGameState.TRACK_LENGTH)
	# Track indices grow clockwise on the physical board. GameRules already moves
	# racing pieces with +1 indices, so the visual marker order must match it.
	var angle := TAU * float(display_position - 1) / float(CamelGameState.TRACK_LENGTH) - PI * 0.5
	var point := Vector3(cos(angle) * 6.7, 0, sin(angle) * 4.5)
	if position > CamelGameState.TRACK_LENGTH:
		point += Vector3(0.9 * (position - CamelGameState.TRACK_LENGTH), 0, 0)
	elif position < 1:
		point += Vector3(-0.9 * (1 - position), 0, 0)
	return point


func piece_position(space: int, level: int) -> Vector3:
	return track_point(space) + Vector3(0, 0.5 + float(level) * PIECE_HEIGHT, 0)


func _move_group(piece_ids: Array, targets: Array, duration: float, jump_height: float) -> void:
	var up_tween := create_tween().set_parallel(true)
	up_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for index in piece_ids.size():
		var piece := piece_visuals[str(piece_ids[index])] as CamelPieceVisual
		var target := targets[index] as Vector3
		var horizontal_mid := (piece.position + target) * 0.5
		horizontal_mid.y = maxf(piece.position.y, target.y) + jump_height
		up_tween.tween_property(piece, "position", horizontal_mid, duration * 0.5)
	await up_tween.finished
	var down_tween := create_tween().set_parallel(true)
	down_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for index in piece_ids.size():
		var piece := piece_visuals[str(piece_ids[index])] as CamelPieceVisual
		down_tween.tween_property(piece, "position", targets[index], duration * 0.5)
	await down_tween.finished


func _refresh_tiles(state: CamelGameState) -> void:
	for node in _tile_nodes:
		node.queue_free()
	_tile_nodes.clear()
	for key in state.spectator_tiles:
		var tile := state.spectator_tiles[key] as Dictionary
		var marker := _create_spectator_token(str(tile["owner_id"]), str(tile["side"]))
		marker.position = track_point(int(key)) + Vector3(0, 0.16, 0)
		add_child(marker)
		_tile_nodes.append(marker)


func _build_board() -> void:
	var table := MeshInstance3D.new()
	var table_mesh := BoxMesh.new()
	table_mesh.size = Vector3(19.0, 0.55, 13.5)
	table.mesh = table_mesh
	table.position.y = -0.5
	table.material_override = _material(Color("8f593b"))
	add_child(table)
	var center := MeshInstance3D.new()
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(17.8, 0.22, 12.3)
	center.mesh = center_mesh
	center.position.y = -0.18
	center.material_override = _material(Color("f0d18c"))
	add_child(center)
	var race_lane := MeshInstance3D.new()
	var lane_mesh := TorusMesh.new()
	lane_mesh.inner_radius = 5.75
	lane_mesh.outer_radius = 7.55
	lane_mesh.rings = 64
	lane_mesh.ring_segments = 8
	race_lane.mesh = lane_mesh
	race_lane.scale = Vector3(1.0, 0.22, 0.68)
	race_lane.position.y = -0.08
	race_lane.material_override = _material(Color("bd8357"))
	add_child(race_lane)
	# The former pyramid/glass enclosure is replaced by an open, low Dice Plaza.
	var plaza := MeshInstance3D.new()
	plaza.name = "DicePlaza"
	var plaza_mesh := CylinderMesh.new()
	plaza_mesh.top_radius = 2.8
	plaza_mesh.bottom_radius = 2.95
	plaza_mesh.height = 0.12
	plaza_mesh.radial_segments = 32
	plaza.mesh = plaza_mesh
	plaza.position = Vector3(0, 0.02, 0)
	plaza.material_override = _material(Color("f3ddb0"))
	add_child(plaza)
	for space in range(1, CamelGameState.TRACK_LENGTH + 1):
		var node := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.59
		mesh.bottom_radius = 0.63
		mesh.height = 0.2
		mesh.radial_segments = 16
		node.mesh = mesh
		node.position = track_point(space)
		node.material_override = _material(Color("fff0c8") if space % 2 == 0 else Color("f1c980"))
		add_child(node)
		_register_interaction(node, "track", str(space), Vector3(1.25, 0.45, 1.25), Vector3(0, 0.22, 0))
		var number := Label3D.new()
		number.text = str(space)
		number.font_size = 52
		number.outline_size = 6
		number.outline_modulate = Color("fff1ce")
		number.modulate = Color("6b442b")
		number.position = track_point(space) + Vector3(0, 0.17, 0)
		number.rotation_degrees.x = -90
		add_child(number)
	_build_bet_stack_anchors()
	_build_prediction_areas()
	_build_history_area()


func _build_pieces() -> void:
	for camel_id in CamelGameState.RACE_CAMELS + CamelGameState.CRAZY_CAMELS:
		var piece := CamelPieceVisual.new()
		piece.setup(str(camel_id), CAMEL_COLORS[camel_id])
		add_child(piece)
		piece_visuals[camel_id] = piece


func _build_bet_stack_anchors() -> void:
	var x_positions := [-5.2, -2.6, 0.0, 2.6, 5.2]
	for index in CamelGameState.RACE_CAMELS.size():
		var camel_id: String = str(CamelGameState.RACE_CAMELS[index])
		var root := Node3D.new()
		root.position = Vector3(x_positions[index], 0.05, -5.75)
		add_child(root)
		_bet_stack_roots[camel_id] = root
		_bet_card_nodes[camel_id] = []
		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new(); pad_mesh.size = Vector3(1.7, 0.06, 1.25)
		pad.mesh = pad_mesh; pad.position.y = 0.01; pad.material_override = _material(CAMEL_COLORS[camel_id].darkened(0.35)); root.add_child(pad)
		_register_interaction(root, "bet", camel_id, Vector3(1.75, 1.0, 1.35), Vector3(0, 0.45, 0))
		var name_label := Label3D.new()
		name_label.text = camel_id.to_upper()
		name_label.font_size = 38
		name_label.outline_size = 9
		name_label.modulate = CAMEL_COLORS[camel_id]
		name_label.position = Vector3(0, 0.25, -0.75)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(name_label)


func _rebuild_bet_stacks(state: CamelGameState) -> void:
	for camel_id in CamelGameState.RACE_CAMELS:
		for old_card in _bet_card_nodes.get(camel_id, []):
			if is_instance_valid(old_card):
				old_card.queue_free()
		var cards: Array = []
		var values := state.betting_stacks.get(camel_id, []) as Array
		var root := _bet_stack_roots[camel_id] as Node3D
		for index in values.size():
			var card := _create_bet_card(str(camel_id), int(values[index]), index)
			root.add_child(card)
			cards.append(card)
		_bet_card_nodes[camel_id] = cards
		var badge := root.get_node_or_null("Count") as Label3D
		if badge == null:
			badge = Label3D.new()
			badge.name = "Count"
			badge.font_size = 34
			badge.outline_size = 8
			badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			root.add_child(badge)
		badge.text = "%d장 · 다음 %s" % [values.size(), str(values[-1]) if not values.is_empty() else "없음"]
		badge.position = Vector3(0, 0.42 + values.size() * 0.1, 0.72)


func _create_bet_card(camel_id: String, value: int, index: int) -> Node3D:
	var card := Node3D.new()
	card.position = Vector3(index * 0.055, 0.08 + index * 0.105, index * 0.045)
	card.rotation.y = (index - 1.5) * 0.018
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.45, 0.09, 1.0)
	mesh_node.mesh = mesh
	mesh_node.material_override = _material(CAMEL_COLORS[camel_id].lightened(0.18))
	card.add_child(mesh_node)
	var value_label := Label3D.new()
	value_label.text = str(value)
	value_label.font_size = 58
	value_label.pixel_size = 0.0052
	value_label.outline_size = 8
	value_label.outline_modulate = Color("51392d")
	value_label.modulate = Color("fff6db")
	value_label.position = Vector3(0, 0.052, 0)
	value_label.rotation.x = -PI * 0.5
	card.add_child(value_label)
	return card


func _build_prediction_areas() -> void:
	_create_prediction_area("winner", Vector3(-8.0, 0.03, 0.2), Color("f4c95d"), "★ 최종 1등")
	_create_prediction_area("loser", Vector3(8.0, 0.03, 0.2), Color("8b7ab8"), "▼ 최종 꼴등")


func _create_prediction_area(bet_type: String, area_position: Vector3, color: Color, title: String) -> void:
	var root := Node3D.new()
	root.position = area_position
	add_child(root)
	_prediction_roots[bet_type] = root
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(2.2, 0.12, 3.2)
	pad.mesh = pad_mesh
	pad.material_override = _material(color.darkened(0.15))
	root.add_child(pad)
	_register_interaction(root, "prediction", bet_type, Vector3(2.35, 0.5, 3.3), Vector3(0, 0.24, 0))
	var title_label := Label3D.new()
	title_label.text = title
	title_label.font_size = 44
	title_label.outline_size = 10
	title_label.position = Vector3(0, 0.2, -1.15)
	title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(title_label)
	var hint := Label3D.new()
	hint.text = "비공개 카드"
	hint.font_size = 28
	hint.outline_size = 7
	hint.position = Vector3(0, 0.18, 1.18)
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(hint)


func _rebuild_predictions(state: CamelGameState) -> void:
	var piles := {"winner": state.final_winner_bets, "loser": state.final_loser_bets}
	for bet_type in piles:
		for old_card in _prediction_cards[bet_type]:
			if is_instance_valid(old_card):
				old_card.queue_free()
		_prediction_cards[bet_type] = []
		var root := _prediction_roots[bet_type] as Node3D
		for index in (piles[bet_type] as Array).size():
			var bet := (piles[bet_type] as Array)[index] as Dictionary
			var card := _create_face_down_card(str(bet.get("player_id", "")))
			root.add_child(card)
			card.position = Vector3(0, 0.22 + index * 0.1, 0)
			card.rotation.y = (index % 3 - 1) * 0.07
			_prediction_cards[bet_type].append(card)


func _create_face_down_card(player_id: String) -> Node3D:
	var card := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.25, 0.08, 1.7)
	mesh_node.mesh = mesh
	mesh_node.material_override = _material(Color("355c7d"))
	card.add_child(mesh_node)
	var label := Label3D.new()
	label.text = "?\n" + player_id.replace("player_", "P")
	label.font_size = 38
	label.outline_size = 8
	label.pixel_size = 0.0045
	label.position.y = 0.046
	label.rotation.x = -PI * 0.5
	card.add_child(label)
	return card


func _build_history_area() -> void:
	var tray := MeshInstance3D.new()
	var tray_mesh := BoxMesh.new()
	tray_mesh.size = Vector3(6.8, 0.12, 1.45)
	tray.mesh = tray_mesh
	tray.position = Vector3(0, 0.03, 2.45)
	tray.material_override = _material(Color("6d9f72"))
	add_child(tray)
	var label := Label3D.new()
	label.text = "이번 구간 주사위 · 5개면 정산"
	label.font_size = 36
	label.outline_size = 8
	label.position = Vector3(0, 0.25, 3.15)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	for index in 5:
		var slot_position := Vector3(-2.45 + index * 1.22, 0.38, 2.4)
		_history_slots.append(slot_position)
		var slot := MeshInstance3D.new()
		var slot_mesh := CylinderMesh.new()
		slot_mesh.top_radius = 0.46
		slot_mesh.bottom_radius = 0.46
		slot_mesh.height = 0.06
		slot.mesh = slot_mesh
		slot.position = slot_position - Vector3(0, 0.3, 0)
		slot.material_override = _material(Color("41694f"))
		add_child(slot)


func _sync_dice_history(history: Array) -> void:
	if history.size() == _history_nodes.size():
		return
	for node in _history_nodes:
		node.queue_free()
	_history_nodes.clear()
	for index in mini(history.size(), 5):
		var result := history[index] as Dictionary
		var die_visual := _create_history_die(str(result["die"]), int(result["value"]))
		add_child(die_visual)
		die_visual.position = _history_slots[index]
		die_visual.scale = Vector3.ONE * 0.62
		_history_nodes.append(die_visual)


func _create_history_die(die_id: String, value: int) -> Node3D:
	var root := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh_node.mesh = mesh
	var color: Color = CAMEL_COLORS.get(die_id, Color("9aa0aa")) as Color
	mesh_node.material_override = _material(color)
	root.add_child(mesh_node)
	var label := Label3D.new()
	label.text = str(value)
	label.font_size = 82
	label.pixel_size = 0.0048
	label.outline_size = 9
	label.outline_modulate = Color("29252a")
	label.modulate = Color("fff9e8") if die_id != "yellow" else Color("29252a")
	label.position = Vector3(0, 0.506, 0)
	label.rotation.x = -PI * 0.5
	root.add_child(label)
	return root


func _create_spectator_token(player_id: String, side: String) -> Node3D:
	var root := Node3D.new()
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new(); mesh.top_radius = 0.46; mesh.bottom_radius = 0.46; mesh.height = 0.1
	marker.mesh = mesh; marker.material_override = _material(Color("43d6d1") if side == "oasis" else Color("e9749c")); root.add_child(marker)
	var label := Label3D.new(); label.text = "%s\n%s" % ["+1" if side == "oasis" else "-1", player_id.replace("player_", "P").replace("cpu_", "CPU")]
	label.font_size = 34; label.pixel_size = 0.0048; label.outline_size = 7; label.position.y = 0.056; label.rotation.x = -PI * 0.5; root.add_child(label)
	return root


func _build_scenery() -> void:
	for position in [Vector3(-8.4, 0, -5.2), Vector3(8.4, 0, -5.0), Vector3(-8.5, 0, 5.2), Vector3(8.5, 0, 5.0)]:
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.15
		trunk_mesh.bottom_radius = 0.22
		trunk_mesh.height = 1.3
		trunk.mesh = trunk_mesh
		trunk.position = position + Vector3(0, 0.65, 0)
		trunk.material_override = _material(Color("855b3d"))
		add_child(trunk)
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 0.72
		crown_mesh.height = 1.35
		crown.mesh = crown_mesh
		crown.position = position + Vector3(0, 1.55, 0)
		crown.material_override = _material(Color("67a65f"))
		add_child(crown)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func _register_interaction(parent: Node3D, target_type: String, target_id: String, hit_size: Vector3, local_position: Vector3) -> void:
	var key := "%s:%s" % [target_type, target_id]
	var visual: MeshInstance3D = parent if parent is MeshInstance3D else null
	if visual == null:
		for child in parent.get_children():
			if child is MeshInstance3D:
				visual = child as MeshInstance3D
				break
	if visual != null:
		var source := visual.material_override as StandardMaterial3D
		if source != null:
			visual.material_override = source.duplicate()
		_interaction_meshes[key] = visual
		_interaction_base_scales[key] = visual.scale
		_interaction_base_positions[key] = visual.position
		var marker := Sprite3D.new()
		marker.texture = TARGET_ARROW
		marker.pixel_size = 0.045
		marker.modulate = Color("fff1a1")
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.visible = false
		parent.add_child(marker)
		_interaction_markers[key] = marker
	var area := Area3D.new()
	area.input_ray_pickable = true
	area.collision_layer = 4
	area.collision_mask = 0
	area.position = local_position
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = hit_size
	shape_node.shape = shape
	area.add_child(shape_node)
	area.input_event.connect(func(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
		if not _enabled_targets.has(key):
			return
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			board_target_pressed.emit(target_type, target_id)
			get_viewport().set_input_as_handled()
	)
	parent.add_child(area)
