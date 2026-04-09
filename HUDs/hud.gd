extends CanvasLayer
class_name HUD
@onready var turn_label = $"回合信息/TurnLabel" as Label
@onready var phase_label = $"回合信息/PhaseLabel" as Label
@onready var time_label = $"回合信息/TimeLabel" as Label

@onready var player_label = $"玩家信息/玩家信息" as Label
@onready var money_label = $"玩家信息/MoneyLabel" as Label
@onready var energy_label = $"玩家信息/EnergyLabel" as Label

@onready var map_sec = $"地图"

@onready var btn_action = $"操作区域/BtnAction" as Button
@onready var btn_food = $"操作区域/BtnFood" as Button
@onready var btn_end_turn = $"操作区域/BtnEndTurn" as Button

@onready var score_label = $"积分区域/ScoreLabel" as Label

@onready var current_status = $"手牌信息/当前" as Label
@onready var information = $"手牌信息/游戏信息" as Label

@onready var timer = TurnManager.get_node("TurnTimer") as Timer
var map:MAP
func _ready() -> void:
	map = get_tree().get_first_node_in_group("MAP")
	TurnManager.turn_start.connect(_on_turn_start)
	TurnManager.phase_changed.connect(_on_phase_changed)
	btn_end_turn.pressed.connect(_on_btn_end_turn_pressed)
	btn_action.pressed.connect(_on_btn_action_pressed)
	#_update_button_states(TurnManager.TurnPhase.BEGIN)

func _process(delta: float):
	if timer and TurnManager.GameOn and timer.time_left > 0:
		time_label.visible = true
		time_label.text = " " + str(int(ceil(timer.time_left))) + " s"
	else:
		time_label.visible = false
	
func _on_turn_start(player_idx: int) -> void:
	var current_player = TurnManager.players[player_idx]
	turn_label.text = "回合数：" + str(TurnManager.now_turn) + " 当前玩家：" + current_player.player_name
	_update_player_stats(current_player)

func _on_phase_changed(new_phase: TurnManager.TurnPhase) -> void:
	# 每次阶段改变时，刷新 UI 上的数值和按钮可用性
	var current_player = TurnManager.players[TurnManager.now_player_index]
	_update_player_stats(current_player)
	_update_button_states(new_phase)
	
	match new_phase:
		TurnManager.TurnPhase.BEGIN:
			information.text = "等待中…"
			phase_label.text = "【准备阶段】"
		TurnManager.TurnPhase.ROLL_DICE:
			phase_label.text = "【掷骰子】"
			TurnManager.players[TurnManager.now_player_index].roll_dice.connect(_roll_dice_information)
			await TurnManager.players[TurnManager.now_player_index].roll_dice
			TurnManager.players[TurnManager.now_player_index].roll_dice.disconnect(_roll_dice_information)
		TurnManager.TurnPhase.MOVING:
			phase_label.text = "【移动中】"
		TurnManager.TurnPhase.ACTION:
			phase_label.text = "【行动阶段】"
			# TODO: 这里需要根据玩家当前踩的格子类型，动态改变 btn_action 的文字（如“打工”、“抽取非遗”）
		TurnManager.TurnPhase.END:
			phase_label.text = "【结束阶段】"

func _roll_dice_information(result:int, player:PlayerClass) -> void:
	_update_game_informs("玩家 " + player.player_name + " 掷出了 " + str(result) + " 点！")

# --- UI 刷新状态函数 ---
func _update_player_stats(player: PlayerClass) -> void:
	money_label.text = "积分点: " + str(player.current_money)
	energy_label.text = "精力: " + str(player.current_energy) + " / " + str(player.max_energy)
	score_label.text = "总分数: " + str(player.current_score)
	current_status.text = "当前位置：" + MapSection.REGION.find_key(map.grid_map[player.now_pos].region) + str(map.grid_map[player.now_pos].location_index) + " - " + MapSection.SectionType.find_key(map.grid_map[player.now_pos].type)
	if(TurnManager.now_phase == TurnManager.TurnPhase.MOVING):
		_update_game_informs("剩余可移动：" + str(player.maxMove) + " 步")

func _update_game_informs(information_to_display: String) -> void:
	information.text = information_to_display

func _update_button_states(phase: TurnManager.TurnPhase) -> void:
	# 核心解耦：UI 自己决定什么时候按钮该亮起
	btn_action.disabled = (phase != TurnManager.TurnPhase.ACTION)
	btn_end_turn.disabled = (not phase in [TurnManager.TurnPhase.ACTION, TurnManager.TurnPhase.MOVING])
	btn_food.disabled = (phase != TurnManager.TurnPhase.ACTION)

	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	var current_coord: Vector3i = current_player.now_pos
	
	if not map.grid_map.has(current_coord): return
	var current_section = map.grid_map[current_coord]
	
	if phase == TurnManager.TurnPhase.ACTION:
		match current_section.type: # 注意你定义的枚举变量名叫 type
			MapSection.SectionType.非遗:
				# 获取玩家当前脚下格子属于哪个市区（字符串）
				var region: MapSection.REGION = current_section.region
				
				btn_action.text = "收集非遗"
				
				# 判定一：如果该地区根本没有牌了
				if not ResourceManager.has_feiyi_in_region(region):
					btn_action.text = "已被收集完"
					btn_action.disabled = true
				# 判定二：精力不足或本回合已收集
				elif current_player.current_energy < 1 or current_player.feiyi_collected_this_turn:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.打工:
				btn_action.text = "打工"
				if current_player.current_energy < 1:
					btn_action.disabled = true
				# 历史打过工，且现在并不在打工状态中，则终生禁止在此地再次打工
				elif current_section.grid_visit_history[current_player] > 1 and not current_player.is_working:
					btn_action.disabled = true
				elif current_player.now_turn_worked:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.商店:
				btn_action.text = "打开商店"
				# 买过一次就禁止再买
				if current_section.grid_visit_history[current_player] > 1:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.风景:
				btn_action.text = "行动"
				btn_action.disabled = true # 风景是自动的，手动按钮一直禁用
				if current_section.grid_visit_history[current_player] <= 1:
					current_player.auto_trigger_scenery(current_section) 
			_:
				btn_action.text = "探索"
				btn_action.disabled = true
	else: btn_action.text = "探索"

func _on_btn_action_pressed() -> void:
	var current_player = TurnManager.players[TurnManager.now_player_index]
	current_player.execute_tile_action()

func _on_btn_end_turn_pressed() -> void:
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	if current_player.is_working:
		btn_end_turn.disabled = true
		btn_action.disabled = true
		btn_food.disabled = true
		await current_player.check_and_cancel_work()
		
	if TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		current_player.emit_next_phase(TurnManager.TurnPhase.ACTION)
	elif TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		current_player.emit_next_phase(TurnManager.TurnPhase.END)

func _on_btn_food_pressed() -> void:
	var current_player = TurnManager.players[TurnManager.now_player_index]
	if current_player.is_working:
		await current_player.check_and_cancel_work()

func open_shop_panel(player:PlayerClass):
	pass
