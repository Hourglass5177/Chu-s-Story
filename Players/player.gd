extends AnimatedSprite2D
class_name PlayerClass
signal turn_over_byself
signal roll_dice(result:int)
signal _internal_turn_end
signal player_died(player:PlayerClass)

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

# 这是一个数组，专门用来存放 CardData 类型的资源，也就是玩家手里的“非遗卡牌”
var 非遗牌手牌: Array[非遗牌] = [] 
var 食物牌手牌: Array[食物牌] = []

# --- 回合生命周期 ---
func _on_turn_manager_turn_start(player_idx: int) -> void:
	if player_idx != player_index:
		return
	before_turn()
	await during_turn()
	after_turn()

func before_turn():
	print("玩家", player_name, "回合开始")

func during_turn():
	var turntimer = TurnManager.get_node("TurnTimer")
	
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

func _on_phase_changed(new_phase: TurnManager.TurnPhase):
	pass

func after_turn():
	print("玩家 ", player_name, "回合结束")
	if alive and current_energy <= 0:
		print("玩家 ", player_name,"体力耗尽，被淘汰！")
		alive = false
		player_died.emit(self)

# --- 实体动作逻辑 ---
func do_roll_dice() -> int:
	var result = randi_range(1, 12)
	roll_dice.emit(result)
	print(player_name, " 掷出了 ", result, " 点")
	return result

func move_along_path(path_pixels: Array[Vector2], total_cost: int, target_grid_pos: Vector3i) -> void:
	# 资源扣除交由 ResourceManager 处理更为严谨，此处仅发请求或本地暂扣
	current_energy -= total_cost
	now_pos = target_grid_pos
	
	var tween = create_tween()
	for point in path_pixels:
		tween.tween_property(self, "position", point, 0.2).set_trans(Tween.TRANS_LINEAR)
	
	await tween.finished
	print(player_name, " 移动完毕。")
