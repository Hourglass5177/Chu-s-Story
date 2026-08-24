extends Node
signal turn_start(player_idx : int)
signal phase_changed(new_phase: TurnPhase)
signal next_phase(target_phase: TurnPhase)
signal game_finished(result: GameResult)
signal turn_completed(player: PlayerClass, turn_number: int)
signal modal_state_changed(snapshot: Dictionary)

const NO_END_REASON: int = -1
const EndReason = GameResult.EndReason

enum TurnPhase{
	BEGIN,    # 等待游戏开始或过渡状态
	ROLL_DICE,  # 等待玩家投骰子
	MOVING,     # 玩家正在移动
	ACTION,     # 行动
	END         # 结算本回合
}

enum ModalResumePolicy {
	NO_RESUME,
	RESET_ACTION,
	RESUME_REMAINING,
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
var _modal_resume_time: float = 0.0
var _modal_resume_phase: TurnPhase = TurnPhase.BEGIN
var _modal_resume_session_generation: int = -1
var _modal_resume_turn_epoch: int = -1
var _modal_resolution_token: int = 0
var _modal_leases: Dictionary[int, Dictionary] = {}
var _legacy_modal_stack: Array[int] = []
var _root_modal_policy: ModalResumePolicy = ModalResumePolicy.NO_RESUME
var _root_modal_lease_id: int = -1
var _session_generation: int = 0
var _turn_epoch: int = 0
var _ending_turn: bool = false
var map: MAP
var hud: HUD
var _last_game_result: GameResult = null

@onready var turn_timer: Timer = $TurnTimer

func _ready() -> void:
	# 核心枢纽：监听来自全游戏任何地方的阶段跳转请求
	next_phase.connect(_on_next_phase_requested)
	turn_timer.timeout.connect(_on_timer_timeout)
	#hud = get_tree().get_first_node_in_group("HUD")
	#await get_tree().process_frame
	#map = get_tree().get_first_node_in_group("MAP")

func start_game(player_nodes: Array[PlayerClass]) -> void:
	_session_generation += 1
	players = player_nodes
	player_num = players.size()
	if player_num == 0:
		push_error("TurnManager.start_game: 至少需要一名玩家。")
		return
	now_turn = 0
	_turn_epoch = 0
	_ending_turn = false
	now_player_index = 0
	next_player_index = getNextPlayer(now_player_index)
	GameOn = true
	_last_game_result = null
	modal_resolution_depth = 0
	_modal_resolution_token += 1
	_modal_leases.clear()
	_legacy_modal_stack.clear()
	movement_lock_active = false
	_movement_resume_time = 0.0
	_modal_resume_time = 0.0
	_modal_resume_phase = TurnPhase.BEGIN
	_modal_resume_session_generation = -1
	_modal_resume_turn_epoch = -1
	get_tree().paused = false
	InteractionCoordinator.reset_session(false)
	# 牌库由 Autoload 首次启动以及 GameManager.reset_session() 为下一局预先重建。
	# 不在主场景已经显示后再次同步加载全部卡牌资源，避免首帧 HUD 被阻塞数秒。
	ProfessionManager.reset_for_new_game(players)
	EventManager.reset_for_new_game()
	FoodManager.reset_for_new_game(players)
	if has_node("/root/MarketManager"):
		MarketManager.reset_for_new_game()
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null and achievement_manager.has_method("reset_for_new_game"):
		achievement_manager.call("reset_for_new_game", players)
	ProfessionManager.apply_starting_bonuses()
	now_turn_start()

func now_turn_start() -> void:
	if not GameOn:
		return
	_turn_epoch += 1
	now_turn += 1
	turn_start.emit(now_player_index)
	# 引爆状态机的第一环
	change_phase(TurnPhase.BEGIN)
	if hud != null and hud.is_focus_mode:
		hud.update_camera_view(0.5)

func _on_next_phase_requested(target_phase: TurnPhase) -> void:
	# 所有 next_phase 信号最终都经过这里；旧调用点即使直接 emit，
	# 也不能绕过移动锁、事件/职业模态或回合结束事务。
	if not GameOn or movement_lock_active or modal_resolution_depth > 0 or _ending_turn:
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
	if not GameOn or modal_resolution_depth > 0 or movement_lock_active or _ending_turn:
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
	if not GameOn or modal_resolution_depth > 0 or movement_lock_active or _ending_turn:
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

func acquire_modal(owner: StringName, resume_policy: ModalResumePolicy = ModalResumePolicy.NO_RESUME) -> int:
	if modal_resolution_depth == 0:
		_modal_resolution_token += 1
		_modal_resume_phase = now_phase
		_modal_resume_time = turn_timer.time_left if not turn_timer.is_stopped() else 0.0
		_modal_resume_session_generation = _session_generation
		_modal_resume_turn_epoch = _turn_epoch
		_root_modal_policy = resume_policy
	else:
		_modal_resolution_token += 1
	var lease_id := _modal_resolution_token
	if modal_resolution_depth == 0:
		_root_modal_lease_id = lease_id
	_modal_leases[lease_id] = {
		"owner": owner,
		"session_generation": _session_generation,
		"turn_epoch": _turn_epoch,
		"resume_policy": resume_policy,
	}
	modal_resolution_depth += 1
	if not turn_timer.is_stopped():
		turn_timer.stop()
	modal_state_changed.emit(get_modal_snapshot())
	return lease_id


func release_modal(lease_id: int, resume_policy_override: int = -1) -> bool:
	if not _modal_leases.has(lease_id):
		return false
	var lease: Dictionary = _modal_leases[lease_id]
	if int(lease.get("session_generation", -1)) != _session_generation:
		return false
	if lease_id == _root_modal_lease_id and resume_policy_override >= 0:
		_root_modal_policy = resume_policy_override
	_modal_leases.erase(lease_id)
	_legacy_modal_stack.erase(lease_id)
	modal_resolution_depth = maxi(modal_resolution_depth - 1, 0)
	if modal_resolution_depth > 0:
		modal_state_changed.emit(get_modal_snapshot())
		return true
	var owns_resume_context := _modal_resume_session_generation == _session_generation and _modal_resume_turn_epoch == _turn_epoch
	# 嵌套租约只负责延长锁；恢复方式始终由根租约决定。
	var policy: int = _root_modal_policy
	if owns_resume_context and policy == ModalResumePolicy.RESET_ACTION and GameOn and now_phase == TurnPhase.ACTION:
		turn_timer.start(15.0)
	elif owns_resume_context and policy == ModalResumePolicy.RESUME_REMAINING and GameOn and now_phase == _modal_resume_phase and _modal_resume_time > 0.0:
		turn_timer.start(maxf(_modal_resume_time, 0.05))
	_clear_modal_resume_context()
	modal_state_changed.emit(get_modal_snapshot())
	return true


func invalidate_all_modals(reason: StringName = &"invalidated") -> void:
	if OS.is_debug_build() and modal_resolution_depth > 0:
		print_debug("清理模态租约：%s %s" % [reason, str(get_modal_snapshot())])
	_modal_leases.clear()
	_legacy_modal_stack.clear()
	modal_resolution_depth = 0
	_root_modal_lease_id = -1
	_modal_resolution_token += 1
	_clear_modal_resume_context()
	modal_state_changed.emit(get_modal_snapshot())


func get_modal_snapshot() -> Dictionary:
	var owners: Array[StringName] = []
	for lease: Dictionary in _modal_leases.values():
		owners.append(lease.get("owner", &"unknown"))
	return {
		"depth": modal_resolution_depth,
		"owners": owners,
		"resume_phase": _modal_resume_phase,
		"resume_time": _modal_resume_time,
		"session_generation": _modal_resume_session_generation,
		"turn_epoch": _modal_resume_turn_epoch,
	}


func begin_modal_resolution() -> int:
	var lease_id := acquire_modal(&"legacy", ModalResumePolicy.NO_RESUME)
	_legacy_modal_stack.append(lease_id)
	return lease_id

func end_modal_resolution(
	reset_action_timer: bool = true,
	resume_paused_timer: bool = false,
	resolution_token: int = -1
) -> bool:
	var lease_id := resolution_token
	if lease_id < 0:
		if _legacy_modal_stack.is_empty():
			return false
		lease_id = _legacy_modal_stack.back()
	var policy := ModalResumePolicy.NO_RESUME
	if reset_action_timer:
		policy = ModalResumePolicy.RESET_ACTION
	elif resume_paused_timer:
		policy = ModalResumePolicy.RESUME_REMAINING
	return release_modal(lease_id, policy)


func _clear_modal_resume_context() -> void:
	_modal_resume_time = 0.0
	_modal_resume_phase = TurnPhase.BEGIN
	_modal_resume_session_generation = -1
	_modal_resume_turn_epoch = -1
	_root_modal_policy = ModalResumePolicy.NO_RESUME
	_root_modal_lease_id = -1

func is_modal_resolution_active() -> bool:
	return modal_resolution_depth > 0

func get_session_generation() -> int:
	return _session_generation

func get_turn_epoch() -> int:
	return _turn_epoch

func now_turn_end() -> void:
	if not GameOn or _ending_turn:
		return
	_ending_turn = true
	var ending_session_generation := _session_generation
	var ending_turn_epoch := _turn_epoch
	# 职业封锁覆盖完整 END；当前玩家完成本回合后才递减。
	# 因而“孤注一掷”在当前 ACTION 触发时，当前回合正好计作第一个受影响回合。
	if now_player_index >= 0 and now_player_index < players.size():
		ProfessionManager.on_player_turn_finished(players[now_player_index])
	# 淘汰只能在完整回合结束、即将交接玩家的这一刻判断。
	# 移动或行动中精力为 0 的玩家仍可继续 ACTION 并使用食物恢复。
	if now_player_index >= 0 and now_player_index < players.size():
		await players[now_player_index].resolve_turn_end_elimination()
	# 返回主菜单并快速开始新局时，旧局的 END 协程不得继续操作新局状态。
	if ending_session_generation != _session_generation or ending_turn_epoch != _turn_epoch:
		if ending_session_generation == _session_generation:
			_ending_turn = false
		return
	if not GameOn:
		_ending_turn = false
		return
	assert_runtime_quiescent("回合 %d 交接" % now_turn)
	if now_player_index >= 0 and now_player_index < players.size():
		turn_completed.emit(players[now_player_index], now_turn)
	# 淘汰结算完成后再同时检查两项胜利条件，避免死亡回调抢先结束游戏。
	var end_reason: int = get_current_end_reason()
	if end_reason != NO_END_REASON:
		_ending_turn = false
		finish_game(end_reason)
		return
	var next_alive_index: int = getNextPlayer(now_player_index)
	if next_alive_index < 0:
		# 正常游戏不会进入这里；所有玩家均淘汰时，上面的淘汰条件必然已命中。
		push_error("TurnManager.now_turn_end: 没有可交接的存活玩家。")
		_ending_turn = false
		return
	now_player_index = next_alive_index
	next_player_index = getNextPlayer(now_player_index)
	_ending_turn = false
	now_turn_start()

func getNextPlayer(player_id: int) -> int:
	if player_num <= 0:
		return -1
	for offset in range(1, player_num + 1):
		var candidate_index: int = (player_id + offset) % player_num
		if players[candidate_index].alive:
			return candidate_index
	return -1

func assert_runtime_quiescent(context: String = "") -> bool:
	var interaction_quiet := InteractionCoordinator.assert_quiescent(context)
	var modal_quiet := modal_resolution_depth == 0 and _modal_leases.is_empty()
	var map_quiet := map == null or not map.is_section_choice_active()
	var event_quiet := not EventManager.resolving
	var quiet := interaction_quiet and modal_quiet and map_quiet and event_quiet and not movement_lock_active
	if not quiet and OS.is_debug_build():
		push_error("运行时未归零（%s）：interaction=%s modal=%s map_choice=%s event=%s movement=%s" % [
			context, str(get_active_interaction_snapshot()), str(get_modal_snapshot()), str(not map_quiet), str(not event_quiet), str(movement_lock_active)
		])
	return quiet

func get_active_interaction_snapshot() -> Dictionary:
	return InteractionCoordinator.get_active_snapshot()


## 兼容 PlayerClass 的淘汰通知入口。
## 正式胜利判断统一由 now_turn_end 在玩家完成隐藏和格子清理后执行。
func player_died(_player: PlayerClass) -> bool:
	return false

func has_player_reached_score_limit() -> bool:
	for player: PlayerClass in players:
		# 胜利判断和计分详情、最终排名统一读取同一份实时分解，
		# 避免缓存分数因刚完成的手牌或成就事务而滞后。
		var breakdown: Dictionary = ResourceManager.get_score_breakdown(player)
		player.current_score = int(breakdown.get("total_score", 0))
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

func get_current_end_reason() -> int:
	var reached_score_limit: bool = has_player_reached_score_limit()
	var reached_elimination_limit: bool = has_reached_elimination_limit()
	if reached_score_limit and reached_elimination_limit:
		return EndReason.BOTH
	if reached_score_limit:
		return EndReason.SCORE_LIMIT
	if reached_elimination_limit:
		return EndReason.ELIMINATION_LIMIT
	return NO_END_REASON

func get_game_result() -> GameResult:
	return _last_game_result

## 正式终局的唯一入口。重复调用返回同一个快照且不会重复发信号。
func finish_game(reason: int) -> GameResult:
	if _last_game_result != null:
		return _last_game_result
	if not GameOn:
		return null
	if not GameResult.is_valid_end_reason(reason):
		reason = get_current_end_reason()
	if not GameResult.is_valid_end_reason(reason):
		push_error("TurnManager.finish_game: 无效的结束原因。")
		return null

