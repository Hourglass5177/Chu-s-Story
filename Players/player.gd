extends AnimatedSprite2D
class_name PlayerClass
signal roll_dice(result:int, player:PlayerClass)
var hud:HUD
var map:MAP
enum PlayerCharacter{
	美食博主,
	魔术博主,
	探险博主,
	商业博主,
	旅行博主,
	生活博主
}
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 1. 监听回合开始信号
	TurnManager.turn_start.connect(_on_turn_manager_turn_start)
	# 2. 监听阶段改变信号 (比如判断什么时候该我走)
	TurnManager.phase_changed.connect(_on_phase_changed)
	hud = get_tree().get_first_node_in_group("HUD") as HUD
	await get_tree().process_frame
	map = get_tree().get_first_node_in_group("MAP") as MAP
	if get_parent() != map:
		self.reparent(map)
		print(player_name, "已挂载到地图")
	now_pos = start_coord
	position = map.to_local(map.grid_map[start_coord].global_position) 
	map.grid_map[start_coord].is_occupied = true
	_init_character()
	if material:
		material = material.duplicate()
		material.set_shader_parameter("line_thickness", 0.0)
	score_label.text = str(current_score)

# 玩家的基础属性 [cite: 1]
@export var player_name: String = "Player"
@export var player_types: PlayerCharacter = PlayerCharacter.美食博主

@export var current_energy: int = 6 
@export var max_energy: int = 12
@export var current_score: int = 0
@export var current_money: int = 500
@export var start_coord: Vector3i = Vector3i(0,0,0)

@export var player_index: int = 0
var 立绘精一: Texture2D = null
var 立绘精二: Texture2D = null
@export var 立绘精一图组: Dictionary[PlayerCharacter, Texture2D] = {}
@export var 立绘精二图组: Dictionary[PlayerCharacter, Texture2D] = {}

@onready var score_label = $ScoreBadge/Score as Label

var alive: bool = true
var now_pos: Vector3i = Vector3i(0, 0, 0)
var onTurn: bool = false
var maxMove:int = 0

var feiyi_collected_this_turn: bool = false # 记录本回合是否已经收集过非遗
## 本回合真正成功享用的食物数量；职业变化后按当前职业动态读取上限。
var food_used_count_this_turn: int = 0
## 兼容旧代码与测试的布尔视图。新逻辑统一读写 food_used_count_this_turn。
var food_used_this_turn: bool:
	get:
		return food_used_count_this_turn > 0
	set(value):
		food_used_count_this_turn = 1 if value else 0
var 武术拳法已生效:bool = false

var is_working: bool = false # 当前是否处于“连续打工”状态
var now_turn_worked: bool = false # 本回合是否已打工过
var work_turns_left: int = 0 # 剩余连续打工回合数
var work_turns: int = 0
var current_work_index: int = -1 # 当前打工格子的逻辑索引

var 非遗牌手牌: Array[非遗牌] = [] 
var 食物牌手牌: Array[食物牌] = []
var 事件牌手牌: Array[事件牌] = []
var last_successful_feiyi_section: MapSection = null
var arrival_id: int = 0
var last_normal_arrival_position: Vector3i = Vector3i(1 << 29, 1 << 29, 1 << 29)
## 最近一次允许在本回合 ACTION 结算格子效果的到达。
## 普通 MOVING 到达与探险博主 BEGIN 到达会写入；END 探索、事件传送和换位不会写入。
var last_action_arrival_position: Vector3i = Vector3i(1 << 29, 1 << 29, 1 << 29)
var last_action_arrival_turn_epoch: int = -1
var last_action_arrival_session_generation: int = -1
var last_resolved_event_arrival_id: int = 0
var last_resolved_scenery_arrival_id: int = 0
var last_opened_shop_arrival_id: int = -1
var handicraft_used_this_moving: bool = false
var movement_multiplier_applied: bool = false
var _profession_begin_move_turn_epoch: int = -1
var _profession_begin_move_session_generation: int = -1
var _profession_end_move_turn_epoch: int = -1
var _profession_end_move_session_generation: int = -1

