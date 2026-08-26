extends GutTest

var _source: PlayerClass
var _target: PlayerClass
var _third: PlayerClass
var _turn_backup: Dictionary

func before_each() -> void:
	_turn_backup = {
		"players": TurnManager.players.duplicate(), "game_on": TurnManager.GameOn,
		"index": TurnManager.now_player_index, "phase": TurnManager.now_phase,
		"turn": TurnManager.now_turn,
	}
	_source = _player("食客")
	_target = _player("目标")
	_third = _player("第三人")
	TurnManager.players.assign([_source, _target, _third])
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	TurnManager.now_turn = 1
	ProfessionManager.reset_for_new_game(TurnManager.players)
	EventManager.reset_for_new_game()
	EventManager.auto_resolve_choices = true
	MarketManager.reset_for_new_game()
	FoodManager.reset_for_new_game(TurnManager.players)

func after_each() -> void:
	EventManager.reset_for_new_game()
	MarketManager.reset_for_new_game()
	FoodManager.reset_for_new_game([])
	ProfessionManager.reset_for_new_game([])
	ResourceManager.reset_for_new_game()
	TurnManager.players.assign(_turn_backup["players"])
	TurnManager.GameOn = bool(_turn_backup["game_on"])
	TurnManager.now_player_index = int(_turn_backup["index"])
	TurnManager.now_phase = int(_turn_backup["phase"])
	TurnManager.now_turn = int(_turn_backup["turn"])
	_source.free()
	_target.free()
	_third.free()

func test_full_energy_food_is_consumed_counted_and_recycled() -> void:
	_source.current_energy = 12
	var card := _food(&"dong_po_bing", 食物牌.FoodType.省级)
	_source.食物牌手牌.append(card)
	var result: FoodResolutionResult = await FoodManager.consume_food(_source, card)
	assert_true(result.success)
	assert_eq(_source.current_energy, 12)
	assert_eq(_source.food_used_count_this_turn, 1)
	assert_true(ResourceManager.食物牌库.has(card))
	ResourceManager.食物牌库.erase(card)

func test_public_mandatory_cost_and_permanent_duplicate_are_disabled() -> void:
	var qian := _food(&"qian_zhang_kou_rou", 食物牌.FoodType.省级)
	_source.食物牌手牌.append(qian)
	_source.current_energy = 0
	assert_false(FoodManager.get_use_check(_source, qian).allowed)
	_source.食物牌手牌.clear()
	var permanent := _food(&"wu_xue_fo_shou_shan_yao", 食物牌.FoodType.省级)
	assert_true(await FoodManager._resolve_effect(_source, permanent, FoodManager._session_token))
	_source.食物牌手牌.append(permanent)
	assert_false(FoodManager.get_use_check(_source, permanent).allowed)
	_source.食物牌手牌.clear()

func test_movement_additions_then_single_double_and_shared_discount_pool() -> void:
	await FoodManager._resolve_effect(_source, _food(&"wu_xue_fo_shou_shan_yao", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"tu_jia_tai_ge_zi", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"shang_xiang_feng_gan_ji", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"tu_jia_la_rou", 食物牌.FoodType.省级), FoodManager._session_token)
	assert_eq(FoodManager.adjust_movement_steps(_source, 6), 22, "(6+1+4) 后最多翻倍一次")
	await FoodManager._resolve_effect(_source, _food(&"du_jia_ji", 食物牌.FoodType.省级), FoodManager._session_token)
	assert_false(FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING))
	assert_eq(FoodManager.commit_movement_cost(_source, 3), 0)
	assert_eq(FoodManager.commit_movement_cost(_source, 3), 2, "分段移动共用4点池")

func test_skipped_moving_consumes_one_fifo_marker_and_preserves_buffs() -> void:
	await FoodManager._resolve_effect(_source, _food(&"huang_shi_gang_bing", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"tong_shan_bao_tuo", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"tu_jia_tai_ge_zi", 食物牌.FoodType.省级), FoodManager._session_token)
	var before := _source.current_energy
	assert_true(FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING))
	assert_eq(FoodManager.take_phase_message(_source), "【huang_shi_gang_bing】生效：跳过移动阶段，精力+2。")
	assert_eq(_source.current_energy, mini(before + 2, 12))
	assert_eq(FoodManager.get_state_snapshot(_source)[&"movement_step_bonuses"].size(), 1)
	assert_true(FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING))
	assert_true(FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING))
	assert_false(FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING))

