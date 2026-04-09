extends AnimatedSprite2D
class_name PlayerClass
signal roll_dice(result:int, player:PlayerClass)
signal player_died(player:PlayerClass)
var hud:HUD
var map:MAP
enum PlayerCharacter{
	无,
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
	map = get_tree().get_first_node_in_group("MAP") as MAP
	now_pos = start_coord
	position = map.grid_map[start_coord].global_position
	map.grid_map[start_coord].is_occupied = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 玩家的基础属性 [cite: 1]
@export var player_name: String = "Player"
@export var player_types: PlayerCharacter = PlayerCharacter.无

@export var current_energy: int = 6 
@export var max_energy: int = 12
@export var current_score: int = 0
@export var current_money: int = 1000
@export var start_coord: Vector3i = Vector3i(0,0,0)

@export var player_index: int = 0
var alive: bool = true
var now_pos: Vector3i = Vector3i(0, 0, 0)
var onTurn: bool = false
var maxMove:int = 0

var feiyi_collected_this_turn: bool = false # 记录本回合是否已经收集过非遗

var is_working: bool = false # 当前是否处于“连续打工”状态
var now_turn_worked: bool = false # 本回合是否已打工过
var work_turns_left: int = 0 # 剩余连续打工回合数
var work_turns: int = 0
var current_work_index: int = -1 # 当前打工格子的逻辑索引

var 非遗牌手牌: Array[非遗牌] = [] 
var 食物牌手牌: Array[食物牌] = []

# --- 回合生命周期 ---
func _on_turn_manager_turn_start(player_idx: int) -> void:
	if player_idx != player_index:
		onTurn = false
	else:
		onTurn = true

func before_turn():
	print("玩家", player_name, "回合开始")

func _on_phase_changed(new_phase: TurnManager.TurnPhase):
	if !onTurn:
		return
	hud._update_button_states(new_phase)
	match new_phase:
		TurnManager.TurnPhase.BEGIN:
			feiyi_collected_this_turn = false
			now_turn_worked = false
		TurnManager.TurnPhase.ROLL_DICE:
			if is_working:
				print(player_name, " 正在专心打工，跳过移动")
				hud._update_game_informs("打工中……")
				emit_next_phase(TurnManager.TurnPhase.ACTION)
				return
			hud._update_game_informs("玩家"+player_name+" 掷骰子中…")
			await get_tree().create_timer(1).timeout
			maxMove = do_roll_dice()
		TurnManager.TurnPhase.MOVING:
			pass
		TurnManager.TurnPhase.ACTION:
			hud._update_game_informs("等待行动…")
			hud._update_button_states(TurnManager.TurnPhase.ACTION)
		TurnManager.TurnPhase.END:
			pass

func emit_next_phase(next_phase: TurnManager.TurnPhase):
	TurnManager._emit_next_phase(next_phase)

func after_turn():
	print("玩家 ", player_name, "回合结束")
	if alive and current_energy <= 0:
		print("玩家 ", player_name,"体力耗尽，被淘汰！")
		alive = false
		player_died.emit(self)

# --- 实体动作逻辑 ---
func do_roll_dice() -> int:
	var result = randi_range(1, 12)
	roll_dice.emit(result, self)
	print(player_name, " 掷出了 ", result, " 点")
	return result

func move_along_path(path_pixels: Array[Vector2], total_cost: int, target_grid_pos: Vector3i) -> void:
	current_energy -= total_cost
	var tween = create_tween()
	for point in path_pixels:
		maxMove -= 1
		hud._update_player_stats(self)
		tween.tween_property(self, "global_position", point, 0.2).set_trans(Tween.TRANS_LINEAR)
		# 此处 触发事件
	await tween.finished
	print(player_name, " 移动完毕。")
	map.grid_map[now_pos].is_occupied = false
	now_pos = target_grid_pos # 更新逻辑坐标
	map.grid_map[now_pos].is_occupied = true
	hud._update_player_stats(self)
	map._clear_all_highlights()
	map._show_reachable_areas()
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
				var card = ResourceManager.get_feiyi(self, section)
				feiyi_collected_this_turn = true
				ResourceManager.calculate_victory_score(self)
				await get_tree().create_timer(1.5).timeout
			else:
				# 兜底防错：如果不满足条件却点进来了，解锁 UI 避免卡死
				hud.btn_action.disabled = false
				hud.btn_end_turn.disabled = false
				hud.btn_food.disabled = false
				
		MapSection.SectionType.打工:
			if not is_working and section.grid_visit_history[self]<=1:
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
				
			if current_energy >= 1 and is_working:
				ResourceManager.process_work_salary(self, work_turns)
				
			if work_turns_left <= 0:
				is_working = false
				hud.btn_action.disabled = true
				print(player_name, " 打工期满，恢复自由！")
				hud._update_game_informs("打工结束！")
			
		MapSection.SectionType.商店:
			if section.grid_visit_history[self] == 1:
				hud.btn_action.disabled = true
				print(player_name, " 打开了食物商店。")
				# 呼叫 HUD 打开商店弹窗（HUD中留好接口）
				hud.open_shop_panel(self)
				# 注意：商店打开后不直接 emit END，等玩家买完或关掉弹窗再结束
			
			
		MapSection.SectionType.事件, MapSection.SectionType.研究所:
			print(player_name, " 触发了未实装的格子：", section.type)
			emit_next_phase(TurnManager.TurnPhase.END)
			

# 自动触发类：风景
func auto_trigger_scenery(section: MapSection):
	if(section.type != MapSection.SectionType.风景):
		return
	if section.grid_visit_history[self] == 1:
		ResourceManager.vis_scenery(self, section)
	
		
# 退出打工拦截
func check_and_cancel_work():
	if is_working and not now_turn_worked:
		is_working = false
		work_turns_left = 0
		print(player_name, " 执行了其他操作，提前退出了打工状态！")
		hud._update_game_informs("结束打工！")
		await get_tree().create_timer(3).timeout

# 覆盖原本的结束回合请求
func request_end_turn():
	check_and_cancel_work() # 如果正在打工，点结束按钮直接放弃剩余打工回合
	if TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		TurnManager.next_phase.emit(TurnManager.TurnPhase.ACTION)
	elif TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		TurnManager.next_phase.emit(TurnManager.TurnPhase.END)
