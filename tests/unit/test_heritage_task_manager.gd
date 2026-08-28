extends GutTest

const TEST_DISCOVERY_PATH: String = "user://test_heritage_task_manager.cfg"
const NATIONAL_CARD_PATHS: Dictionary[StringName, String] = {
	&"ezhou_diaohua_jianzhi": "res://Cards/非遗牌/鄂州/鄂州雕花剪纸.tres",
	&"huangmei_xi": "res://Cards/非遗牌/黄冈/黄梅戏.tres",
	&"xisai_shenzhou_hui": "res://Cards/非遗牌/黄石/西塞神舟会.tres",
	&"xia_lian_dan_shu": "res://Cards/非遗牌/荆门/夏氏炼丹术及其祖传秘方.tres",
	&"gu_pen_ge": "res://Cards/非遗牌/荆州/鼓盆歌.tres",
	&"yandi_shennong_chuanshuo": "res://Cards/非遗牌/神农架/炎帝神农传说.tres",
	&"tianmen_tang_su": "res://Cards/非遗牌/天门/天门糖塑.tres",
	&"han_ju": "res://Cards/非遗牌/武汉/汉剧.tres",
	&"jingzhou_hua_gu_xi": "res://Cards/非遗牌/仙桃/荆州花鼓戏.tres",
	&"ti_qin_xi": "res://Cards/非遗牌/咸宁/提琴戏.tres",
	&"laohekou_si_xian": "res://Cards/非遗牌/襄阳/老河口丝弦.tres",
	&"dong_yong_chuanshuo": "res://Cards/非遗牌/孝感/董永传说.tres",
	&"tujia_saye_erhe": "res://Cards/非遗牌/宜昌/土家族撒叶儿嗬.tres",
	&"xiabaoping_minjian_gushi": "res://Cards/非遗牌/宜昌/下堡坪民间故事.tres",
	&"xingshan_min_ge": "res://Cards/非遗牌/宜昌/兴山民歌.tres",
}

var _player: PlayerClass
var _other: PlayerClass
var _saved_game_on: bool
var _saved_phase: TurnManager.TurnPhase
var _saved_players: Array[PlayerClass]
var _saved_player_index: int
var _saved_session_generation: int
var _saved_turn_epoch: int
var _saved_region_totals: Dictionary
var _saved_category_totals: Dictionary


func before_each() -> void:
	_saved_game_on = TurnManager.GameOn
	_saved_phase = TurnManager.now_phase
	_saved_players.assign(TurnManager.players)
	_saved_player_index = TurnManager.now_player_index
	_saved_session_generation = TurnManager.get_session_generation()
	_saved_turn_epoch = TurnManager.get_turn_epoch()
	_saved_region_totals = ResourceManager.地区非遗牌上限字典.duplicate(true)
	_saved_category_totals = ResourceManager.类别非遗牌上限字典.duplicate(true)

	_player = PlayerClass.new()
	_player.player_name = "传承测试P1"
	_player.player_index = 0
	_player.current_energy = 6
	_player.alive = true
	_player.onTurn = true
	_other = PlayerClass.new()
	_other.player_name = "传承测试P2"
	_other.player_index = 1
	_other.current_energy = 6
	_other.alive = true
	_other.onTurn = false

	InteractionCoordinator.reset_session(false)
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	TurnManager._session_generation = _saved_session_generation + 100
	TurnManager._turn_epoch = 100
	TurnManager.players.assign([_player, _other])
	TurnManager.now_player_index = 0
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	var players: Array[PlayerClass] = [_player, _other]
	HeritageTaskManager.reload_definitions()
	HeritageTaskManager.reset_for_new_game(players)
	AchievementManager.reset_for_new_game(players)
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)


func after_each() -> void:
	EventManager.reset_for_new_game()
	HeritageTaskManager.reset_session()
	InteractionCoordinator.reset_session(false)
	AchievementManager.reset_for_new_game([])
	ResourceManager.地区非遗牌上限字典.assign(_saved_region_totals)
	ResourceManager.类别非遗牌上限字典.assign(_saved_category_totals)
	TurnManager.players.assign(_saved_players)
	TurnManager.now_player_index = _saved_player_index
	TurnManager.GameOn = _saved_game_on
	TurnManager.now_phase = _saved_phase
	TurnManager._session_generation = _saved_session_generation
	TurnManager._turn_epoch = _saved_turn_epoch
	DiscoveryManager.configure_storage_path(DiscoveryManager.DEFAULT_STORAGE_PATH)
	var test_path := ProjectSettings.globalize_path(TEST_DISCOVERY_PATH)
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(test_path)
	_player.free()
	_other.free()