func test_work_bonus_changes_normal_and_forced_work_basis() -> void:
	var tea := _food(&"tu_jia_you_cha_tang", 食物牌.FoodType.国家级)
	assert_true(await FoodManager._resolve_effect(_source, tea, FoodManager._session_token))
	assert_eq(FoodManager.adjust_work_income(_source, 250), 500)
	assert_eq(FoodManager.get_work_income_effect_message(_source), "【tu_jia_you_cha_tang】生效：本次打工工资+250。")
	assert_true(await FoodManager._resolve_effect(_source, tea, FoodManager._session_token), "直接效果调用保持幂等且不报错")
	assert_eq(FoodManager.adjust_work_income(_source, 250), 500)


func test_mao_zui_lu_ji_uses_partial_payment_without_blocking_energy_gain() -> void:
	_source.current_money = 0
	_target.current_money = 60
	_third.current_money = 0
	_source.current_energy = 5
	_target.current_energy = 5
	_third.current_energy = 5
	var card := _food(&"mao_zui_lu_ji", 食物牌.FoodType.省级)
	card.card_name = "毛嘴卤鸡"
	assert_true(await FoodManager._resolve_effect(_source, card, FoodManager._session_token))
	assert_eq(_source.current_money, 60)
	assert_eq(_target.current_money, 0)
	assert_eq(_third.current_money, 0)
	assert_eq([_source.current_energy, _target.current_energy, _third.current_energy], [6, 6, 6])


func test_delayed_begin_recovery_and_movement_modifiers_report_their_sources() -> void:
	await FoodManager._resolve_effect(_source, _food(&"pi_tiao_shan_yu", 食物牌.FoodType.省级), FoodManager._session_token)
	FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.BEGIN)
	assert_string_contains(FoodManager.take_phase_message(_source), "【pi_tiao_shan_yu】生效：回合开始精力+1。")

	await FoodManager._resolve_effect(_source, _food(&"du_jia_ji", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"tu_jia_tai_ge_zi", 食物牌.FoodType.省级), FoodManager._session_token)
	await FoodManager._resolve_effect(_source, _food(&"shang_xiang_feng_gan_ji", 食物牌.FoodType.省级), FoodManager._session_token)
	FoodManager.on_phase_entered(_source, TurnManager.TurnPhase.MOVING)
	var message := FoodManager.take_phase_message(_source)
	assert_string_contains(message, "【du_jia_ji】生效：本移动阶段精力消耗最多-4。")
	assert_string_contains(message, "【tu_jia_tai_ge_zi】生效：本移动阶段步数+4。")
	assert_string_contains(message, "【shang_xiang_feng_gan_ji】生效：本移动阶段步数翻倍。")
func test_all_high_level_effects_have_a_deterministic_resolution_path() -> void:
	for card: 卡牌基类 in ResourceManager.食物牌库.duplicate():
		if not card is 食物牌 or (card as 食物牌).food_type == 食物牌.FoodType.市级:
			continue
		_prepare_effect_prerequisites()
		var result = await FoodManager._resolve_effect(_source, card as 食物牌, FoodManager._session_token)
		assert_true(result is bool, (card as 食物牌).card_name)

func _prepare_effect_prerequisites() -> void:
	_source.current_energy = 6
	_source.current_money = 500
	_target.current_energy = 6
	_target.current_money = 500
	_third.current_money = 500
	_source.非遗牌手牌.clear()
	_target.非遗牌手牌.clear()
	_source.事件牌手牌.clear()
	_source.非遗牌手牌.append(_feiyi("甲牌"))
	_target.非遗牌手牌.append(_feiyi("乙牌"))
	MarketManager.reset_for_new_game()
	MarketManager.deposit_card(_feiyi("研究所牌"), &"test")

func _player(display_name: String) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_name = display_name
	player.alive = true
	return player

func _food(id: StringName, level: 食物牌.FoodType) -> 食物牌:
	var card := 食物牌.new()
	card.food_id = id
	card.card_name = str(id)
	card.food_type = level
	card.cost = card.get_default_cost()
	return card

func _feiyi(display_name: String) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.category = 非遗牌.CardCategory.手工技艺
	return card