func _init_character() -> void:
	animation = PlayerCharacter.find_key(player_types)
	立绘精一 = 立绘精一图组[player_types]
	立绘精二 = 立绘精二图组[player_types]

# --- 回合生命周期 ---
func _on_turn_manager_turn_start(player_idx: int) -> void:
	if player_idx != player_index:
		onTurn = false
		await get_tree().process_frame
		if material:
			material.set_shader_parameter("line_thickness", 0.0)
	else:
		onTurn = true
		await get_tree().process_frame
		if material:
			material.set_shader_parameter("line_thickness", 20)
		

func before_turn():
	print("玩家", player_name, "回合开始")

func reset_turn_usage_limits() -> void:
	feiyi_collected_this_turn = false
	food_used_count_this_turn = 0
	now_turn_worked = false
	_clear_action_arrival()

func _on_phase_changed(new_phase: TurnManager.TurnPhase):
	if !onTurn or !alive:
		return
	if new_phase == TurnManager.TurnPhase.BEGIN:
		reset_turn_usage_limits()
	if new_phase == TurnManager.TurnPhase.MOVING:
		武术拳法已生效 = false
		handicraft_used_this_moving = false
	var event_skipped: bool = EventManager.on_phase_entered(self, new_phase)
	var food_skipped: bool = FoodManager.on_phase_entered(self, new_phase, event_skipped)
	var delayed_messages: Array[String] = []
	var event_phase_message := EventManager.take_phase_message(self)
	var food_phase_message := FoodManager.take_phase_message(self)
	if not event_phase_message.is_empty():
		delayed_messages.append(event_phase_message)
	if not food_phase_message.is_empty():
		delayed_messages.append(food_phase_message)
	if event_skipped or food_skipped:
		if new_phase == TurnManager.TurnPhase.MOVING:
			emit_next_phase(TurnManager.TurnPhase.ACTION)
		elif new_phase == TurnManager.TurnPhase.ACTION:
			emit_next_phase(TurnManager.TurnPhase.END)
		_append_delayed_effect_messages(delayed_messages)
		return
	hud._update_button_states(new_phase)
	match new_phase:
		TurnManager.TurnPhase.BEGIN:
			_begin_profession_begin_move()
		TurnManager.TurnPhase.ROLL_DICE:
			if is_working:
				print(player_name, " 正在专心打工，跳过移动")
				hud._update_game_informs("打工中……")
				emit_next_phase(TurnManager.TurnPhase.ACTION)
				return
			hud._update_game_informs("玩家"+player_name+" 掷骰子中…")
			if not GameManager.is_headless_simulation():
				await get_tree().create_timer(1).timeout
			movement_multiplier_applied = false
			maxMove = FoodManager.adjust_movement_steps(self, do_roll_dice())
		TurnManager.TurnPhase.MOVING:
			pass
		TurnManager.TurnPhase.ACTION:
			hud._update_game_informs("等待行动…")
			hud._update_button_states(TurnManager.TurnPhase.ACTION)
			var current_section: MapSection = map.grid_map.get(now_pos)
			if current_section != null and current_section.type == MapSection.SectionType.风景:
				auto_trigger_scenery(current_section)
			elif current_section != null and current_section.type == MapSection.SectionType.事件:
				await EventManager.trigger_arrival_event(self, current_section, arrival_id)
		TurnManager.TurnPhase.END:
			_begin_profession_end_move()
	_append_delayed_effect_messages(delayed_messages)


func _append_delayed_effect_messages(messages: Array[String]) -> void:
	if hud == null or messages.is_empty():
		return
	var message := "\n".join(messages)
	if hud.information.text.is_empty():
		hud._update_game_informs(message)
	else:
		hud.information.text += "\n" + message

## BEGIN/END 阶段各一次的可选职业移动。同步取得模态锁，避免 1 秒阶段计时抢跑。
func _begin_profession_begin_move() -> void:
	_begin_profession_phase_move(TurnManager.TurnPhase.BEGIN)