func test_all_fifteen_national_cards_have_unique_task_definitions() -> void:
	assert_eq(NATIONAL_CARD_PATHS.size(), 15)
	var seen: Dictionary[StringName, bool] = {}
	for expected_id: StringName in NATIONAL_CARD_PATHS:
		var card := load(NATIONAL_CARD_PATHS[expected_id]) as 非遗牌
		assert_not_null(card, String(expected_id))
		assert_eq(card.category, 非遗牌.CardCategory.国家级非遗, String(expected_id))
		assert_eq(card.inheritance_task_id, expected_id, card.card_name)
		assert_false(seen.has(card.inheritance_task_id), "任务 ID 不得重复")
		seen[card.inheritance_task_id] = true
		var definition := HeritageTaskManager.get_definition(card)
		assert_not_null(definition, "缺少任务定义：%s" % expected_id)
		if definition != null:
			assert_eq(definition.task_id, expected_id)


func test_locked_national_card_is_excluded_from_base_and_region_combos_until_success() -> void:
	var national := _load_national(&"yandi_shennong_chuanshuo")
	_player.非遗牌手牌.append(national)
	for index: int in 4:
		var normal := 非遗牌.new()
		normal.region = national.region
		normal.category = 非遗牌.CardCategory.手工技艺
		normal.base_score = 1
		normal.card_name = "测试牌%d" % index
		_player.非遗牌手牌.append(normal)
	ResourceManager.地区非遗牌上限字典[national.region] = 99
	ResourceManager.类别非遗牌上限字典[非遗牌.CardCategory.手工技艺] = 99
	ResourceManager.类别非遗牌上限字典[非遗牌.CardCategory.国家级非遗] = 99

	var locked := ResourceManager.get_score_breakdown(_player)
	assert_eq(locked.base_score, 4)
	assert_eq(locked.regional_combo_score, 0)
	assert_eq(HeritageTaskManager.get_display_score(national), "?")
	assert_false(ResourceManager.get_effective_feiyi_cards(_player).has(national))

	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.success(national.inheritance_task_id)))
	var unlocked := ResourceManager.get_score_breakdown(_player)
	assert_eq(unlocked.base_score, 9)
	assert_eq(unlocked.regional_combo_score, 5)
	assert_eq(HeritageTaskManager.get_display_score(national), 5)
	assert_true(ResourceManager.get_effective_feiyi_cards(_player).has(national))


func test_failure_consumes_attempt_but_technical_error_refunds_and_rolls_back() -> void:
	var national := _load_national(&"han_ju")
	_player.非遗牌手牌.append(national)
	var first := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(first)
	assert_eq(_player.current_energy, 5)
	assert_true(HeritageTaskManager.finish_attempt(
		first,
		HeritageTaskResult.technical_error(national.inheritance_task_id, &"scene_failed", "测试异常")
	))
	assert_eq(first.state, HeritageTaskAttempt.State.ROLLED_BACK)
	assert_eq(_player.current_energy, 6)
	assert_true(HeritageTaskManager.get_attempt_check(_player, national).allowed)

	var retry := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(retry)
	assert_true(HeritageTaskManager.finish_attempt(retry, HeritageTaskResult.failure(national.inheritance_task_id)))
	assert_eq(_player.current_energy, 5)
	assert_false(HeritageTaskManager.get_attempt_check(_player, national).allowed)
	assert_eq(HeritageTaskManager.get_attempt_check(_player, national).reason, &"already_attempted_this_turn")
	assert_false(HeritageTaskManager.finish_attempt(retry, HeritageTaskResult.success(national.inheritance_task_id)))
	assert_false(HeritageTaskManager.is_inherited(national))


