extends AnimatedSprite2D
class_name PlayerClass
signal turn_over_byself
signal roll_dice(result:int, player:PlayerClass)
signal _internal_turn_end
signal player_died(player:PlayerClass)
var hud:HUD
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

var player_index: int = 0
var alive: bool = true
var now_pos: Vector3i = Vector3i(0, 0, 0)
var onTurn: bool = false
var maxMove:int = 0

# 这是一个数组，专门用来存放 CardData 类型的资源，也就是玩家手里的“非遗卡牌”
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

#func during_turn():
	#var turntimer = TurnManager.get_node("TurnTimer")
	#
	## 创建一个回调函数，无论哪个信号触发，都发射统一的内部信号
	#var callback = func(): 
		#_internal_turn_end.emit()
		#
	## 连接两个可能的结束条件
	#if not turntimer.timeout.is_connected(callback):
		#turntimer.timeout.connect(callback)
	#if not turn_over_byself.is_connected(callback):
		#turn_over_byself.connect(callback)
	#
	## 等待统一信号
	#await _internal_turn_end
	#
	## 【强制清理】断开连接，否则下个回合会重复触发导致内存泄漏和逻辑雪崩
	#turntimer.timeout.disconnect(callback)
	#turn_over_byself.disconnect(callback)
	#
	## 计时器的 stop 应交由 TurnManager 处理，这里仅防错
	#if not turntimer.is_stopped():
		#turntimer.stop()

func _on_phase_changed(new_phase: TurnManager.TurnPhase):
	if !onTurn:
		return
	match new_phase:
		TurnManager.TurnPhase.BEGIN:
			TurnManager.next_phase.emit(TurnManager.TurnPhase.ROLL_DICE)
		TurnManager.TurnPhase.ROLL_DICE:
			maxMove = do_roll_dice()
			await TurnManager.get_node("TurnTimer").timeout
			TurnManager.next_phase.emit(TurnManager.TurnPhase.MOVING)
		TurnManager.TurnPhase.MOVING:
			TurnManager.next_phase.emit(TurnManager.TurnPhase.ACTION)
		TurnManager.TurnPhase.ACTION:
			var turntimer = TurnManager.get_node("TurnTimer")
			turntimer.start()
			# 创建一个回调函数，无论哪个信号触发，都发射统一的内部信号
			var callback = func(): 
				_internal_turn_end.emit()
			# 连接两个可能的结束条件
			if not turntimer.timeout.is_connected(callback):
				turntimer.timeout.connect(callback)
			if not turn_over_byself.is_connected(callback):
				turn_over_byself.connect(callback)
			# 等待统一信号
			await _internal_turn_end
			# 【强制清理】断开连接，否则下个回合会重复触发导致内存泄漏和逻辑雪崩
			turntimer.timeout.disconnect(callback)
			turn_over_byself.disconnect(callback)
			# 计时器的 stop 应交由 TurnManager 处理，这里仅防错
			if not turntimer.is_stopped():
				turntimer.stop()
			TurnManager.next_phase.emit(TurnManager.TurnPhase.END)
		TurnManager.TurnPhase.END:
			pass

func after_turn():
	print("玩家 ", player_name, "回合结束")
	if alive and current_energy <= 0:
		print("玩家 ", player_name,"体力耗尽，被淘汰！")
		alive = false
		player_died.emit(self)
		
# 1. 触发抽卡请求（通常在“非遗”或“事件”格子上触发）
func request_draw_card(deck_type: 卡牌基类.CardType, count: int = 1):
	print(player_name, " 发起抽卡请求：", deck_type)
	ResourceManager.draw_card(self, deck_type, count)
	
	# 如果抽的是非遗牌，一定要通知资源管理器重算得分！
	if deck_type == 卡牌基类.CardType.非遗牌:
		ResourceManager.calculate_victory_score(self)
		
	# 行动完成后，向外发射内部结束信号，解除 during_turn 的等待
	turn_over_byself.emit() 

# 2. 触发打工请求
func request_work(work_turn: int):
	print(player_name, " 发起打工请求，当前轮数：", work_turn)
	ResourceManager.process_work_salary(self, work_turn)
	turn_over_byself.emit()

# 3. 触发商店购买请求
func request_buy_food(food_card: 食物牌):
	print(player_name, " 发起购买食物请求：", food_card.card_name if "card_name" in food_card else "未知食物")
	var success = ResourceManager.buy_food(self, food_card)
	if success:
		pass
	else:
		print("购买失败，行动未结束，请玩家重新选择。")
		# 购买失败不 emit 结束信号，让玩家继续停留在 ACTION 阶段操作

# 4. 什么都不做，直接结束回合（直接点结束按钮）
func request_end_turn():
	print(player_name, " 放弃行动，直接结束。")
	turn_over_byself.emit()

# --- 实体动作逻辑 ---
func do_roll_dice() -> int:
	var result = randi_range(1, 12)
	roll_dice.emit(result, self)
	print(player_name, " 掷出了 ", result, " 点")
	return result

func move_along_path(path_pixels: Array[Vector2], total_cost: int, target_grid_pos: Vector3i) -> void:
	# 资源扣除交由 ResourceManager 处理更为严谨，此处仅发请求或本地暂扣
	current_energy -= total_cost
	now_pos = target_grid_pos
	
	var tween = create_tween()
	for point in path_pixels:
		tween.tween_property(self, "position", point, 0.2).set_trans(Tween.TRANS_LINEAR)
		# 此处 触发事件
	
	await tween.finished
	print(player_name, " 移动完毕。")
	now_pos = target_grid_pos
