extends GutTest

class TurnEndProbePlayer extends PlayerClass:
	var eliminate_at_turn_end: bool = false
	var turn_end_resolution_count: int = 0

	func _ready() -> void:
		pass

	func resolve_turn_end_elimination() -> bool:
		turn_end_resolution_count += 1
		if eliminate_at_turn_end:
			alive = false
		return false

var _players_backup: Array[PlayerClass] = []
var _game_on_backup: bool = false
var _phase_backup: TurnManager.TurnPhase = TurnManager.TurnPhase.BEGIN
var _turn_backup: int = 0
var _player_index_backup: int = 0
var _next_player_index_backup: int = 0
var _player_num_backup: int = 0
var _hud_backup: HUD = null
var _map_backup: MAP = null
var _result_backup: GameResult = null
var _paused_backup: bool = false
var _player_data_backup: Array = []
var _created_players: Array[PlayerClass] = []

func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_turn_backup = TurnManager.now_turn
	_player_index_backup = TurnManager.now_player_index
	_next_player_index_backup = TurnManager.next_player_index
	_player_num_backup = TurnManager.player_num
	_hud_backup = TurnManager.hud
	_map_backup = TurnManager.map
	_result_backup = TurnManager._last_game_result
	_paused_backup = get_tree().paused
	_player_data_backup = GameManager.player_data.duplicate(true)

	get_tree().paused = false
	TurnManager.turn_timer.stop()
	TurnManager.players.clear()
	TurnManager.player_num = 0
	TurnManager.now_turn = 0
	TurnManager.now_player_index = 0
	TurnManager.next_player_index = 0
	TurnManager.GameOn = false
	TurnManager.modal_resolution_depth = 0
	TurnManager.movement_lock_active = false
	TurnManager._last_game_result = null
	TurnManager.hud = null
	TurnManager.map = null

func after_each() -> void:
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	for player: PlayerClass in _created_players:
		if is_instance_valid(player):
			player.free()
	_created_players.clear()

	TurnManager.players.assign(_players_backup)
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.now_turn = _turn_backup
	TurnManager.now_player_index = _player_index_backup
	TurnManager.next_player_index = _next_player_index_backup
	TurnManager.player_num = _player_num_backup
	TurnManager.hud = _hud_backup
	TurnManager.map = _map_backup
	TurnManager._last_game_result = _result_backup
	GameManager.player_data = _player_data_backup.duplicate(true)
	get_tree().paused = _paused_backup

func test_result_uses_stable_competition_ranking_and_includes_eliminated_players() -> void:
	var third_place := _make_scored_player("P1", 0, 7, true)
	var first_winner := _make_scored_player("P2", 1, 12, true)
	var second_winner := _make_scored_player("P3", 2, 12, false)
	TurnManager.players.assign([third_place, first_winner, second_winner])
	TurnManager.player_num = 3
	TurnManager.now_turn = 9
	TurnManager.GameOn = true
	watch_signals(TurnManager)

	var result: GameResult = TurnManager.finish_game(TurnManager.EndReason.SCORE_LIMIT)

	assert_not_null(result)
	assert_eq(result.end_reason, GameResult.EndReason.SCORE_LIMIT)
	assert_eq(result.turn_number, 9)
	assert_eq(result.entries.size(), 3)
	assert_eq(result.entries.map(func(entry: GameResultEntry) -> String: return entry.player_name), ["P2", "P3", "P1"])
	assert_eq(result.entries.map(func(entry: GameResultEntry) -> int: return entry.rank), [1, 1, 3])
	assert_eq(result.winners.size(), 2)
	assert_true(result.entries[1].is_winner)
	assert_false(result.entries[1].alive, "已淘汰玩家仍应保留在排名和并列冠军快照中")
	assert_signal_emit_count(TurnManager, "game_finished", 1)
	assert_true(get_tree().paused)

	var same_result: GameResult = TurnManager.finish_game(TurnManager.EndReason.BOTH)
	assert_same(same_result, result, "重复 finish_game 必须返回第一次生成的快照")
	assert_signal_emit_count(TurnManager, "game_finished", 1)

func test_reaching_twenty_triggers_settlement_but_does_not_designate_the_champion() -> void:
	var trigger_player := _make_scored_player("达到20分", 0, 20, true)
	var actual_winner := _make_scored_player("最终25分", 1, 25, true)
	TurnManager.players.assign([trigger_player, actual_winner])
	TurnManager.player_num = 2
	TurnManager.GameOn = true
	var result := TurnManager.finish_game(TurnManager.EndReason.SCORE_LIMIT)
	assert_eq(result.entries[0].player_name, "最终25分")
	assert_true(result.entries[0].is_winner)
	assert_eq(result.entries[1].player_name, "达到20分")
	assert_false(result.entries[1].is_winner)

func test_result_arrays_and_score_breakdowns_are_snapshot_copies() -> void:
	var player := _make_scored_player("快照玩家", 0, 8, true)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.GameOn = true
	var result: GameResult = TurnManager.finish_game(TurnManager.EndReason.SCORE_LIMIT)
	var entry: GameResultEntry = result.entries[0]

	var copied_entries: Array[GameResultEntry] = result.entries
	copied_entries.clear()
	var copied_breakdown: Dictionary = entry.score_breakdown
	copied_breakdown["total_score"] = 999
	player.alive = false
	player.current_score = 999

	assert_eq(result.entries.size(), 1)
	assert_eq(entry.total_score, 8)
	assert_eq(int(entry.score_breakdown["total_score"]), 8)
	assert_true(entry.alive)

