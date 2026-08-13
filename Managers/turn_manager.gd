extends Node
signal turn_start(player_idx : int)
signal phase_changed(new_phase: TurnPhase)
signal next_phase(target_phase: TurnPhase)

enum TurnPhase{
	BEGIN,    # 等待游戏开始或过渡状态
	ROLL_DICE,  # 等待玩家投骰子
	MOVING,     # 玩家正在移动
	ACTION,     # 行动
	END         # 结算本回合
}

var players: Array[PlayerClass] = []
var now_turn: int = 0
var now_phase: TurnPhase = TurnPhase.BEGIN
var now_player_index: int = 0
var next_player_index: int = 0
var player_num: int = 0
var GameOn: bool = false
var modal_resolution_depth: int = 0
var movement_lock_active: bool = false
var _movement_resume_time: float = 0.0
var map: MAP
var hud: HUD

@onready var turn_timer: Timer = $TurnTimer

func _ready() -> void:
	# 核心枢纽：监听来自全游戏任何地方的阶段跳转请求
	next_phase.connect(_on_next_phase_requested)
	turn_timer.timeout.connect(_on_timer_timeout)
	#hud = get_tree().get_first_node_in_group("HUD")
	#await get_tree().process_frame
	#map = get_tree().get_first_node_in_group("MAP")

func start_game(player_nodes: Array[PlayerClass]) -> void:
	players = player_nodes
	player_num = players.size()
	if player_num == 0:
		push_error("TurnManager.start_game: 至少需要一名玩家。")
		return
	now_turn = 0
	now_player_index = 0
	next_player_index = getNextPlayer(now_player_index)
	GameOn = true
	modal_resolution_depth = 0
	movement_lock_active = false
	_movement_resume_time = 0.0
	EventManager.reset_for_new_game()
	if has_node("/root/MarketManager"):
		MarketManager.reset_for_new_game()
	now_turn_start()

func now_turn_start() -> void:
	if not GameOn:
		return
	now_turn += 1
	turn_start.emit(now_player_index)
	# 引爆状态机的第一环
	change_phase(TurnPhase.BEGIN)
	if hud.is_focus_mode:
		hud.update_camera_view(0.5)

func _on_next_phase_requested(target_phase: TurnPhase) -> void:
	if not GameOn or movement_lock_active:
		return
	# 只要有人请求进入下一阶段，立刻掐断当前的计时器，防止幽灵回调
	if not turn_timer.is_stopped():
		turn_timer.stop()
	change_phase(target_phase)

func change_phase(new_phase: TurnPhase) -> void:
	if not GameOn:
		return
	now_phase = new_phase
	
	# 进入新阶段的初始化与倒计时设定
	match now_phase:
		TurnPhase.BEGIN:
			print("--- 回合开始 ---")
			turn_timer.start(1.0)
		TurnPhase.ROLL_DICE:
			print(">>> 等待玩家掷骰子")
			turn_timer.start(3.0) # 兜底防卡死
		TurnPhase.MOVING:
			get_tree().call_group("section", "_clear_is_reached")
			print(">>> 等待玩家移动")
			turn_timer.start(15.0)
		TurnPhase.ACTION:
			print(">>> 等待玩家行动")
			turn_timer.start(15.0)
		TurnPhase.END:
			print("--- 回合结束 ---")
			turn_timer.start(1.0)
			
	# 广播当前阶段，让 Player 和 HUD 做出反应
	phase_changed.emit(now_phase)

# 倒计时结束的自动推进逻辑
func _on_timer_timeout() -> void:
	if not GameOn or modal_resolution_depth > 0 or movement_lock_active:
		return
	match now_phase:
		TurnPhase.BEGIN:
			_emit_next_phase(TurnPhase.ROLL_DICE)
		TurnPhase.ROLL_DICE:
			_emit_next_phase(TurnPhase.MOVING)
		TurnPhase.MOVING:
			# 时间到了没移动，强制进入行动阶段
			_emit_next_phase(TurnPhase.ACTION)
		TurnPhase.ACTION:
			# 时间到了没操作，强制结束
			_emit_next_phase(TurnPhase.END)
		TurnPhase.END:
			# 结算结束，把轮次交给下一个人
			await now_turn_end()

