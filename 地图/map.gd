extends Node2D
class_name MAP
signal event_section_selected(request_id: int, section: MapSection)
signal section_choice_selected(owner: StringName, request_id: int, section: MapSection)
var grid_map: Dictionary[Vector3i, MapSection] = {}
var hud:HUD
var _event_section_request_id: int = -1
var _event_section_options: Array[MapSection] = []
var _section_choice_owner: StringName = &""
func _ready():
	# 1. 注册所有格子
	# 假设所有的 MapSection 都放在一个叫 "Sections" 的节点下
	TurnManager.phase_changed.connect(_on_phase_changed)
	hud = get_tree().get_first_node_in_group("HUD")
	for city in $MapSprite.get_children():
		if city is 市基类:
			for section: MapSection in city.get_children():
				grid_map[section.location_index] = section
				grid_map[Vector3i(0, 0, section.logical_index)] = section
				# 监听格子的点击信号
				section.section_clicked.connect(_on_section_clicked)
				#hud._update_ui_for_action()
			
	# 2. 监听阶段变化
	

# --- 核心调度：阶段响应 ---
func _on_phase_changed(new_phase: TurnManager.TurnPhase):
	match new_phase:
		TurnManager.TurnPhase.MOVING:
			_show_reachable_areas()
		TurnManager.TurnPhase.ACTION:
			# 移动结束，关闭所有高亮
			_clear_all_highlights()
	hud._update_button_states(new_phase)

# --- 显示可达区域 ---
func _show_reachable_areas() -> void:
	_clear_all_highlights()
	if TurnManager.is_movement_locked() or TurnManager.players.is_empty():
		return
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	var start_coord: Vector3i = current_player.now_pos
	var max_steps: int = current_player.maxMove
	var available_energy: int = current_player.current_energy
	available_energy += FoodManager.get_preview_movement_discount(current_player)
	if not current_player.武术拳法已生效:
		for card:非遗牌 in current_player.非遗牌手牌:
			if card.category == 非遗牌.CardCategory.武术拳法:
				available_energy += 1
				break

	var states: Array[Dictionary] = _search_path_states(start_coord, max_steps, available_energy, current_player)
	for state: Dictionary in states:
		var coord: Vector3i = state["position"]
		if coord == start_coord or not _is_state_active(state, states):
			continue
		grid_map[coord].is_reachable = true
	# 免费移动阶段可选择骰子步数内的任意合法格；畅行无阻额外开放骰子步数内的特殊地形终点。
	if EventManager.has_free_move_this_phase(current_player) or EventManager.can_ignore_special_terrain_this_phase(current_player):
		var step_queue: Array[Vector3i] = [start_coord]
		var step_distance: Dictionary[Vector3i, int] = {start_coord: 0}
		while not step_queue.is_empty():
			var step_pos: Vector3i = step_queue.pop_front()
			for mov: Vector3i in 常量.MOVE:
				var candidate: Vector3i = step_pos + mov
				if not grid_map.has(candidate) or step_distance.has(candidate):
					continue
				var distance: int = step_distance[step_pos] + 1
				if distance > max_steps:
					continue
				step_distance[candidate] = distance
				step_queue.append(candidate)
				var candidate_section: MapSection = grid_map[candidate]
				var free_target := EventManager.has_free_move_this_phase(current_player)
				var special_target := EventManager.can_ignore_special_terrain_this_phase(current_player) and candidate_section.landform != MapSection.LandForm.平原
				if (free_target or special_target) and not candidate_section.is_occupied and not candidate_section.is_reached:
					candidate_section.is_reachable = true
	if EventManager.is_scenery_banned(current_player):
		for section: MapSection in grid_map.values():
			if section.type == MapSection.SectionType.风景:
				section.is_reachable = false

func _clear_all_highlights() -> void:
	for section:MapSection in grid_map.values():
		section.is_reachable = false


## 玩家占用的唯一写入口。MapSection 内部按玩家实例计数，因此事件允许的
## 多人同格不会在其中一人离开时误把整格标记为空。
func occupy_player_section(player: PlayerClass, section: MapSection) -> void:
	if player == null or section == null:
		return
	section.add_occupant(player)


func vacate_player_section(player: PlayerClass, section: MapSection) -> void:
	if player == null or section == null:
		return
	section.remove_occupant(player)
	# 兼容旧场景/测试只写 is_occupied=true 的占用标记。setter 仅清除
	# legacy 标志，不会删除同格其他玩家的正式登记。
	section.is_occupied = false


func transfer_player_occupancy(player: PlayerClass, from_section: MapSection, to_section: MapSection) -> void:
	if player == null or to_section == null:
		return
	if from_section != to_section:
		vacate_player_section(player, from_section)
	occupy_player_section(player, to_section)

func begin_event_section_choice(request_id: int, sections: Array[MapSection]) -> void:
	begin_section_choice(&"event", request_id, sections)

func begin_section_choice(owner: StringName, request_id: int, sections: Array[MapSection]) -> void:
	_clear_all_highlights()
	_section_choice_owner = owner
	_event_section_request_id = request_id
	_event_section_options.clear()
	for section: MapSection in sections:
		if section == null or _event_section_options.has(section):
			continue
		_event_section_options.append(section)
		section.is_reachable = true

func end_event_section_choice(request_id: int = -1) -> void:
	end_section_choice(&"event", request_id)

func end_section_choice(owner: StringName = &"", request_id: int = -1) -> void:
	if not owner.is_empty() and owner != _section_choice_owner:
		return
	if request_id >= 0 and request_id != _event_section_request_id:
		return
	_section_choice_owner = &""
	_event_section_request_id = -1
	_event_section_options.clear()
	_clear_all_highlights()