func _begin_profession_end_move() -> void:
	_begin_profession_phase_move(TurnManager.TurnPhase.END)


func _begin_profession_phase_move(phase: TurnManager.TurnPhase) -> void:
	if TurnManager.now_phase != phase or not ProfessionManager.can_move_in_phase(self, phase) or map == null:
		return
	var turn_session_generation: int = TurnManager.get_session_generation()
	var turn_epoch: int = TurnManager.get_turn_epoch()
	match phase:
		TurnManager.TurnPhase.BEGIN:
			if _profession_begin_move_session_generation == turn_session_generation \
					and _profession_begin_move_turn_epoch == turn_epoch:
				return
			_profession_begin_move_session_generation = turn_session_generation
			_profession_begin_move_turn_epoch = turn_epoch
		TurnManager.TurnPhase.END:
			if _profession_end_move_session_generation == turn_session_generation \
					and _profession_end_move_turn_epoch == turn_epoch:
				return
			_profession_end_move_session_generation = turn_session_generation
			_profession_end_move_turn_epoch = turn_epoch
		_:
			return
	var options: Array[MapSection] = []
	for direction: Vector3i in 常量.MOVE:
		var coordinate: Vector3i = now_pos + direction
		var section: MapSection = map.grid_map.get(coordinate) as MapSection
		if section != null \
				and not section.is_occupied \
				and not (section.type == MapSection.SectionType.风景 and EventManager.is_scenery_banned(self)) \
				and not options.has(section):
			options.append(section)
	if options.is_empty():
		return
	var modal_token: int = TurnManager.begin_modal_resolution()
	_resolve_profession_phase_move(options, phase, turn_session_generation, turn_epoch, modal_token)

func _resolve_profession_phase_move(
	options: Array[MapSection],
	phase: TurnManager.TurnPhase,
	turn_session_generation: int,
	turn_epoch: int,
	modal_token: int
) -> void:
	var selected := await ProfessionManager.request_section_choice(
		self,
		options,
		"邻格探索",
		"请选择相邻格子"
	)
	if turn_session_generation != TurnManager.get_session_generation():
		if is_instance_valid(hud):
			hud.complete_profession_section_choice(self, turn_session_generation, turn_epoch, phase)
		return
	var owns_phase := _owns_current_profession_phase(turn_session_generation, turn_epoch, phase)
	if selected != null and owns_phase:
		var moved: bool = await _move_to_adjacent_for_profession(selected, phase, turn_session_generation, turn_epoch)
		if moved:
			if is_working:
				is_working = false
				work_turns_left = 0
				current_work_index = -1
			if hud != null:
				hud._update_game_informs("【邻格探索】移动完成。")
		elif hud != null:
			hud._update_game_informs("【邻格探索】未移动。")
	elif hud != null and TurnManager.GameOn:
		hud._update_game_informs("【邻格探索】未移动。")
	TurnManager.end_modal_resolution(false, true, modal_token)
	if is_instance_valid(hud):
		hud.complete_profession_section_choice(self, turn_session_generation, turn_epoch, phase)

func _owns_current_profession_phase(
	turn_session_generation: int,
	turn_epoch: int,
	phase: TurnManager.TurnPhase
) -> bool:
	return turn_session_generation == TurnManager.get_session_generation() \
		and turn_epoch == TurnManager.get_turn_epoch() \
		and TurnManager.GameOn \
		and TurnManager.now_phase == phase \
		and TurnManager.now_player_index >= 0 \
		and TurnManager.now_player_index < TurnManager.players.size() \
		and TurnManager.players[TurnManager.now_player_index] == self \
		and onTurn \
		and alive

