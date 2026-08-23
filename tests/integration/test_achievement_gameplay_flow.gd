extends GutTest

var _first: PlayerClass
var _second: PlayerClass
var _created_map: MAP = null
var _food_deck_backup: Array[卡牌基类] = []
var _event_deck_backup: Array[事件牌] = []
var _event_discard_backup: Array[事件牌] = []
var _players_backup: Array[PlayerClass] = []
var _turn_state_backup: Dictionary = {}
var _resource_hud_backup: HUD = null
var _event_hud_backup: HUD = null
var _event_overlay_backup: Control = null
var _paused_backup := false


func before_each() -> void:
	_food_deck_backup.assign(ResourceManager.食物牌库)
	_event_deck_backup.assign(ResourceManager.事件牌库)
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)
	_players_backup.assign(TurnManager.players)
	_turn_state_backup = {
		"player_num": TurnManager.player_num,
		"now_player_index": TurnManager.now_player_index,
		"next_player_index": TurnManager.next_player_index,
		"now_phase": TurnManager.now_phase,
		"now_turn": TurnManager.now_turn,
		"game_on": TurnManager.GameOn,
		"map": TurnManager.map,
		"hud": TurnManager.hud,
		"result": TurnManager._last_game_result,
	}
	_resource_hud_backup = ResourceManager.hud
	_event_hud_backup = EventManager.hud
	_event_overlay_backup = EventManager.event_overlay
	_paused_backup = get_tree().paused
	get_tree().paused = false
	TurnManager.turn_timer.stop()

	_first = PlayerClass.new()
	_first.player_name = "成就流程P1"
	_first.player_index = 0
	_second = PlayerClass.new()
	_second.player_name = "成就流程P2"
	_second.player_index = 1
	var players: Array[PlayerClass] = [_first, _second]
	AchievementManager.reset_for_new_game(players)
	TurnManager.players.assign(players)
	TurnManager.player_num = 2
	TurnManager.now_player_index = 0
	TurnManager.next_player_index = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.now_turn = 1
	TurnManager.GameOn = true
	TurnManager.modal_resolution_depth = 0
	TurnManager.movement_lock_active = false
	TurnManager._last_game_result = null
	TurnManager.map = null
	TurnManager.hud = null
	ResourceManager.hud = null
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)


func after_each() -> void:
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	if _created_map != null and is_instance_valid(_created_map):
		_created_map.free()
	_created_map = null
	AchievementManager.reset_for_new_game([])
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(_event_hud_backup, _event_overlay_backup)
	ResourceManager.食物牌库.assign(_food_deck_backup)
	ResourceManager.事件牌库.assign(_event_deck_backup)
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	ResourceManager.hud = _resource_hud_backup
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = int(_turn_state_backup["player_num"])
	TurnManager.now_player_index = int(_turn_state_backup["now_player_index"])
	TurnManager.next_player_index = int(_turn_state_backup["next_player_index"])
	TurnManager.now_phase = int(_turn_state_backup["now_phase"])
	TurnManager.now_turn = int(_turn_state_backup["now_turn"])
	TurnManager.GameOn = bool(_turn_state_backup["game_on"])
	TurnManager.map = _turn_state_backup["map"] as MAP
	TurnManager.hud = _turn_state_backup["hud"] as HUD
	TurnManager._last_game_result = _turn_state_backup["result"] as GameResult
	if is_instance_valid(_first):
		_first.free()
	if is_instance_valid(_second):
		_second.free()
	get_tree().paused = _paused_backup


