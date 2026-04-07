extends Node
signal turn_start(player_idx : int)
signal phase_changed(new_phase: TurnPhase)
signal game_over()
signal next_phase(phase: TurnPhase)

enum TurnPhase{
	BEGIN,    # 等待游戏开始或过渡状态
	ROLL_DICE,  # 等待玩家投骰子
	MOVING,     # 玩家正在移动
	ACTION,     # 行动
	END         # 结算本回合
}
var players: Array[Node] = []
var now_turn: int = 0
var now_phase: TurnPhase = TurnPhase.BEGIN
var now_player_index: int = 0
var next_player_index: int = 0
var player_num: int = 0
var GameOn: bool = false

func start_game(player_nodes: Array[Node]):
	players = player_nodes
	player_num = players.size()
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
	now_player_index = next_player_index
	next_player_index = getNextPlayer(next_player_index)
	if next_player_index < 0:
		game_over.emit()
		GameOn = false
		return
	now_turn_start()

func getNextPlayer(player_id: int) -> int:
	var nxtplayer_id
	var cnt = 0
	nxtplayer_id = (player_id+1) % player_num
	while !players[nxtplayer_id].alive:
		nxtplayer_id = (player_id+1) % player_num
		cnt+=1
		if cnt > player_num:
			return -1
	return nxtplayer_id