	_last_game_result = _build_game_result(reason)
	InteractionCoordinator.cancel_all(&"game_finished")
	GameOn = false
	_ending_turn = false
	turn_timer.stop()
	movement_lock_active = false
	_movement_resume_time = 0.0
	invalidate_all_modals(&"game_finished")
	get_tree().paused = true
	game_finished.emit(_last_game_result)
	return _last_game_result

## 保留旧入口供现有调用兼容；新代码应传入明确原因调用 finish_game。
func game_over(reason: int = NO_END_REASON) -> GameResult:
	if reason == NO_END_REASON:
		reason = get_current_end_reason()
	return finish_game(reason)

func reset_session() -> void:
	_session_generation += 1
	InteractionCoordinator.reset_session()
	turn_timer.stop()
	players.clear()
	player_num = 0
	now_turn = 0
	_turn_epoch = 0
	_ending_turn = false
	now_phase = TurnPhase.BEGIN
	now_player_index = 0
	next_player_index = 0
	GameOn = false
	invalidate_all_modals(&"session_reset")
	movement_lock_active = false
	_movement_resume_time = 0.0
	_last_game_result = null
	ProfessionManager.reset_session()
	map = null
	hud = null
	if get_tree() != null:
		get_tree().paused = false

func _build_game_result(reason: int) -> GameResult:
	var ranked_players: Array[Dictionary] = []
	for original_order: int in players.size():
		var player: PlayerClass = players[original_order]
		var breakdown: Dictionary = ResourceManager.get_score_breakdown(player)
		var total_score: int = int(breakdown.get("total_score", player.current_score))
		player.current_score = total_score
		ranked_players.append({
			"player": player,
			"breakdown": breakdown,
			"score": total_score,
			"player_index": player.player_index,
			"original_order": original_order,
		})
	ranked_players.sort_custom(_ranked_player_precedes)

	var entries: Array[GameResultEntry] = []
	var previous_score: int = 0
	var previous_rank: int = 0
	for sorted_index: int in ranked_players.size():
		var candidate: Dictionary = ranked_players[sorted_index]
		var score: int = int(candidate["score"])
		var rank: int = sorted_index + 1
		if sorted_index > 0 and score == previous_score:
			rank = previous_rank
		var entry := GameResultEntry.new(
			candidate["player"] as PlayerClass,
			candidate["breakdown"] as Dictionary,
			rank,
			rank == 1
		)
		entries.append(entry)
		previous_score = score
		previous_rank = rank
	return GameResult.new(reason, now_turn, entries)

func _ranked_player_precedes(first: Dictionary, second: Dictionary) -> bool:
	var first_score: int = int(first["score"])
	var second_score: int = int(second["score"])
	if first_score != second_score:
		return first_score > second_score
	var first_player_index: int = int(first["player_index"])
	var second_player_index: int = int(second["player_index"])
	if first_player_index != second_player_index:
		return first_player_index < second_player_index
	return int(first["original_order"]) < int(second["original_order"])
