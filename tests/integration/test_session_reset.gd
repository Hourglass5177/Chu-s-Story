extends GutTest

class SessionHudProbe extends HUD:
	func _ready() -> void:
		pass

var _players_backup: Array[PlayerClass] = []
var _turn_state_backup: Dictionary = {}
var _player_data_backup: Array = []
var _event_hud_backup: HUD = null
var _event_overlay_backup: Control = null
var _resource_hud_backup: HUD = null
var _paused_backup := false
var _created_nodes: Array[Node] = []


func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_turn_state_backup = {
		"player_num": TurnManager.player_num,
		"now_player_index": TurnManager.now_player_index,
		"next_player_index": TurnManager.next_player_index,
		"now_phase": TurnManager.now_phase,
		"now_turn": TurnManager.now_turn,
		"game_on": TurnManager.GameOn,
		"hud": TurnManager.hud,
		"map": TurnManager.map,
		"result": TurnManager._last_game_result,
	}
	_player_data_backup = GameManager.player_data.duplicate(true)
	_event_hud_backup = EventManager.hud
	_event_overlay_backup = EventManager.event_overlay
	_resource_hud_backup = ResourceManager.hud
	_paused_backup = get_tree().paused
	get_tree().paused = false
	GameManager.reset_session()


func after_each() -> void:
	get_tree().paused = false
	GameManager.reset_session()
	for node: Node in _created_nodes:
		if is_instance_valid(node):
			node.free()
	_created_nodes.clear()
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = int(_turn_state_backup["player_num"])
	TurnManager.now_player_index = int(_turn_state_backup["now_player_index"])
	TurnManager.next_player_index = int(_turn_state_backup["next_player_index"])
	TurnManager.now_phase = int(_turn_state_backup["now_phase"])
	TurnManager.now_turn = int(_turn_state_backup["now_turn"])
	TurnManager.GameOn = bool(_turn_state_backup["game_on"])
	TurnManager.hud = _turn_state_backup["hud"] as HUD
	TurnManager.map = _turn_state_backup["map"] as MAP
	TurnManager._last_game_result = _turn_state_backup["result"] as GameResult
	GameManager.player_data = _player_data_backup.duplicate(true)
	EventManager.bind_runtime(_event_hud_backup, _event_overlay_backup)
	ResourceManager.hud = _resource_hud_backup
	get_tree().paused = _paused_backup


func test_two_consecutive_sessions_rebuild_clean_state_without_duplicate_signals() -> void:
	var clean_counts := _deck_counts()
	var prepared_deck_generation: int = ResourceManager._deck_build_generation
	assert_gt(int(clean_counts["feiyi"]), 0)
	assert_gt(int(clean_counts["food"]), 0)
	assert_eq(int(clean_counts["event"]), 40)
	var energy_connections_before := _connection_count(ResourceManager, &"energy_changed", AchievementManager._on_energy_changed)
	var hand_connections_before := _connection_count(ResourceManager, &"feiyi_hand_changed", AchievementManager._on_feiyi_hand_changed)
	var event_connections_before := _connection_count(EventManager, &"gameplay_event_triggered", AchievementManager._on_gameplay_event_triggered)

	var first_player := _new_player("第一局")
	var first_players: Array[PlayerClass] = [first_player]
	TurnManager.start_game(first_players)
	assert_eq(ResourceManager._deck_build_generation, prepared_deck_generation, "进入主场景时不得重复同步加载整副牌库")
	_dirty_every_runtime_system(first_player)
	GameManager.player_data = [{"name": "第一局"}]
	GameManager.reset_session()
	assert_eq(ResourceManager._deck_build_generation, prepared_deck_generation + 1, "会话清理应只重建一次下一局牌库")
	_assert_clean_session(clean_counts, first_player)

	var second_player := _new_player("第二局")
	var second_players: Array[PlayerClass] = [second_player]
	TurnManager.start_game(second_players)
	assert_eq(ResourceManager._deck_build_generation, prepared_deck_generation + 1, "已准备好的第二局不得在 start_game 再重建一次")
	assert_eq(_deck_counts(), clean_counts, "第二局开局不得重复加载牌资源")
	for card: 成就牌 in AchievementManager.get_all_achievements():
		assert_eq(AchievementManager.get_achievement_state(card.achievement_id), AchievementManager.AvailabilityState.AVAILABLE)
	assert_eq(_connection_count(ResourceManager, &"energy_changed", AchievementManager._on_energy_changed), energy_connections_before)
	assert_eq(_connection_count(ResourceManager, &"feiyi_hand_changed", AchievementManager._on_feiyi_hand_changed), hand_connections_before)
	assert_eq(_connection_count(EventManager, &"gameplay_event_triggered", AchievementManager._on_gameplay_event_triggered), event_connections_before)
	assert_eq(energy_connections_before, 1)
	assert_eq(hand_connections_before, 1)
	assert_eq(event_connections_before, 1)