func test_achievement_metadata_is_an_immutable_result_snapshot() -> void:
	var player := _make_scored_player("成就快照玩家", 0, 8, true)
	var source_achievement := 成就牌.new()
	source_achievement.achievement_id = &"snapshot_test"
	source_achievement.card_name = "原成就名"
	source_achievement.score_value = 3
	var breakdown := ResourceManager.get_score_breakdown(player)
	breakdown["achievements"] = [source_achievement]
	breakdown["achievement_score"] = 3
	breakdown["total_score"] = 11
	var entry := GameResultEntry.new(player, breakdown, 1, true)
	var result_entries: Array[GameResultEntry] = [entry]
	var result := GameResult.new(GameResult.EndReason.SCORE_LIMIT, 1, result_entries)

	source_achievement.card_name = "被修改的名称"
	source_achievement.score_value = 99
	var first_read: Array = result.entries[0].achievements
	first_read[0]["card_name"] = "外部篡改"
	var second_read: Array = result.entries[0].achievements

	assert_eq(second_read[0]["card_name"], "原成就名")
	assert_eq(second_read[0]["score_value"], 3)
	assert_eq(result.entries[0].total_score, 11)

func test_end_reason_reports_score_elimination_and_both_without_changing_two_player_limit() -> void:
	var first := _make_scored_player("P1", 0, 20, true)
	var second := _make_scored_player("P2", 1, 0, false)
	TurnManager.players.assign([first, second])
	TurnManager.player_num = 2

	assert_eq(TurnManager.get_current_end_reason(), TurnManager.EndReason.SCORE_LIMIT)
	var score_card: 非遗牌 = first.非遗牌手牌[0]
	first.非遗牌手牌.clear()
	first.current_score = 0
	assert_eq(TurnManager.get_current_end_reason(), TurnManager.NO_END_REASON, "2人局只淘汰1人不得结束")
	first.alive = false
	assert_eq(TurnManager.get_current_end_reason(), TurnManager.EndReason.ELIMINATION_LIMIT)
	first.非遗牌手牌.append(score_card)
	assert_eq(TurnManager.get_current_end_reason(), TurnManager.EndReason.BOTH)

func test_player_died_notification_cannot_finish_before_turn_end_coordinator() -> void:
	var first := _make_scored_player("P1", 0, 0, false)
	var second := _make_scored_player("P2", 1, 0, false)
	TurnManager.players.assign([first, second])
	TurnManager.player_num = 2
	TurnManager.GameOn = true
	watch_signals(TurnManager)

	assert_false(TurnManager.player_died(first))
	assert_null(TurnManager.get_game_result())
	assert_true(TurnManager.GameOn)
	assert_signal_not_emitted(TurnManager, "game_finished")

func test_turn_end_resolves_elimination_before_simultaneous_victory_check() -> void:
	var current := TurnEndProbePlayer.new()
	current.player_name = "当前玩家"
	current.player_index = 0
	current.eliminate_at_turn_end = true
	current.current_score = 20
	current.非遗牌手牌.append(_make_score_card(20))
	var already_eliminated := _make_scored_player("已淘汰玩家", 1, 0, false)
	_created_players.append(current)
	TurnManager.players.assign([current, already_eliminated])
	TurnManager.player_num = 2
	TurnManager.now_player_index = 0
	TurnManager.now_turn = 4
	TurnManager.GameOn = true
	watch_signals(TurnManager)

	assert_null(TurnManager.get_game_result(), "达到20分也必须等完整回合结束")
	await TurnManager.now_turn_end()

	assert_eq(current.turn_end_resolution_count, 1)
	assert_false(current.alive)
	assert_not_null(TurnManager.get_game_result())
	assert_eq(TurnManager.get_game_result().end_reason, GameResult.EndReason.BOTH)
	assert_signal_emit_count(TurnManager, "game_finished", 1)

func test_game_manager_reset_session_unpauses_and_clears_runtime_references() -> void:
	var player := _make_scored_player("待清理玩家", 0, 0, true)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.GameOn = true
	GameManager.player_data = [{"name": "待清理玩家"}]
	get_tree().paused = true

	GameManager.reset_session()

	assert_false(get_tree().paused)
	assert_false(TurnManager.GameOn)
	assert_true(TurnManager.players.is_empty())
	assert_null(TurnManager.hud)
	assert_null(TurnManager.map)
	assert_true(GameManager.player_data.is_empty())

func _make_scored_player(display_name: String, index: int, score: int, is_alive: bool) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_name = display_name
	player.player_index = index
	player.alive = is_alive
	player.current_score = score
	if score > 0:
		player.非遗牌手牌.append(_make_score_card(score))
	_created_players.append(player)
	return player

func _make_score_card(score: int) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = "测试计分牌%d" % score
	card.category = 非遗牌.CardCategory.戏曲表演
	card.base_score = score
	card.region = 非遗牌.REGION.鄂州
	return card