func is_event_section_choice_active() -> bool:
	return _section_choice_owner == &"event" and is_section_choice_active()

func is_section_choice_active(owner: StringName = &"") -> bool:
	if not owner.is_empty() and owner != _section_choice_owner:
		return false
	return _event_section_request_id >= 0 and not _event_section_options.is_empty()

func _search_path_states(
	start_coord: Vector3i,
	max_steps: int,
	max_energy: int,
	player: PlayerClass = null
) -> Array[Dictionary]:
	var states: Array[Dictionary] = [{
		"position": start_coord,
		"steps": 0,
		"cost": 0,
		"parent": -1,
	}]
	var frontier: Array[int] = [0]
	var labels: Dictionary[Vector3i, Array] = {start_coord: [Vector2i(0, 0)]}
	while not frontier.is_empty():
		var state_index: int = frontier.pop_front()
		var state: Dictionary = states[state_index]
		var position: Vector3i = state["position"]
		var label := Vector2i(int(state["steps"]), int(state["cost"]))
		if not labels.get(position, []).has(label) or label.x >= max_steps:
			continue
		for movement: Vector3i in 常量.MOVE:
			var next_position: Vector3i = position + movement
			if not grid_map.has(next_position):
				continue
			var next_section: MapSection = grid_map[next_position]
			if next_section.is_reached or next_section.is_occupied:
				continue
			var entry_cost := ProfessionManager.adjust_section_movement_cost(player, next_section, next_section.cost)
			var next_label := Vector2i(label.x + 1, label.y + entry_cost)
			if next_label.x > max_steps or next_label.y > max_energy:
				continue
			var existing_labels: Array = labels.get(next_position, [])
			var dominated := false
			for existing: Vector2i in existing_labels:
				if existing.x <= next_label.x and existing.y <= next_label.y:
					dominated = true
					break
			if dominated:
				continue
			var retained_labels: Array = []
			for existing: Vector2i in existing_labels:
				if not (next_label.x <= existing.x and next_label.y <= existing.y):
					retained_labels.append(existing)
			retained_labels.append(next_label)
			labels[next_position] = retained_labels
			states.append({
				"position": next_position,
				"steps": next_label.x,
				"cost": next_label.y,
				"parent": state_index,
			})
			frontier.append(states.size() - 1)
	for state: Dictionary in states:
		state["active_labels"] = labels
	return states

func _is_state_active(state: Dictionary, _states: Array[Dictionary]) -> bool:
	var labels: Dictionary = state.get("active_labels", {})
	var position: Vector3i = state["position"]
	return labels.get(position, []).has(Vector2i(int(state["steps"]), int(state["cost"])))

func _best_path(
	start_coord: Vector3i,
	target_coord: Vector3i,
	max_steps: int,
	max_energy: int,
	player: PlayerClass = null
) -> Dictionary:
	var states := _search_path_states(start_coord, max_steps, max_energy, player)
	var best_index := -1
	for index: int in states.size():
		var state: Dictionary = states[index]
		if state["position"] != target_coord or not _is_state_active(state, states):
			continue
		if best_index < 0:
			best_index = index
			continue
		var best: Dictionary = states[best_index]
		if int(state["cost"]) < int(best["cost"]) or (int(state["cost"]) == int(best["cost"]) and int(state["steps"]) < int(best["steps"])):
			best_index = index
	if best_index < 0:
		return {}
	var coordinates: Array[Vector3i] = []
	var cursor := best_index
	while cursor >= 0 and states[cursor]["position"] != start_coord:
		coordinates.append(states[cursor]["position"])
		cursor = int(states[cursor]["parent"])
	coordinates.reverse()
	return {
		"coordinates": coordinates,
		"cost": int(states[best_index]["cost"]),
		"steps": int(states[best_index]["steps"]),
	}

# --- 玩家点击处理 ---
func _on_section_clicked(target_section: MapSection) -> String:
	if is_section_choice_active():
		if _event_section_options.has(target_section):
			section_choice_selected.emit(_section_choice_owner, _event_section_request_id, target_section)
			if _section_choice_owner == &"event":
				event_section_selected.emit(_event_section_request_id, target_section)
			return "event choice"
		return "not available"
	if TurnManager.now_phase != TurnManager.TurnPhase.MOVING or TurnManager.is_movement_locked():
		return "not available"
		
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	
	var start_coord: Vector3i = current_player.now_pos
	var target_coord: Vector3i = target_section.location_index
	
	if target_coord == start_coord:
		return "not necessary"
		
	var max_energy = current_player.current_energy
	max_energy += FoodManager.get_preview_movement_discount(current_player)
	if EventManager.has_free_move_this_phase(current_player) or (EventManager.can_ignore_special_terrain_this_phase(current_player) and target_section.landform != MapSection.LandForm.平原):
		max_energy = 1 << 30
	if not current_player.武术拳法已生效:
		for card:非遗牌 in current_player.非遗牌手牌:
			if card.category == 非遗牌.CardCategory.武术拳法:
				max_energy += 1
				break
	
	var path_result: Dictionary = _best_path(start_coord, target_coord, current_player.maxMove, max_energy, current_player)
	if path_result.is_empty():
		print("无法到达该目标！")
		return "error"

	var path_pixels: Array[Vector2] = []
	for coordinate: Vector3i in path_result["coordinates"]:
		grid_map[coordinate].is_reached = true
		grid_map[coordinate].is_reachable = false
		path_pixels.append(grid_map[coordinate].global_position)
	var moved: bool = await current_player.move_along_path(path_pixels, int(path_result["cost"]), target_coord)
	return "success" if moved else "not available"
	