func test_skipped_roll_phase_clears_the_previous_hud_dice_listener() -> void:
	var hud := SessionHudProbe.new()
	var player := _new_player("跳过掷骰测试")
	_created_nodes.append(hud)
	player.roll_dice.connect(hud._roll_dice_information, CONNECT_ONE_SHOT)
	hud._dice_signal_player = player
	assert_true(player.roll_dice.is_connected(hud._roll_dice_information))
	hud._clear_dice_information_connection()
	assert_false(player.roll_dice.is_connected(hud._roll_dice_information))
	# 下一回合重新进入掷骰阶段时必须可安全建立唯一监听。
	player.roll_dice.connect(hud._roll_dice_information, CONNECT_ONE_SHOT)
	assert_true(player.roll_dice.is_connected(hud._roll_dice_information))


func test_game_manager_reset_cancels_interaction_once_and_preserves_reason_for_waiter() -> void:
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	var ticket := InteractionCoordinator.begin_interaction(
		&"session_reset_probe", 15.0, Callable(), TurnManager.ModalResumePolicy.NO_RESUME, true
	)
	assert_not_null(ticket)
	GameManager.reset_session(false)
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.state, InteractionTicket.State.CANCELLED)
	assert_eq(result.cancel_reason, &"session_reset")
	assert_eq(TurnManager.get_modal_snapshot().depth, 0)


func _dirty_every_runtime_system(player: PlayerClass) -> void:
	var event_card: 事件牌 = ResourceManager.事件牌库.pop_back()
	ResourceManager.discard_event(event_card)
	ResourceManager.食物牌库.pop_back()
	var market_card := 非遗牌.new()
	market_card.card_name = "污染研究所"
	market_card.category = 非遗牌.CardCategory.戏曲表演
	MarketManager.deposit_card(market_card, &"test")
	EventManager.add_status(player, &"work_banned", 3)
	EventManager._request_sequence = 9
	EventManager.auto_resolve_choices = true
	player.current_energy = 12
	AchievementManager.record_energy_reached(player, 12)
	var hud := SessionHudProbe.new()
	var map := MAP.new()
	var overlay := Control.new()
	_created_nodes.append(hud)
	_created_nodes.append(map)
	_created_nodes.append(overlay)
	ResourceManager.hud = hud
	TurnManager.hud = hud
	TurnManager.map = map
	TurnManager.modal_resolution_depth = 2
	TurnManager.movement_lock_active = true
	EventManager.bind_runtime(hud, overlay)
	get_tree().paused = true


func _assert_clean_session(expected_counts: Dictionary, old_player: PlayerClass) -> void:
	assert_false(get_tree().paused)
	assert_eq(_deck_counts(), expected_counts)
	assert_true(ResourceManager.事件弃牌堆.is_empty())
	assert_null(ResourceManager.hud)
	assert_true(MarketManager.get_inventory().is_empty())
	assert_false(EventManager.resolving)
	assert_eq(EventManager._request_sequence, 0)
	assert_false(EventManager.auto_resolve_choices)
	assert_null(EventManager.hud)
	assert_null(EventManager.event_overlay)
	assert_eq(EventManager.get_status_remaining(old_player, &"work_banned"), 0)
	assert_false(TurnManager.GameOn)
	assert_true(TurnManager.players.is_empty())
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.movement_lock_active)
	assert_null(TurnManager.hud)
	assert_null(TurnManager.map)
	assert_true(GameManager.player_data.is_empty())
	assert_true(AchievementManager.get_progress(old_player, AchievementManager.ID_CHAO_YUE_REN_LEI).is_empty())
	for card: 成就牌 in AchievementManager.get_all_achievements():
		assert_eq(AchievementManager.get_achievement_state(card.achievement_id), AchievementManager.AvailabilityState.AVAILABLE)


func _deck_counts() -> Dictionary:
	var regional_counts: Dictionary = {}
	for region: MapSection.REGION in ResourceManager.地区非遗牌库:
		regional_counts[region] = ResourceManager.地区非遗牌库[region].size()
	return {
		"feiyi": ResourceManager.非遗牌库.size(),
		"food": ResourceManager.食物牌库.size(),
		"event": ResourceManager.事件牌库.size(),
		"regional": regional_counts,
		"category": ResourceManager.类别非遗牌上限字典.duplicate(true),
	}


func _connection_count(source: Object, signal_name: StringName, callback: Callable) -> int:
	var result := 0
	for connection: Dictionary in source.get_signal_connection_list(signal_name):
		if connection.get("callable") == callback:
			result += 1
	return result


func _new_player(display_name: String) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_name = display_name
	player.player_index = 0
	_created_nodes.append(player)
	return player