func test_food_counts_only_after_a_successful_consume_even_at_full_energy() -> void:
	_first.current_energy = _first.max_energy
	var full_energy_food := _make_food("满精力也可享用")
	_first.食物牌手牌.append(full_energy_food)
	assert_true(ResourceManager.consume_food(_first, full_energy_food))
	assert_eq(_achievement_progress(_first, AchievementManager.ID_TAO_TIE), 1)
	assert_eq(_first.current_energy, _first.max_energy)

	var second_food := _make_food("本回合第二张")
	_first.食物牌手牌.append(second_food)
	assert_false(ResourceManager.consume_food(_first, second_food), "同一回合第二张食物必须使用失败")
	assert_eq(_achievement_progress(_first, AchievementManager.ID_TAO_TIE), 1)
	EventManager._discard_player_card(_first, second_food)
	assert_eq(_achievement_progress(_first, AchievementManager.ID_TAO_TIE), 1, "事件弃置不计入享用次数")

	var missing_food := _make_food("不在手牌")
	assert_false(ResourceManager.consume_food(_first, missing_food))
	assert_eq(_achievement_progress(_first, AchievementManager.ID_TAO_TIE), 1)


func test_event_progress_counts_public_resolution_once_but_not_empty_blocked_or_retained_reuse() -> void:
	var no_effect_card := load("res://Cards/事件牌/故地重游.tres") as 事件牌
	await EventManager.resolve_event(_first, no_effect_card)
	assert_eq(_achievement_progress(_first, AchievementManager.ID_XING_YUN_ER), 1, "有效事件即使无事发生也应计数")

	var retained_card := load("res://Cards/事件牌/畅行无阻.tres") as 事件牌
	await EventManager.resolve_event(_first, retained_card)
	assert_true(_first.事件牌手牌.has(retained_card))
	assert_eq(_achievement_progress(_first, AchievementManager.ID_XING_YUN_ER), 2)
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	await EventManager.play_retained_event(_first, retained_card)
	assert_eq(_achievement_progress(_first, AchievementManager.ID_XING_YUN_ER), 2, "保留牌之后使用不得重复计数")

	ResourceManager.事件牌库.clear()
	var event_section := MapSection.new()
	event_section.type = MapSection.SectionType.事件
	event_section.location_index = Vector3i(2, -2, 0)
	_first.last_normal_arrival_position = event_section.location_index
	await EventManager.trigger_arrival_event(_first, event_section, 1)
	event_section.free()
	assert_eq(_achievement_progress(_first, AchievementManager.ID_XING_YUN_ER), 2, "空牌库没有公开事件，不得计数")

	var blocked_card := load("res://Cards/事件牌/孤注一掷.tres") as 事件牌
	await EventManager.resolve_event(_first, blocked_card)
	assert_eq(_achievement_progress(_first, AchievementManager.ID_XING_YUN_ER), 2, "未实装依赖牌不是合法公开结算")


func test_normal_scenery_check_in_is_atomic_unique_and_rewards_three_only_once() -> void:
	var scenery := MapSection.new()
	scenery.type = MapSection.SectionType.风景
	scenery.region = MapSection.REGION.武汉
	scenery.location_index = Vector3i(3, -3, 0)
	_first.current_energy = 4
	assert_true(await ResourceManager.vis_scenery(_first, scenery))
	assert_eq(_first.current_energy, 7)
	assert_eq(_achievement_progress(_first, AchievementManager.ID_YOU_SHAN_WAN_SHUI), 1)
	assert_false(await ResourceManager.vis_scenery(_first, scenery))
	assert_eq(_first.current_energy, 7, "重复普通到达不得再次获得3点精力")
	scenery.free()


