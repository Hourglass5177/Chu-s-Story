extends CanvasLayer
@onready var turn_label = $"回合信息/TurnLabel"
@onready var phase_label = $"回合信息/PhaseLabel"
@onready var time_label = $"回合信息/TimeLabel"

@onready var player_label = $"玩家信息/玩家信息"
@onready var money_label = $"玩家信息/MoneyLabel"
@onready var energy_label = $"玩家信息/EnergyLabel"

@onready var map_sec = $"地图"

@onready var btn_action = $"操作区域/BtnAction"
@onready var btn_food = $"操作区域/BtnFood"
@onready var btn_end_turn = $"操作区域/BtnEndTurn"

@onready var score_label = $"积分区域/ScoreLabel"

@onready var currunt_status = $"手牌信息/当前"

func _ready() -> void:
	TurnManager.turn_start.connect(_on_turn_start)
	TurnManager.phase_changed.connect(_on_phase_changed)
	_update_button_states(TurnManager.TurnPhase.BEGIN)
	
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
			phase_label.text = "【准备阶段】"
		TurnManager.TurnPhase.ROLL_DICE:
			phase_label.text = "【掷骰子】"
		TurnManager.TurnPhase.MOVING:
			phase_label.text = "【移动中】"
		TurnManager.TurnPhase.ACTION:
			phase_label.text = "【行动阶段】"
			# TODO: 这里需要根据玩家当前踩的格子类型，动态改变 btn_action 的文字（如“打工”、“抽取非遗”）
		TurnManager.TurnPhase.END:
			phase_label.text = "【结束阶段】"

# --- UI 刷新辅助函数 ---
func _update_player_stats(player: PlayerClass) -> void:
	money_label.text = "积分点: " + str(player.current_money)
	energy_label.text = "精力: " + str(player.current_energy) + " / " + str(player.max_energy)
	score_label.text = "总分数: " + str(player.current_score)

func _update_button_states(phase: TurnManager.TurnPhase) -> void:
	# 核心解耦：UI 自己决定什么时候按钮该亮起
	btn_action.disabled = (phase != TurnManager.TurnPhase.ACTION)
	btn_end_turn.disabled = (phase != TurnManager.TurnPhase.ACTION)
	btn_food.disabled = (phase != TurnManager.TurnPhase.ACTION)

func _on_btn_action_pressed() -> void:
	var current_player = TurnManager.players[TurnManager.now_player_index]
	
	# 这里目前用一个测试逻辑代替。
	# 未来应通过 MainMap 获取 current_player.now_pos 所在格子的 SectionType
	print("执行格子默认行动：抽一张非遗牌")
	current_player.request_draw_card(卡牌基类.CardType.非遗牌, 1)

func _on_btn_end_turn_pressed() -> void:
	var current_player = TurnManager.players[TurnManager.now_player_index]
	current_player.request_end_turn()

func _process(delta: float):
	#time_label.text = str(TurnManager.get_node("TurnTimer"))
	pass