## 技能移动本身永不立即触发格子。BEGIN 只登记本回合 ACTION 到达；END 不登记。
func _move_to_adjacent_for_profession(
	target_section: MapSection,
	phase: TurnManager.TurnPhase,
	turn_session_generation: int = -1,
	turn_epoch: int = -1
) -> bool:
	if target_section == null or map == null or target_section.is_occupied:
		return false
	if target_section.location_index not in _adjacent_coordinates():
		return false
	var old_coordinate := now_pos
	var old_section: MapSection = map.grid_map.get(now_pos) as MapSection
	var old_position := position
	target_section.is_occupied = true
	if GameManager.is_headless_simulation():
		position = map.to_local(target_section.global_position)
	else:
		var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", map.to_local(target_section.global_position), 0.28)
		await tween.finished
	if turn_session_generation >= 0 \
			and (not _owns_current_profession_phase(turn_session_generation, turn_epoch, phase) or now_pos != old_coordinate):
		target_section.is_occupied = _is_section_occupied_by_other_player(target_section)
		if now_pos == old_coordinate:
			position = old_position
		return false
	if old_section != null:
		old_section.is_occupied = false
	now_pos = target_section.location_index
	if phase == TurnManager.TurnPhase.BEGIN:
		_record_action_arrival(target_section, false)
	if hud != null:
		hud._update_player_stats(self)
	return true


func _record_action_arrival(section: MapSection, is_normal_movement: bool) -> void:
	if section == null:
		return
	arrival_id += 1
	last_action_arrival_position = section.location_index
	last_action_arrival_turn_epoch = TurnManager.get_turn_epoch()
	last_action_arrival_session_generation = TurnManager.get_session_generation()
	if is_normal_movement:
		last_normal_arrival_position = section.location_index
	section.grid_visit_history[self] = int(section.grid_visit_history.get(self, 0)) + 1


func _clear_action_arrival() -> void:
	last_action_arrival_position = Vector3i(1 << 29, 1 << 29, 1 << 29)
	last_action_arrival_turn_epoch = -1
	last_action_arrival_session_generation = -1


func has_current_action_arrival_at(coordinate: Vector3i) -> bool:
	return arrival_id > 0 \
		and last_action_arrival_position == coordinate \
		and last_action_arrival_turn_epoch == TurnManager.get_turn_epoch() \
		and last_action_arrival_session_generation == TurnManager.get_session_generation()

func _is_section_occupied_by_other_player(section: MapSection) -> bool:
	if section == null:
		return false
	for candidate: PlayerClass in TurnManager.players:
		if candidate == self or not is_instance_valid(candidate) or not candidate.alive:
			continue
		if candidate.map == map and candidate.now_pos == section.location_index:
			return true
	return false

func _adjacent_coordinates() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for direction: Vector3i in 常量.MOVE:
		result.append(now_pos + direction)
	return result

func emit_next_phase(next_phase: TurnManager.TurnPhase):
	TurnManager._emit_next_phase(next_phase)

## 仅由 TurnManager 在 END 阶段完成、即将交接下一位玩家前调用。
## 其他阶段精力降到 0 只保留数值状态，不得提前淘汰。
func resolve_turn_end_elimination() -> bool:
	print("玩家 ", player_name, "回合结束")
	if not alive or current_energy > 0:
		return false
	if await EventManager.try_revive_player(self):
		if hud != null:
			hud._update_game_informs("玩家 %s 被【妙手回春】复活，恢复3点精力！" % player_name)
		return false
	print("玩家 ", player_name,"体力耗尽，被淘汰！")
	alive = false
	var game_finished: bool = TurnManager.player_died(self)
	if map != null and map.grid_map.has(now_pos):
		map.grid_map[now_pos].is_occupied = false
	hide()
	if game_finished:
		return true
	if hud != null:
		hud._update_game_informs("玩家 " + player_name + "精力耗尽，被淘汰！分数：" + str(current_score))
	if is_inside_tree() and not GameManager.is_headless_simulation():
		get_tree().paused = true
		await get_tree().create_timer(2.5, true).timeout
		get_tree().paused = false
	return false

# --- 实体动作逻辑 ---
func do_roll_dice() -> int:
	# 两枚六面骰，保留 2-12 的正常概率分布。
	var result: int = GameManager.randi_between(1, 6) + GameManager.randi_between(1, 6)
	roll_dice.emit(result, self)
	print(player_name, " 掷出了 ", result, " 点")
	return result

