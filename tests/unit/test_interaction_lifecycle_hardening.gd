extends GutTest


class PhaseProbePlayer extends PlayerClass:
	func _ready() -> void:
		pass


var _players_backup: Array[PlayerClass] = []
var _player_num_backup: int = 0
var _game_on_backup: bool = false
var _phase_backup: TurnManager.TurnPhase = TurnManager.TurnPhase.BEGIN
var _player_index_backup: int = 0
var _map_backup: MAP = null
var _turn_epoch_backup: int = 0
var _movement_lock_backup: bool = false
var _paused_backup: bool = false
var _runtime_profile_backup: GameManager.RuntimeProfile
var _seed_backup: int = 0
var _target_score_backup: int = SessionSetup.DEFAULT_TARGET_SCORE
var _elimination_presentation_done: bool = false


func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_player_num_backup = TurnManager.player_num
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_player_index_backup = TurnManager.now_player_index
	_map_backup = TurnManager.map
	_turn_epoch_backup = TurnManager._turn_epoch
	_movement_lock_backup = TurnManager.movement_lock_active
	_paused_backup = get_tree().paused
	_runtime_profile_backup = GameManager.runtime_profile
	_seed_backup = GameManager.get_session_seed()
	_target_score_backup = GameManager.get_target_score()

	get_tree().paused = false
	TurnManager.turn_timer.stop()
	InteractionCoordinator.reset_session(false)
	TurnManager.invalidate_all_modals(&"lifecycle_test_setup")
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	TurnManager.players.clear()
	TurnManager.player_num = 0
	TurnManager.GameOn = false
	TurnManager.now_phase = TurnManager.TurnPhase.BEGIN
	TurnManager.now_player_index = 0
	TurnManager.map = null
	TurnManager.movement_lock_active = false


func after_each() -> void:
	get_tree().paused = false
	InteractionCoordinator.reset_session(false)
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	TurnManager.invalidate_all_modals(&"lifecycle_test_teardown")
	TurnManager.turn_timer.stop()
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = _player_num_backup
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.now_player_index = _player_index_backup
	TurnManager.map = _map_backup
	TurnManager._turn_epoch = _turn_epoch_backup
	TurnManager.movement_lock_active = _movement_lock_backup
	GameManager.configure_session(_seed_backup, _runtime_profile_backup, _target_score_backup)
	get_tree().paused = _paused_backup


func test_rejected_event_request_does_not_replace_the_active_request() -> void:
	var overlay := Control.new()
	add_child_autofree(overlay)
	EventManager.bind_runtime(null, overlay)
	var first := EventChoiceRequest.new(null, "第一项", [true], PackedStringArray(["确认"]), false)
	var second := EventChoiceRequest.new(null, "第二项", [false], PackedStringArray(["确认"]), false)

	EventManager._request_choice(first)
	await get_tree().process_frame
	assert_true(EventManager._choice_waiting)
	assert_eq(EventManager._pending_request, first)
	assert_gt(first.request_id, 0)

	EventManager._request_choice(second)
	await get_tree().process_frame
	assert_true(EventManager._choice_waiting, "被拒绝的新请求不能结束既有请求")
	assert_eq(EventManager._pending_request, first, "被拒绝的新请求不能覆盖既有请求")
	assert_eq(InteractionCoordinator.get_active_snapshot().get("interaction_id", -1), first.request_id)

	assert_true(InteractionCoordinator.submit(first.request_id, true))
	await get_tree().process_frame
	assert_false(EventManager._choice_waiting)
	assert_null(EventManager._pending_request)
	assert_true(InteractionCoordinator.assert_quiescent("event request collision"))


func test_multiple_players_can_share_a_section_without_losing_occupancy() -> void:
	var map := autofree(MAP.new()) as MAP
	var origin := autofree(MapSection.new()) as MapSection
	var shared := autofree(MapSection.new()) as MapSection
	origin.location_index = Vector3i.ZERO
	shared.location_index = Vector3i(1, -1, 0)
	map.grid_map[origin.location_index] = origin
	map.grid_map[shared.location_index] = shared
	var first := autofree(PhaseProbePlayer.new()) as PhaseProbePlayer
	var second := autofree(PhaseProbePlayer.new()) as PhaseProbePlayer
	first.map = map
	second.map = map
	first.now_pos = origin.location_index
	second.now_pos = shared.location_index
	map.occupy_player_section(first, origin)
	map.occupy_player_section(second, shared)

	assert_true(EventManager._teleport_player(first, shared))
	assert_eq(shared.get_occupant_count(), 2)
	assert_true(shared.is_occupied)

	map.vacate_player_section(first, shared)
	assert_eq(shared.get_occupant_count(), 1)
	assert_true(shared.is_occupied, "一名玩家离开后，同格的另一名玩家仍应保持占用")

	# 旧场景和少量夹具仍会直接写布尔占用；清除该兼容标记不能留下幽灵占用。
	origin.clear_occupants()
	origin.is_occupied = true
	assert_true(origin.is_occupied)
	origin.is_occupied = false
	assert_false(origin.is_occupied)