func test_attempt_requires_owners_action_and_allows_exactly_one_energy() -> void:
	var national := _load_national(&"xia_lian_dan_shu")
	_player.非遗牌手牌.append(national)
	_player.current_energy = 1

	assert_null(HeritageTaskManager.begin_attempt(_other, national), "非持有者不能挑战")
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	assert_null(HeritageTaskManager.begin_attempt(_player, national), "仅自己的行动阶段可挑战")
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION

	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_eq(_player.current_energy, 0, "精力恰好为1时允许支付至0")
	assert_true(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.failure(national.inheritance_task_id, &"test_failure", "火候失控")
	))
	assert_eq(_player.current_energy, 0, "普通失败不返还成本")


func test_active_attempt_rejects_double_start() -> void:
	var national := _load_national(&"dong_yong_chuanshuo")
	_player.非遗牌手牌.append(national)
	var first := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(first)
	assert_null(HeritageTaskManager.begin_attempt(_player, national), "同一次按钮连点只能登记一个事务")
	assert_eq(_player.current_energy, 5, "重复点击不能重复扣除精力")
	assert_true(HeritageTaskManager.abort_attempt(first, &"manual_abort"))


func test_stale_result_rolls_back_and_releases_interaction_without_unlocking() -> void:
	var national := _load_national(&"gu_pen_ge")
	_player.非遗牌手牌.append(national)
	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_eq(_player.current_energy, 5)

	TurnManager._turn_epoch += 1
	assert_false(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.success(national.inheritance_task_id)
	), "旧回合结果不能提交")
	await wait_process_frames(2)

	assert_false(HeritageTaskManager.is_inherited(national))
	assert_eq(attempt.state, HeritageTaskAttempt.State.ROLLED_BACK)
	assert_eq(_player.current_energy, 6, "跨回合结果按技术取消返还成本")
	assert_true(InteractionCoordinator.assert_quiescent("stale heritage result"))


func test_result_cannot_land_after_action_or_card_ownership_ends() -> void:
	var national := _load_national(&"gu_pen_ge")
	_player.非遗牌手牌.append(national)
	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_eq(_player.current_energy, 5)

	# Session and turn epochs are deliberately unchanged: the manager must also
	# guard the actual gameplay context, not merely those two counters.
	TurnManager.now_phase = TurnManager.TurnPhase.END
	assert_false(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.success(national.inheritance_task_id)
	))

	assert_false(HeritageTaskManager.is_inherited(national))
	assert_eq(attempt.state, HeritageTaskAttempt.State.ROLLED_BACK)
	assert_eq(_player.current_energy, 6)
	assert_true(InteractionCoordinator.assert_quiescent("heritage action ended"))


func test_invalid_task_result_is_treated_as_technical_error() -> void:
	var national := _load_national(&"gu_pen_ge")
	_player.非遗牌手牌.append(national)
	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)

	assert_true(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.success(&"another_task")
	))
	assert_false(HeritageTaskManager.is_inherited(national))
	assert_eq(attempt.state, HeritageTaskAttempt.State.ROLLED_BACK)
	assert_eq(_player.current_energy, 6, "非法返回值必须走技术回滚，不得留下卡死交互")
	assert_true(InteractionCoordinator.assert_quiescent("invalid heritage result"))


func test_lost_interaction_rolls_back_instead_of_leaving_an_active_attempt() -> void:
	var national := _load_national(&"gu_pen_ge")
	_player.非遗牌手牌.append(national)
	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_eq(_player.current_energy, 5)

	InteractionCoordinator.cancel_all(&"external_teardown")
	assert_false(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.success(national.inheritance_task_id)
	))

	assert_false(HeritageTaskManager.is_inherited(national))
	assert_eq(attempt.state, HeritageTaskAttempt.State.ROLLED_BACK)
	assert_eq(_player.current_energy, 6)
	assert_true(HeritageTaskManager.get_attempt_check(_player, national).allowed)
	assert_true(InteractionCoordinator.assert_quiescent("lost heritage interaction"))


func test_success_and_repeated_finish_are_idempotent() -> void:
	var national := _load_national(&"tianmen_tang_su")
	_player.非遗牌手牌.append(national)
	watch_signals(HeritageTaskManager)
	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	var success := HeritageTaskResult.success(national.inheritance_task_id)
	assert_true(HeritageTaskManager.finish_attempt(attempt, success))
	assert_true(HeritageTaskManager.is_inherited(national))
	assert_false(HeritageTaskManager.finish_attempt(attempt, success))
	assert_signal_emit_count(HeritageTaskManager, "inheritance_completed", 1)
	assert_signal_emit_count(HeritageTaskManager, "inheritance_state_changed", 1)
	assert_signal_emit_count(HeritageTaskManager, "attempt_finished", 1)
	assert_true(InteractionCoordinator.assert_quiescent("heritage success"))


