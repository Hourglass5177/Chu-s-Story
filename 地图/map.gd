extends Node2D
class_name MAP
var grid_map: Dictionary[Vector3i, MapSection] = {}
var hud:HUD
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
func _show_reachable_areas():
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	var start_coord = current_player.now_pos
	var max_steps = current_player.maxMove
	var available_energy = current_player.current_energy 
	if not current_player.武术拳法已生效:
		for card:非遗牌 in current_player.非遗牌手牌:
			if card.category == 非遗牌.CardCategory.武术拳法:
				available_energy += 1
				break
	
	var que: Array[Vector3i] = []
	var que_status: Array[Vector2i] = []
	var vis: Dictionary[int, bool] = {}
	
	que.push_back(start_coord)
	que_status.push_back(Vector2i(0, 0))
	
	if grid_map.has(start_coord):
		vis[grid_map[start_coord].logical_index] = true
		grid_map[start_coord].is_reachable = true
	
	while not que.is_empty():
		var now_pos = que.pop_front()
		var now_status = que_status.pop_front()
		for mov: Vector3i in 常量.MOVE:
			var new_pos: Vector3i = now_pos + mov
			if new_pos in grid_map and now_status.x < max_steps:
				var next_section = grid_map[new_pos]
				var new_cost = now_status.y + next_section.cost
				if new_cost <= available_energy and not vis.has(next_section.logical_index) and not next_section.is_reached and not grid_map[new_pos].is_occupied:
					next_section.is_reachable = true 
					que.push_back(new_pos)
					que_status.push_back(Vector2i(now_status.x + 1, new_cost))
					vis[next_section.logical_index] = true

func _clear_all_highlights():
	for section:MapSection in grid_map.values():
		section.is_reachable = false

# --- 玩家点击处理 ---
func _on_section_clicked(target_section: MapSection) -> String:
	if TurnManager.now_phase != TurnManager.TurnPhase.MOVING:
		return "not available"
		
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	
	var start_coord: Vector3i = current_player.now_pos
	var target_coord: Vector3i = target_section.location_index
	
	if target_coord == start_coord:
		return "not necessary"
		
	var max_energy = current_player.current_energy
	if not current_player.武术拳法已生效:
		for card:非遗牌 in current_player.非遗牌手牌:
			if card.category == 非遗牌.CardCategory.武术拳法:
				max_energy += 1
				break
	
	# 【核心数据结构】
	var que: Array[Vector3i] = []
	var came_from: Dictionary = {}   # 记录路径：{ 当前节点坐标 : 来源节点坐标 }
	var cost_so_far: Dictionary = {} # 记录消耗：{ 当前节点坐标 : 从起点到这里的总消耗 }
	
	# 初始化起点
	que.push_back(start_coord)
	came_from[start_coord] = start_coord
	cost_so_far[start_coord] = 0
	grid_map[start_coord].is_reached = true
	grid_map[start_coord].is_reachable = false
	var found_target: bool = false
	
	# --- 第一步：BFS 寻路与构建溯源树 ---
	while not que.is_empty():
		var now_pos = que.pop_front()
		# 如果找到了目标，直接停止扩散！
		if now_pos == target_coord:
			found_target = true
			break 	
		for mov: Vector3i in 常量.MOVE:
			var new_pos: Vector3i = now_pos + mov
			
			if new_pos in grid_map:
				# 计算走到新格子的累计精力消耗
				var new_cost = cost_so_far[now_pos] + grid_map[new_pos].cost
				
				# 如果这个格子没去过，或者找到了一条更省精力的路，且未超过玩家最大精力上限
				if (not cost_so_far.has(new_pos) or new_cost < cost_so_far[new_pos]) and new_cost <= max_energy and not grid_map[new_pos].is_reached and not grid_map[new_pos].is_occupied:
					cost_so_far[new_pos] = new_cost
					came_from[new_pos] = now_pos # 【关键】记录：我是从 now_pos 走到 new_pos 的
					que.push_back(new_pos)

	# --- 第二步：回溯生成具体路径 ---
	if not found_target:
		print("无法到达该目标！")
		return "error"
		
	var path_pixels: Array[Vector2] = []
	var current_backtrack = target_coord
	var total_cost_used = cost_so_far[target_coord]
	
	# 从终点一步步往回倒推，直到退回起点
	while current_backtrack != start_coord:
		# 注意：Tween 动画需要的是物理世界像素坐标 (global_position)，而不是逻辑坐标的差值
		grid_map[current_backtrack].is_reached = true
		grid_map[current_backtrack].is_reachable = false
		path_pixels.append(grid_map[current_backtrack].global_position)
		current_backtrack = came_from[current_backtrack]
		
	# 因为是从终点倒推的，所以路径是反的，最后必须翻转一下！
	path_pixels.reverse()
	
	# --- 第三步：通知 Player 开始移动 ---
	# 传递真正的像素路线数组、准确的总消耗、以及目标的逻辑坐标
	current_player.move_along_path(path_pixels, total_cost_used, target_coord)
	return "success"
	