func move_along_path(path_pixels: Array[Vector2], total_cost: int, target_grid_pos: Vector3i) -> bool:
	if path_pixels.is_empty() or not TurnManager.begin_movement_lock():
		return false
	if not 武术拳法已生效:
		for card in 非遗牌手牌:
			if card.category == 非遗牌.CardCategory.武术拳法:
				total_cost = maxi(total_cost-1, 0)
				武术拳法已生效 = true
				break
	var target_section: MapSection = map.grid_map[target_grid_pos]
	total_cost = EventManager.adjust_movement_cost(self, total_cost, path_pixels.size(), target_section)
	total_cost = FoodManager.commit_movement_cost(self, total_cost)
	ResourceManager.modify_energy(self, -total_cost, "移动消耗")
	hud.btn_end_turn.disabled = true
	if GameManager.is_headless_simulation():
		for point in path_pixels:
			maxMove -= 1
			position = map.to_local(point)
	else:
		var tween = create_tween()
		for point in path_pixels:
			maxMove -= 1
			hud._update_player_stats(self)
			var target_loacal = map.to_local(point)
			tween.tween_property(self, "position", target_loacal, 0.2).set_trans(Tween.TRANS_LINEAR)
		await tween.finished
	print(player_name, " 移动完毕。")
	map.grid_map[now_pos].is_occupied = false
	now_pos = target_grid_pos # 更新逻辑坐标
	var arrival_section: MapSection = map.grid_map[now_pos]
	arrival_section.is_occupied = true
	_record_action_arrival(arrival_section, true)
	hud._update_player_stats(self)
	hud.update_camera_view(0.5)
	map._clear_all_highlights()
	TurnManager.end_movement_lock()
	# 一次点击只消耗所选路径的步数；若本 MOVING 阶段仍有剩余步数，
	# 解除移动锁后必须以新位置、剩余步数和当前精力重新计算可达格。
	# 否则界面会显示仍可移动，但地图已经没有任何可点击目标。
	if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		map._show_reachable_areas()
	hud._update_button_states(TurnManager.now_phase)
	return true