func test_national_cards_cannot_transfer_or_swap() -> void:
	var national := _load_national(&"ti_qin_xi")
	var first_normal := 非遗牌.new()
	first_normal.card_name = "甲方普通牌"
	var second_normal := 非遗牌.new()
	second_normal.card_name = "乙方普通牌"
	_player.非遗牌手牌.assign([national, first_normal])
	_other.非遗牌手牌.assign([second_normal])

	assert_false(ResourceManager.transfer_feiyi_card(_player, _other, national))
	assert_false(ResourceManager.swap_feiyi_cards(_player, national, _other, second_normal))
	assert_true(_player.非遗牌手牌.has(national))
	assert_true(_player.非遗牌手牌.has(first_normal))
	assert_true(_other.非遗牌手牌.has(second_normal))


func test_locked_national_card_does_not_count_for_cultural_new_wind_until_success() -> void:
	var normal := 非遗牌.new()
	normal.card_name = "普通藏品"
	normal.category = 非遗牌.CardCategory.手工技艺
	var national := _load_national(&"han_ju")
	_player.非遗牌手牌.append(normal)
	_other.非遗牌手牌.append(national)
	_player.current_money = 500
	_other.current_money = 500

	await EventManager._event_wen_hua_xin_feng(_player)
	assert_eq(_player.current_money, 600, "只有有效牌数量最多者获得基础奖励")
	assert_eq(_other.current_money, 500, "未传承国家级牌不计数量，也不触发国家级奖励")

	_player.current_money = 500
	_other.current_money = 500
	_make_current_player(_other)
	var attempt := HeritageTaskManager.begin_attempt(_other, national)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.success(national.inheritance_task_id)))

	await EventManager._event_wen_hua_xin_feng(_player)
	assert_eq(_player.current_money, 600)
	assert_eq(_other.current_money, 700, "传承后恢复数量资格与国家级额外奖励")


func test_locked_national_card_does_not_receive_national_escort_until_success() -> void:
	var national := _load_national(&"ti_qin_xi")
	_player.非遗牌手牌.append(national)

	EventManager._event_guo_bao_hu_hang()
	assert_eq(EventManager.get_status_remaining(_player, &"free_move_phases"), 0)

	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.success(national.inheritance_task_id)))
	EventManager._event_guo_bao_hu_hang()
	assert_eq(EventManager.get_status_remaining(_player, &"free_move_phases"), 2)


func test_locked_shennongjia_national_card_does_not_complete_collection_until_success() -> void:
	var national := _load_national(&"yandi_shennong_chuanshuo")
	var normal := load("res://Cards/非遗牌/神农架/黑暗传.tres") as 非遗牌
	assert_not_null(normal)
	_player.非遗牌手牌.assign([normal, national])
	var progress: Dictionary = AchievementManager._progress_by_player[_player]
	progress[AchievementManager.PROGRESS_SHENNONGJIA_SCENERY] = \
		AchievementManager._required_shennongjia_scenery_ids.duplicate(true)

	AchievementManager.evaluate_collection_achievements(_player)
	var locked_progress := AchievementManager.get_progress(_player, AchievementManager.ID_YE_REN)
	assert_eq(locked_progress[&"feiyi_current"], 1)
	assert_eq(locked_progress[&"feiyi_target"], 2)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN))

	var attempt := HeritageTaskManager.begin_attempt(_player, national)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.success(national.inheritance_task_id)))
	var inherited_progress := AchievementManager.get_progress(_player, AchievementManager.ID_YE_REN)
	assert_eq(inherited_progress[&"feiyi_current"], 2)
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN), _player)


func _make_current_player(player: PlayerClass) -> void:
	for candidate: PlayerClass in TurnManager.players:
		candidate.onTurn = candidate == player
	TurnManager.now_player_index = TurnManager.players.find(player)


func _load_national(task_id: StringName) -> 非遗牌:
	return load(NATIONAL_CARD_PATHS[task_id]) as 非遗牌