func test_roll_delay_stops_while_paused_and_discards_a_stale_phase() -> void:
	GameManager.configure_session(20260828, GameManager.RuntimeProfile.NORMAL)
	var player := PhaseProbePlayer.new()
	# PlayerClass 的 @onready 引用属于真实场景契约；探针只补齐该最小节点，
	# 不运行正式 _ready，以免为一次异步阶段测试搭建整张地图。
	var score_badge := Node2D.new()
	score_badge.name = "ScoreBadge"
	var score_label := Label.new()
	score_label.name = "Score"
	score_badge.add_child(score_label)
	player.add_child(score_badge)
	add_child_autofree(player)
	player.onTurn = true
	player.alive = true
	player.maxMove = 0
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ROLL_DICE
	var session_generation := TurnManager.get_session_generation()
	var turn_epoch := TurnManager.get_turn_epoch()

	player._resolve_roll_dice_phase(session_generation, turn_epoch)
	get_tree().paused = true
	await get_tree().create_timer(1.1, true).timeout
	assert_eq(player.maxMove, 0, "暂停时掷骰延迟不得在后台完成")

	get_tree().paused = false
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	await get_tree().create_timer(1.1, true).timeout
	assert_eq(player.maxMove, 0, "旧阶段的异步掷骰结果不得写入当前回合")


func test_turn_handoff_cleanup_returns_runtime_to_quiescence() -> void:
	var map := autofree(MAP.new()) as MAP
	var option := autofree(MapSection.new()) as MapSection
	map.begin_section_choice(&"test", 91, [option])
	TurnManager.map = map
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.END
	TurnManager.movement_lock_active = true
	TurnManager.acquire_modal(&"leaked_modal", TurnManager.ModalResumePolicy.NO_RESUME)
	# 模拟旧 UI 遗留的无主 SceneTree 暂停；回合交接必须一并恢复。
	get_tree().paused = true
	var ticket := InteractionCoordinator.begin_interaction(&"leaked_interaction", 15.0)
	assert_not_null(ticket)
	EventManager.resolving = true
	assert_false(InteractionCoordinator.get_active_snapshot().is_empty())
	assert_gt(TurnManager.modal_resolution_depth, 0)
	assert_true(map.is_section_choice_active())

	assert_true(await TurnManager.recover_runtime_quiescence("turn handoff test"))
	assert_true(InteractionCoordinator.assert_quiescent("turn handoff test"))
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(map.is_section_choice_active())
	assert_false(EventManager.resolving)
	assert_false(TurnManager.movement_lock_active)
	assert_false(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("tree_pause_depth", -1)), 0)


func test_stale_elimination_presentation_cannot_unpause_a_new_modal() -> void:
	var player := PhaseProbePlayer.new()
	var score_badge := Node2D.new()
	score_badge.name = "ScoreBadge"
	var score_label := Label.new()
	score_label.name = "Score"
	score_badge.add_child(score_label)
	player.add_child(score_badge)
	add_child_autofree(player)
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.END
	_elimination_presentation_done = false
	var old_session: int = TurnManager.get_session_generation()
	var old_epoch: int = TurnManager.get_turn_epoch()
	_await_elimination_presentation(old_session, old_epoch, player)
	await get_tree().process_frame
	assert_true(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("tree_pause_depth", -1)), 1)

	# 作废旧局后立即开启一个新的暂停所有者。旧的 2.5 秒等待
	# 恢复时，不得释放这份新租约。
	TurnManager.reset_session()
	var new_lease := TurnManager.acquire_modal(
		&"new_session_pause",
		TurnManager.ModalResumePolicy.NO_RESUME,
		true
	)
	assert_true(get_tree().paused)
	await get_tree().create_timer(2.6, true).timeout
	assert_true(_elimination_presentation_done)
	assert_true(get_tree().paused, "旧淘汰协程不得解锁新局暂停")
	assert_eq(int(TurnManager.get_modal_snapshot().get("tree_pause_depth", -1)), 1)
	assert_true(TurnManager.release_modal(new_lease))
	assert_false(get_tree().paused)


func _await_elimination_presentation(
	session_generation: int,
	turn_epoch: int,
	player: PlayerClass
) -> void:
	await TurnManager._play_turn_end_elimination_presentation(
		session_generation,
		turn_epoch,
		player
	)
	_elimination_presentation_done = true