func test_scenery_events_register_without_ordinary_bonus_and_repeat_only_their_own_reward() -> void:
	var start := MapSection.new()
	start.location_index = Vector3i.ZERO
	start.position = Vector2.ZERO
	var scenery := MapSection.new()
	scenery.type = MapSection.SectionType.风景
	scenery.region = MapSection.REGION.武汉
	scenery.location_index = Vector3i(1, -1, 0)
	scenery.position = Vector2(100, 0)
	_created_map = MAP.new()
	_created_map.add_child(start)
	_created_map.add_child(scenery)
	_created_map.grid_map[start.location_index] = start
	_created_map.grid_map[scenery.location_index] = scenery
	_first.map = _created_map
	_first.now_pos = start.location_index
	TurnManager.map = _created_map

	_first.current_energy = 0
	await EventManager._play_you_mu_cheng_huai(_first)
	assert_eq(_first.current_energy, 5, "游目骋怀只能执行牌面+5，不叠加普通+3")
	assert_eq(_achievement_progress(_first, AchievementManager.ID_YOU_SHAN_WAN_SHUI), 1)

	_first.current_energy = 0
	await EventManager._event_chen_jin_ti_yan(_first)
	assert_eq(_first.current_energy, 6, "沉浸体验重复到达仍执行牌面+6")
	assert_eq(_achievement_progress(_first, AchievementManager.ID_YOU_SHAN_WAN_SHUI), 1)
	assert_false(await ResourceManager.vis_scenery(_first, scenery))
	assert_eq(_first.current_energy, 6, "事件已登记的风景之后不能再领普通+3")


func test_achievement_score_refreshes_immediately_but_finishes_only_at_turn_end() -> void:
	var base_card := 非遗牌.new()
	base_card.card_name = "17分测试牌"
	base_card.category = 非遗牌.CardCategory.戏曲表演
	base_card.base_score = 17
	base_card.region = 非遗牌.REGION.鄂州
	assert_true(ResourceManager.add_feiyi_card(_first, base_card))
	for index: int in 5:
		var event_card := 事件牌.new()
		event_card.event_id = StringName("score_event_%d" % index)
		AchievementManager.record_gameplay_event(_first, event_card)
	assert_eq(_first.current_score, 20, "成就领取后应立即刷新统一总分")
	assert_true(TurnManager.GameOn)
	assert_null(TurnManager.get_game_result(), "达到20分不能在成就回调中提前结束")

	await TurnManager.now_turn_end()
	var result := TurnManager.get_game_result()
	assert_not_null(result)
	if result != null:
		assert_eq(result.end_reason, GameResult.EndReason.SCORE_LIMIT)


func test_group_energy_event_awards_the_first_resolved_player_not_the_trigger_player() -> void:
	# 复现实际观察：P2 触发群体事件，但存活玩家按 P1、P2 的顺序结算。
	TurnManager.now_player_index = 1
	_first.current_energy = 11
	_second.current_energy = 11
	await EventManager._event_mei_mei_yu_gong(_second)
	assert_eq(
		AchievementManager.get_achievement_owner(AchievementManager.ID_CHAO_YUE_REN_LEI),
		_first,
		"群体事件应由实际最先达到12点精力的玩家领取，而不是默认归事件触发者"
	)
	assert_true(AchievementManager.get_owned_achievements(_second).is_empty())


func test_upgrade_destroys_an_eliminated_players_tao_tie_and_refreshes_both_scores() -> void:
	_record_food_progress(_first, 6)
	assert_eq(_first.current_score, 2)
	_first.alive = false
	_record_food_progress(_second, 12)
	assert_eq(AchievementManager.get_achievement_state(AchievementManager.ID_TAO_TIE), AchievementManager.AvailabilityState.DESTROYED)
	assert_eq(_first.current_score, 0, "已淘汰原持有者也必须立即扣除饕餮2分")
	assert_eq(_second.current_score, 5)


func _make_food(display_name: String) -> 食物牌:
	var food := 食物牌.new()
	food.card_name = display_name
	food.food_type = 食物牌.FoodType.市级
	return food


func _record_food_progress(player: PlayerClass, count: int) -> void:
	var food := _make_food("进度测试食物")
	for _index: int in count:
		AchievementManager.record_food_consumed(player, food)


func _achievement_progress(player: PlayerClass, achievement_id: StringName) -> int:
	return int(AchievementManager.get_progress(player, achievement_id).get(&"current", 0))
