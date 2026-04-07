extends Node
signal turn_start(player_idx : int)
signal phase_changed(new_phase: TurnPhase)
signal game_over(winner_id: int)
signal next_phase(phase: TurnPhase)

enum TurnPhase{
	BEGIN,    # 等待游戏开始或过渡状态
	ROLL_DICE,  # 等待玩家投骰子
	MOVING,     # 玩家正在移动
	ACTION,     # 行动
	END         # 结算本回合
}
var players: Array[int] = []
var now_turn: int = 0
var now_phase: TurnPhase = TurnPhase.BEGIN
var now_player_index: int = 0
var next_player_index: int = 0
var player_num: int = 0
var player_alive_num: int = 0
var GameOn: bool = false

func start_game(player_count: int):
	players.clear()
	for i in range(player_count):
		players.append(i)
	player_num = player_count
	player_alive_num = player_num
	now_player_index = 0
	next_player_index = now_player_index
	GameOn = true
	now_turn_start()

func now_turn_start():
	$TurnTimer.start()
	turn_start.emit(now_player_index)
	for phase in TurnPhase.values():
		await change_phase(phase)
		await next_phase
	

func now_turn_end():
	next_turn()
	
func change_phase(new_phase: TurnPhase):
	now_phase = new_phase
	phase_changed.emit(now_phase)
	
	match now_phase:
		TurnPhase.BEGIN:
			print("回合开始")
		TurnPhase.ROLL_DICE:
			print("等待玩家掷骰子……")
		TurnPhase.MOVING:
			print("等待玩家移动……")
		TurnPhase.ACTION:
			print("等待玩家行动……")
		TurnPhase.END:
			print("回合结束")
			
			
func next_turn():
	now_turn += 1
	# 待补充
	now_player_index = next_player_index
	next_player_index = getNextPlayer(next_player_index)
	now_turn_start()

func getNextPlayer(current_id: int) -> int:
	# 安全校验：只剩1个人或全死光了，直接判定游戏结束
	if player_alive_num <= 1:
		# 触发游戏结束信号，把唯一存活的玩家ID传出去
		for i in range(player_num):
			if players_alive[i]:
				game_over.emit(i)
				return i
		return -1

	var check_id = current_id
	var checked_count = 0
	
	# 最多循环查找 player_num 次，防止出现死循环
	while checked_count < player_num:
		check_id = (check_id + 1) % player_num
		if players_alive[check_id] == true:
			return check_id # 找到一个活着的人，返回他的ID
		checked_count += 1
		
	return -1
