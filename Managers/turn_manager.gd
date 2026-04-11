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
var map: MAP
var hud: HUD

@onready var turn_timer: Timer = $TurnTimer

func _ready() -> void:
	# 核心枢纽：监听来自全游戏任何地方的阶段跳转请求
	next_phase.connect(_on_next_phase_requested)
	turn_timer.timeout.connect(_on_timer_timeout)
	hud = get_tree().get_first_node_in_group("HUD")
	await get_tree().process_frame
	map = get_tree().get_first_node_in_group("MAP")

func start_game(player_nodes: Array[PlayerClass]):
	players = player_nodes
	player_num = players.size()
	now_player_index = 0
	next_player_index = getNextPlayer(now_player_index)
	GameOn = true
	now_turn_start()

func now_turn_start():
	now_turn += 1
	turn_start.emit(now_player_index)
	# 引爆状态机的第一环
	change_phase(TurnPhase.BEGIN)

func _on_next_phase_requested(target_phase: TurnPhase):
	# 只要有人请求进入下一阶段，立刻掐断当前的计时器，防止幽灵回调
	if not turn_timer.is_stopped():
		turn_timer.stop()
	change_phase(target_phase)

func change_phase(new_phase: TurnPhase):
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
func _on_timer_timeout():
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
			now_turn_end()

func _emit_next_phase(nxt_phase: TurnPhase):
	if(now_phase == TurnPhase.MOVING):
		if map.grid_map[players[now_player_index].now_pos].grid_visit_history.has(players[now_player_index]):
			map.grid_map[players[now_player_index].now_pos].grid_visit_history[players[now_player_index]] += 1
		else:
			map.grid_map[players[now_player_index].now_pos].grid_visit_history[players[now_player_index]] = 1
	next_phase.emit(nxt_phase)

func now_turn_end():
	now_player_index = next_player_index
	next_player_index = getNextPlayer(now_player_index)
	if next_player_index < 0:
		game_over()
		GameOn = false
		return
	now_turn_start()

func getNextPlayer(player_id: int) -> int:
	var nxtplayer_id
	var cnt = 0
	nxtplayer_id = (player_id+1) % player_num
	while !players[nxtplayer_id].alive:
		nxtplayer_id = (nxtplayer_id+1) % player_num
		cnt+=1
		if cnt > player_num:
			return -1
	return nxtplayer_id

func player_died(player: PlayerClass):
	pass

func game_over():
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