# ==========================================
# 格子交互执行枢纽 (由 UI 点击触发)
# ==========================================
func execute_tile_action():
	if !onTurn:
		return
	
	hud.btn_action.disabled = true
	
	var section: MapSection = map.grid_map[now_pos]
	var s_index = section.logical_index
	
	match section.type:
		MapSection.SectionType.非遗:
			var region = section.region

			# 严格加上 not feiyi_collected_this_turn 的判定，防止同一回合执行两次
			if current_energy >= 1 and not feiyi_collected_this_turn and ResourceManager.has_feiyi_in_region(region):
				var collected: 非遗牌 = await ResourceManager.get_feiyi_with_profession(self, section)
				feiyi_collected_this_turn = collected != null
				ResourceManager.calculate_victory_score(self)
				if not GameManager.is_headless_simulation():
					await get_tree().create_timer(1.5).timeout
				if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
					hud._update_button_states(TurnManager.TurnPhase.ACTION)
			else:
				# 兜底防错：如果不满足条件却点进来了，解锁 UI 避免卡死
				hud.btn_action.disabled = false
				hud.btn_end_turn.disabled = false
				hud.btn_food.disabled = false
				
		MapSection.SectionType.打工:
			if EventManager.is_work_banned(self):
				hud._update_game_informs("罢耕歇业生效中，当前不能打工。")
				return
			var visit_count: int = section.grid_visit_history.get(self, 0)
			var work_energy_cost: int = ProfessionManager.get_work_energy_cost(self)
			if current_energy < work_energy_cost:
				hud._update_game_informs("精力不足，无法打工。")
				return
			if not is_working and visit_count <= 1:
				# 初次打工
				is_working = true
				work_turns_left = 2
				work_turns = 1
				current_work_index = s_index
				print(player_name, " 开始打工！")
				now_turn_worked = true
				hud.btn_action.disabled = true
				hud.btn_food.disabled = true
				hud._update_game_informs("开始打工！")
			
			elif is_working:
				# 连续打工中
				work_turns_left -= 1
				work_turns += 1
				print(player_name, " 继续打工，剩余 ", work_turns_left, " 回合。")
				hud.btn_action.disabled = true
				hud.btn_food.disabled = true
				now_turn_worked = true
				hud._update_game_informs("继续打工")
				
			var work_income := 0
			if current_energy >= work_energy_cost and is_working:
				var money_before_work := current_money
				if ResourceManager.process_work_salary(self, work_turns):
					work_income = maxi(current_money - money_before_work, 0)
				
			if work_turns_left <= 0:
				is_working = false
				hud.btn_action.disabled = true
				print(player_name, " 打工期满，恢复自由！")
				var work_message := FoodManager.get_work_income_effect_message(self)
				var finish_message := "打工结束，获得%d积分点！" % work_income
				hud._update_game_informs(finish_message if work_message.is_empty() else "%s\n%s" % [work_message, finish_message])
			
		MapSection.SectionType.商店:
			if has_current_action_arrival_at(now_pos) and last_opened_shop_arrival_id != arrival_id:
				hud.btn_action.disabled = true
				last_opened_shop_arrival_id = arrival_id
				print(player_name, " 打开了食物商店。")
				hud.open_shop_panel(self)
				# 注意：商店打开后不直接 emit END，等玩家买完或关掉弹窗再结束
			
			
		MapSection.SectionType.事件:
			hud._update_game_informs("事件已在进入行动阶段时自动结算，本回合仍可继续行动。")
			hud.btn_action.disabled = true
		MapSection.SectionType.研究所:
			if not has_current_action_arrival_at(now_pos):
				hud._update_game_informs("只有本回合实际到达研究所后才能进入。")
				return
			if not MarketManager.begin_visit(self, arrival_id):
				hud._update_game_informs("本次到达已进入过研究所。")
				return
			hud.open_market_panel(self)
			

# 自动触发类：风景。普通移动只在最终进入 ACTION 时结算，每次真实到达最多一次。
func auto_trigger_scenery(section: MapSection) -> bool:
	if section == null or section.type != MapSection.SectionType.风景:
		return false
	if TurnManager.now_phase != TurnManager.TurnPhase.ACTION:
		return false
	if not has_current_action_arrival_at(section.location_index):
		return false
	if arrival_id <= last_resolved_scenery_arrival_id:
		return false
	# 必须在任何奖励和信号之前登记，避免 HUD 刷新或重入重复结算。
	last_resolved_scenery_arrival_id = arrival_id
	if EventManager.is_scenery_banned(self):
		hud._update_game_informs("闭门谢客生效中，当前不能前往景区打卡。")
		return false
	if ResourceManager.vis_scenery(self, section):
		# 首次打卡的 +3 精力与旅行博主积分已由 ResourceManager 合并为同一条信息。
		return true
	var travel_reward: int = ProfessionManager.get_scenery_arrival_money(self)
	if not ProfessionManager.record_scenery_arrival(self, section, &"normal"):
		return false
	if hud != null:
		hud._update_game_informs("%s 到达风景区，获得%d积分点！" % [player_name, travel_reward])
	return true
	
		
# 退出打工拦截
func check_and_cancel_work():
	if is_working and not now_turn_worked:
		is_working = false
		work_turns_left = 0
		print(player_name, " 执行了其他操作，提前退出了打工状态！")
		hud._update_game_informs("结束打工！")
		if not GameManager.is_headless_simulation():
			await get_tree().create_timer(3).timeout

# 覆盖原本的结束回合请求
func request_end_turn():
	check_and_cancel_work() # 如果正在打工，点结束按钮直接放弃剩余打工回合
	if TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		TurnManager._emit_next_phase(TurnManager.TurnPhase.ACTION)
	elif TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		TurnManager._emit_next_phase(TurnManager.TurnPhase.END)