func _emit_next_phase(nxt_phase: TurnPhase) -> void:
	if not GameOn or modal_resolution_depth > 0 or movement_lock_active:
		return
	next_phase.emit(nxt_phase)

func begin_movement_lock() -> bool:
	if not GameOn or now_phase != TurnPhase.MOVING or movement_lock_active:
		return false
	movement_lock_active = true
	_movement_resume_time = turn_timer.time_left if not turn_timer.is_stopped() else 0.0
	turn_timer.stop()
	return true

func end_movement_lock() -> void:
	if not movement_lock_active:
		return
	movement_lock_active = false
	if GameOn and now_phase == TurnPhase.MOVING and modal_resolution_depth == 0:
		turn_timer.start(maxf(_movement_resume_time, 0.05))
	_movement_resume_time = 0.0

func is_movement_locked() -> bool:
	return movement_lock_active

func begin_modal_resolution() -> void:
	modal_resolution_depth += 1
	if not turn_timer.is_stopped():
		turn_timer.stop()

func end_modal_resolution(reset_action_timer: bool = true) -> void:
	modal_resolution_depth = maxi(modal_resolution_depth - 1, 0)
	if modal_resolution_depth == 0 and reset_action_timer and GameOn and now_phase == TurnPhase.ACTION:
		turn_timer.start(15.0)

func is_modal_resolution_active() -> bool:
	return modal_resolution_depth > 0

func now_turn_end() -> void:
	if not GameOn:
		return
	# 淘汰只能在完整回合结束、即将交接玩家的这一刻判断。
	# 移动或行动中精力为 0 的玩家仍可继续 ACTION 并使用食物恢复。
	if now_player_index >= 0 and now_player_index < players.size():
		await players[now_player_index].resolve_turn_end_elimination()
	if not GameOn:
		return
	if has_player_reached_score_limit():
		game_over()
		return
	now_player_index = next_player_index
	next_player_index = getNextPlayer(now_player_index)
	if next_player_index < 0:
		game_over()
		GameOn = false
		return
	now_turn_start()

func getNextPlayer(player_id: int) -> int:
	if player_num <= 0:
		return -1
	for offset in range(1, player_num + 1):
		var candidate_index: int = (player_id + offset) % player_num
		if players[candidate_index].alive:
			return candidate_index
	return -1

func player_died(_player: PlayerClass) -> bool:
	if has_reached_elimination_limit():
		game_over()
		return true
	return false

func has_player_reached_score_limit() -> bool:
	for player: PlayerClass in players:
		if player.current_score >= 20:
			return true
	return false

func has_reached_elimination_limit() -> bool:
	var eliminated_count := 0
	for player: PlayerClass in players:
		if not player.alive:
			eliminated_count += 1
	# 正式多人局固定累计淘汰两人；单人仅用于调试。
	var elimination_limit := 1 if players.size() <= 1 else 2
	return eliminated_count >= elimination_limit

func game_over() -> void:
	if not GameOn:
		return
	GameOn = false
	turn_timer.stop()
	var winners:Array[PlayerClass] = ResourceManager.find_winner()
	if winners.size() > 1:
		var info:String = "玩家 "
		for winner:PlayerClass in winners:
			info += winner.player_name + " "
		info += "并列获胜！ 分数：" + str(winners[0].current_score)
		hud._update_game_informs(info)
	elif winners.size() == 1:
		hud._update_game_informs("玩家 "+winners[0].player_name+" 获胜！ 分数：" + str(winners[0].current_score))
	hud.btn_close_game.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
