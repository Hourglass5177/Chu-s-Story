extends Node

signal food_resolution_started(player: PlayerClass, card: 食物牌)
signal food_resolution_finished(player: PlayerClass, result: FoodResolutionResult)
signal food_state_changed(player: PlayerClass)

const CITY_ENERGY_GAIN: int = 2
const MAX_ENERGY: int = 12
const IMPLEMENTED_FOOD_IDS: Array[StringName] = [
	&"bai_yang_dou_gan", &"chi_bi_rou_gao", &"dong_po_bing", &"du_jia_ji", &"huang_shi_gang_bing",
	&"huang_zhou_dong_po_rou", &"qi_chun_suan_mi_fen", &"jing_men_san_zheng", &"ma_cheng_rou_gao", &"mao_zui_lu_ji",
	&"mian_yang_san_zheng", &"pi_tiao_shan_yu", &"qian_zhang_kou_rou", &"re_gan_mian", &"san_he_tang",
	&"san_you_shen_xian_ji", &"sha_wo_dou_si", &"shang_xiang_feng_gan_ji", &"shen_nong_jia_la_rou", &"sui_zhou_mi_zao",
	&"tian_men_san_zheng", &"tong_shan_bao_tuo", &"tu_jia_la_rou", &"tu_jia_tai_ge_zi", &"tuan_feng_gou_jiao",
	&"wu_xue_fo_shou_shan_yao", &"wu_xue_su_tang", &"xiang_yang_chan_ti", &"xiao_gan_mi_jiu", &"yi_chang_xiao_mian",
	&"ying_shan_yu_mian", &"you_men_da_xia", &"zao_yang_suan_jiang_mian", &"zhang_guan_he_zha", &"zhu_shan_lan_dou_fu",
	&"zhu_xi_wan_gao", &"fang_xian_huang_jiu", &"jing_zhou_yu_gao", &"qing_zhuan_cha", &"tu_jia_you_cha_tang",
]

var _session_token: int = 0
var _players: Array[PlayerClass] = []
var _state_by_player: Dictionary = {}
var _consuming_players: Dictionary = {}
var _phase_message_by_player: Dictionary = {}


func reset_for_new_game(players: Array[PlayerClass] = []) -> void:
	_session_token += 1
	_players.assign(players)
	_state_by_player.clear()
	_consuming_players.clear()
	_phase_message_by_player.clear()
	for player: PlayerClass in players:
		_state(player)


func reset_session() -> void:
	reset_for_new_game([])


func get_use_check(player: PlayerClass, card: 食物牌) -> FoodUseCheck:
	if player == null or card == null or not is_instance_valid(player):
		return FoodUseCheck.new(false, "无效的食物牌。")
	if not TurnManager.GameOn or not player.alive:
		return FoodUseCheck.new(false, "只能在自己的回合享用。")
	if TurnManager.now_phase != TurnManager.TurnPhase.ACTION:
		return FoodUseCheck.new(false, "只能在行动阶段享用。")
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size() \
			or TurnManager.players[TurnManager.now_player_index] != player:
		return FoodUseCheck.new(false, "只能由当前玩家享用。")
	if _consuming_players.has(player):
		return FoodUseCheck.new(false, "食物正在结算。")
	if player.food_used_count_this_turn >= ProfessionManager.get_food_use_limit(player):
		return FoodUseCheck.new(false, "本回合享用次数已用完。")
	if not player.食物牌手牌.has(card):
		return FoodUseCheck.new(false, "手牌中没有这张食物。")
	var id := _food_id(card)
	if id == &"qian_zhang_kou_rou":
		if player.current_energy < 1:
			return FoodUseCheck.new(false, "精力不足。")
		if MarketManager.get_inventory().is_empty():
			return FoodUseCheck.new(false, "研究所暂无藏品。")
	elif id == &"fang_xian_huang_jiu" and MarketManager.get_inventory().is_empty():
		return FoodUseCheck.new(false, "研究所暂无藏品。")
	elif id in [&"san_he_tang", &"zhu_shan_lan_dou_fu"]:
		if _non_national_feiyi(player).is_empty():
			return FoodUseCheck.new(false, "没有可交换的非遗牌。")
		if _alive_players().filter(func(candidate: PlayerClass) -> bool: return candidate != player).is_empty():
			return FoodUseCheck.new(false, "没有可选择的玩家。")
	elif id in [&"wu_xue_fo_shou_shan_yao", &"ying_shan_yu_mian", &"qing_zhuan_cha", &"tu_jia_you_cha_tang"] \
			and _has_permanent(player, id):
		return FoodUseCheck.new(false, "该永久效果已经生效。")
	return FoodUseCheck.new(true)


func consume_food(player: PlayerClass, card: 食物牌) -> FoodResolutionResult:
	var check := get_use_check(player, card)
	if not check.allowed:
		return FoodResolutionResult.new(false, false, check.reason, card)
	var token := _session_token
	_consuming_players[player] = true
	food_resolution_started.emit(player, card)
	if not ResourceManager.remove_food_card(player, card):
		_consuming_players.erase(player)
		return FoodResolutionResult.new(false, false, "食物牌已不在手牌中。", card)
	var applied: bool = await _resolve_effect(player, card, token)
	if token != _session_token or not is_instance_valid(player):
		return FoodResolutionResult.new(false, false, "结算已取消。", card)
	player.food_used_count_this_turn += 1
	var is_extra: bool = player.food_used_count_this_turn > ProfessionManager.BASE_FOOD_USE_LIMIT
	if is_extra and ProfessionManager.is_skill_enabled(player, PlayerClass.PlayerCharacter.美食博主):
		ProfessionManager.notify_skill_triggered(player, "额外享用食物")
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null:
		achievement_manager.call("record_food_consumed", player, card)
	ResourceManager.return_food_to_bottom(card)
	_consuming_players.erase(player)
	var message := "享用【%s】。" % card.card_name
	if not applied:
		message += "\n无事发生！"
	var result := FoodResolutionResult.new(true, applied, message, card)
	food_resolution_finished.emit(player, result)
	food_state_changed.emit(player)
	return result


func on_phase_entered(player: PlayerClass, phase: TurnManager.TurnPhase, phase_already_skipped: bool = false) -> bool:
	if player == null:
		return false
	_phase_message_by_player.erase(player)
	var state := _state(player)
	if phase == TurnManager.TurnPhase.BEGIN:
		_tick_begin_recovery(player, state)
		return false
	if phase != TurnManager.TurnPhase.MOVING:
		return false
	# 其他系统已经跳过本阶段时，食物的跳过标记、步数与减免全部保留。
	if phase_already_skipped:
		return false
	state[&"movement_discount_remaining"] = 0
	state[&"active_movement_turn"] = TurnManager.get_turn_epoch()
	var skips: Array = state[&"skip_moving"]
	if not skips.is_empty():
		var skip: Dictionary = skips.pop_front()
		var reward := int(skip.get("energy_reward", 0))
		var source_name := String(skip.get("source_name", "食物效果"))
		if reward > 0:
			ResourceManager.modify_energy(player, reward, "食物：%s" % source_name)
			_append_phase_message(player, "【%s】生效：跳过移动阶段，精力+%d。" % [source_name, reward])
		else:
			_append_phase_message(player, "【%s】生效：跳过移动阶段。" % source_name)
		food_state_changed.emit(player)
		return true
	var discount := int(state.get(&"permanent_movement_discount", 0))
	var discount_sources: Array[String] = []
	if discount > 0:
		var permanent_discount_source := _permanent_source(state, &"qing_zhuan_cha")
		if not permanent_discount_source.is_empty():
			discount_sources.append(permanent_discount_source)
	var discounts: Array = state[&"movement_discounts"]
	for entry: Dictionary in discounts:
		discount += int(entry.get("amount", 0))
		var source_name := String(entry.get("source_name", "食物效果"))
		if not discount_sources.has(source_name):
			discount_sources.append(source_name)
		entry["uses"] = int(entry.get("uses", 0)) - 1
	state[&"movement_discounts"] = discounts.filter(func(entry: Dictionary) -> bool: return int(entry.get("uses", 0)) > 0)
	state[&"movement_discount_remaining"] = maxi(discount, 0)
	if discount > 0:
		_append_phase_message(player, "【%s】生效：本移动阶段精力消耗最多-%d。" % ["、".join(discount_sources), discount])
	_consume_movement_step_effects(player, state)
	food_state_changed.emit(player)
	return false


func take_phase_message(player: PlayerClass) -> String:
	var message := String(_phase_message_by_player.get(player, ""))
	_phase_message_by_player.erase(player)
	return message


func _append_phase_message(player: PlayerClass, message: String) -> void:
	if player == null or message.is_empty():
		return
	var previous := String(_phase_message_by_player.get(player, ""))
	_phase_message_by_player[player] = message if previous.is_empty() else "%s\n%s" % [previous, message]


func adjust_movement_steps(player: PlayerClass, base_steps: int) -> int:
	var state := _state(player)
	var steps := maxi(base_steps, 0) + int(state.get(&"permanent_step_bonus", 0))
	var temporary_bonus := 0
	for entry: Dictionary in state[&"movement_step_bonuses"]:
		temporary_bonus += int(entry.get("amount", 0))
	steps += temporary_bonus
	if not state[&"movement_doubles"].is_empty():
		steps *= 2
		player.movement_multiplier_applied = true
	return steps


func get_preview_movement_discount(player: PlayerClass) -> int:
	var state := _state(player)
	if int(state.get(&"active_movement_turn", -1)) == TurnManager.get_turn_epoch():
		return int(state.get(&"movement_discount_remaining", 0))
	var discount := int(state.get(&"permanent_movement_discount", 0))
	for entry: Dictionary in state[&"movement_discounts"]:
		discount += int(entry.get("amount", 0))
	return maxi(discount, 0)


func preview_movement_cost(player: PlayerClass, raw_cost: int) -> int:
	return maxi(raw_cost - get_preview_movement_discount(player), 0)


func commit_movement_cost(player: PlayerClass, raw_cost: int) -> int:
	var state := _state(player)
	var remaining := int(state.get(&"movement_discount_remaining", 0))
	var used := mini(maxi(raw_cost, 0), maxi(remaining, 0))
	state[&"movement_discount_remaining"] = remaining - used
	food_state_changed.emit(player)
	return maxi(raw_cost - used, 0)


func adjust_work_income(player: PlayerClass, base_income: int) -> int:
	return maxi(base_income, 0) + int(_state(player).get(&"work_income_bonus", 0))


func get_work_income_effect_message(player: PlayerClass) -> String:
	var state := _state(player)
	var bonus := int(state.get(&"work_income_bonus", 0))
	if bonus <= 0:
		return ""
	var source_name := _permanent_source(state, &"tu_jia_you_cha_tang")
	if source_name.is_empty():
		source_name = "食物效果"
	return "【%s】生效：本次打工工资+%d。" % [source_name, bonus]


func get_state_snapshot(player: PlayerClass) -> Dictionary:
	return _state(player).duplicate(true)


func _resolve_effect(player: PlayerClass, card: 食物牌, token: int) -> bool:
	var id := _food_id(card)
	if card.food_type == 食物牌.FoodType.市级:
		ResourceManager.modify_energy(player, CITY_ENERGY_GAIN, "食物：%s" % card.card_name)
		return true
	match id:
		&"dong_po_bing", &"ma_cheng_rou_gao", &"sha_wo_dou_si", &"yi_chang_xiao_mian", &"zhu_xi_wan_gao":
			ResourceManager.modify_energy(player, 3, "食物：%s" % card.card_name)
		&"jing_zhou_yu_gao":
			ResourceManager.modify_energy(player, 6, "食物：荆州鱼糕")
		&"chi_bi_rou_gao", &"san_you_shen_xian_ji":
			ResourceManager.modify_money(player, 500, "食物：%s" % card.card_name)
		&"re_gan_mian":
			ResourceManager.modify_energy(player, player.current_energy, "食物：热干面")
		&"bai_yang_dou_gan":
			return await _draw_regional_feiyi(player, MapSection.REGION.恩施, token)
		&"huang_zhou_dong_po_rou":
			return await _draw_regional_feiyi(player, MapSection.REGION.黄冈, token)
		&"jing_men_san_zheng":
			return _draw_foods(player, 3, [食物牌.FoodType.市级, 食物牌.FoodType.省级]) > 0
		&"tian_men_san_zheng":
			ResourceManager.modify_energy(player, 1, "食物：天门三蒸")
			_draw_foods(player, 2, [食物牌.FoodType.市级, 食物牌.FoodType.省级])
		&"mian_yang_san_zheng":
			ResourceManager.modify_energy(player, 2, "食物：沔阳三蒸")
			_draw_foods(player, 1, [])
		&"du_jia_ji", &"you_men_da_xia":
			_add_movement_discount(player, 4, 1, card.card_name)
		&"qi_chun_suan_mi_fen":
			_add_movement_discount(player, 2, 2, card.card_name)
		&"qing_zhuan_cha":
			_apply_permanent(player, id, card.card_name, func(): _state(player)[&"permanent_movement_discount"] = int(_state(player)[&"permanent_movement_discount"]) + 1)
		&"huang_shi_gang_bing":
			ResourceManager.modify_energy(player, 2, "食物：黄石港饼")
			_add_skip(player, 2, 2, card.card_name)
		&"tong_shan_bao_tuo":
			ResourceManager.modify_energy(player, 4, "食物：通山包坨")
			_add_skip(player, 1, 0, card.card_name)
		&"pi_tiao_shan_yu":
			ResourceManager.modify_energy(player, 2, "食物：皮条鳝鱼")
			_add_begin_recovery(player, 2, card.card_name)
		&"shen_nong_jia_la_rou":
			ResourceManager.modify_energy(player, 1, "食物：神农架腊肉")
			_add_begin_recovery(player, 4, card.card_name)
		&"tu_jia_tai_ge_zi", &"xiao_gan_mi_jiu":
			_add_step_bonus(player, 4, card.card_name)
		&"shang_xiang_feng_gan_ji", &"tu_jia_la_rou":
			_add_step_double(player, card.card_name)
		&"wu_xue_fo_shou_shan_yao", &"ying_shan_yu_mian":
			_apply_permanent(player, id, card.card_name, func(): _state(player)[&"permanent_step_bonus"] = int(_state(player)[&"permanent_step_bonus"]) + 1)
		&"mao_zui_lu_ji", &"sui_zhou_mi_zao":
			await _resolve_all_players_payment(player, 1, 100, card.card_name, token)
		&"wu_xue_su_tang":
			ResourceManager.modify_energy(player, 1, "食物：武穴酥糖")
			await _resolve_all_players_payment(player, 0, 50, card.card_name, token)
		&"xiang_yang_chan_ti":
			return await _resolve_single_payment(player, 200, card.card_name, token)
		&"zao_yang_suan_jiang_mian":
			return await _resolve_shared_status_target(player, card, token)
		&"zhang_guan_he_zha":
			return await _resolve_shared_energy_target(player, card, 4, token)
		&"san_he_tang", &"zhu_shan_lan_dou_fu":
			return await _resolve_secret_exchange(player, card, token)
		&"qian_zhang_kou_rou":
			if player.current_energy < 1 or MarketManager.get_inventory().is_empty():
				return false
			ResourceManager.modify_energy(player, -1, "食物成本：千张扣肉", true)
			var candidates := MarketManager.sample_cards(1)
			return not candidates.is_empty() and MarketManager.take_card_free(player, candidates[0])
		&"fang_xian_huang_jiu":
			return await _resolve_fangxian_wine(player, token)
		&"tu_jia_you_cha_tang":
			_apply_permanent(player, id, card.card_name, func(): _state(player)[&"work_income_bonus"] = int(_state(player)[&"work_income_bonus"]) + 250)
		&"tuan_feng_gou_jiao":
			return _create_generated_jinchan(player)
		_:
			push_error("FoodManager: 未实现食物效果 %s (%s)" % [card.card_name, id])
			return false
	return token == _session_token


func _draw_regional_feiyi(player: PlayerClass, region: MapSection.REGION, token: int) -> bool:
	var card: 非遗牌 = await ResourceManager.draw_regional_feiyi_free(player, region, true)
	return token == _session_token and card != null


func _draw_foods(player: PlayerClass, count: int, levels: Array) -> int:
	var cards: Array[食物牌] = ResourceManager.draw_food_cards_filtered(count, levels)
	for card: 食物牌 in cards:
		ResourceManager.add_food_card(player, card)
	return cards.size()


func _resolve_all_players_payment(source: PlayerClass, energy: int, payment: int, label: String, token: int) -> bool:
	var applied := false
	for target: PlayerClass in _alive_players():
		if token != _session_token:
			return applied
		if target == source:
			if energy > 0:
				ResourceManager.modify_energy(target, energy, "食物：%s" % label)
			applied = true
			continue
		var final_target: PlayerClass = await EventManager.resolve_external_food_target(source, target, "%s：精力与支付结算" % label)
		if final_target == null:
			continue
		if energy > 0:
			ResourceManager.modify_energy(final_target, energy, "食物：%s" % label)
		_pay(final_target, source, payment, label)
		applied = true
	return applied


func _resolve_single_payment(source: PlayerClass, payment: int, label: String, token: int) -> bool:
	var targets := _alive_players()
	targets.erase(source)
	var target: PlayerClass = await EventManager.request_external_player_choice(source, "%s：选择玩家" % label, targets, false)
	if token != _session_token or target == null:
		return false
	var final_target: PlayerClass = await EventManager.resolve_external_food_target(source, target, "%s：支付%d积分点" % [label, payment])
	if final_target == null:
		return false
	_pay(final_target, source, payment, label)
	return true


func _resolve_shared_energy_target(source: PlayerClass, card: 食物牌, amount: int, token: int) -> bool:
	var targets := _alive_players()
	targets.erase(source)
	var target: PlayerClass = await EventManager.request_external_player_choice(source, "%s：选择玩家" % card.card_name, targets, false)
	if token != _session_token or target == null:
		return false
	var final_target: PlayerClass = await EventManager.resolve_external_food_target(source, target, "%s：双方精力+%d" % [card.card_name, amount])
	if final_target == null:
		return false
	ResourceManager.modify_energy(source, amount, "食物：%s" % card.card_name)
	ResourceManager.modify_energy(final_target, amount, "食物：%s" % card.card_name)
	return true


func _resolve_shared_status_target(source: PlayerClass, card: 食物牌, token: int) -> bool:
	var targets := _alive_players()
	targets.erase(source)
	var target: PlayerClass = await EventManager.request_external_player_choice(source, "%s：选择玩家" % card.card_name, targets, false)
	if token != _session_token or target == null:
		return false
	var final_target: PlayerClass = await EventManager.resolve_external_food_target(source, target, "%s：精力+1并跳过移动与行动" % card.card_name)
	if final_target == null:
		return false
	for affected: PlayerClass in [source, final_target]:
		ResourceManager.modify_energy(affected, 1, "食物：%s" % card.card_name)
		_add_skip(affected, 1, 0, card.card_name)
		EventManager.add_status(affected, &"skip_action", 1, card.card_name)
	return true


func _resolve_secret_exchange(source: PlayerClass, card: 食物牌, token: int) -> bool:
	# 目标玩家的手牌属于隐藏信息。选择前只按存活状态筛选，不能据其是否
	# 持有合法非遗牌来隐藏目标；最终目标确定后再检查能否完成交换。
	var targets: Array[PlayerClass] = _alive_players()
	targets.erase(source)
	if _non_national_feiyi(source).is_empty():
		return false
	var target: PlayerClass = await EventManager.request_external_player_choice(source, "%s：选择交换玩家" % card.card_name, targets, false)
	if token != _session_token or target == null:
		return false
	var final_target: PlayerClass = await EventManager.resolve_external_food_target(source, target, "%s：交换非遗牌" % card.card_name)
	if final_target == null or _non_national_feiyi(final_target).is_empty():
		return false
	var source_card: 非遗牌 = await EventManager.request_external_card_choice(source, "秘密选择一张非遗牌", _non_national_feiyi(source), false) as 非遗牌
	if token != _session_token or source_card == null:
		return false
	var target_card: 非遗牌 = await EventManager.request_external_card_choice(final_target, "秘密选择一张非遗牌", _non_national_feiyi(final_target), false) as 非遗牌
	if token != _session_token or target_card == null:
		return false
	return ResourceManager.swap_feiyi_cards(source, source_card, final_target, target_card)


func _resolve_fangxian_wine(player: PlayerClass, token: int) -> bool:
	var candidates: Array[非遗牌] = MarketManager.sample_cards(4)
	if candidates.is_empty():
		return false
	var selected: Array = await EventManager.request_external_market_multi_choice(player, "房县黄酒：至多选择2张", candidates, 2)
	if token != _session_token:
		return false
	var acquired := 0
	for card: 非遗牌 in selected:
		if candidates.has(card) and MarketManager.take_card_free(player, card):
			acquired += 1
	return acquired > 0


func _create_generated_jinchan(player: PlayerClass) -> bool:
	var base := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	if base == null:
		return false
	var generated := base.duplicate(true) as 事件牌
	generated.set_meta(&"generated_by_food", true)
	return ResourceManager.add_event_card(player, generated)


func _pay(payer: PlayerClass, receiver: PlayerClass, requested: int, label: String) -> int:
	var amount := mini(maxi(requested, 0), maxi(payer.current_money, 0))
	if amount <= 0:
		return 0
	ResourceManager.modify_money(payer, -amount, "食物：%s" % label, true)
	ResourceManager.modify_money(receiver, amount, "食物：%s" % label)
	return amount


func _alive_players() -> Array[PlayerClass]:
	var result: Array[PlayerClass] = []
	for player: PlayerClass in TurnManager.players:
		if player != null and player.alive:
			result.append(player)
	return result


func _non_national_feiyi(player: PlayerClass) -> Array[非遗牌]:
	var result: Array[非遗牌] = []
	for card: 非遗牌 in ResourceManager.get_effective_feiyi_cards(player):
		if card.category != 非遗牌.CardCategory.国家级非遗:
			result.append(card)
	return result


func _food_id(card: 食物牌) -> StringName:
	if card.food_id != &"":
		return card.food_id
	return StringName(card.card_name.to_snake_case())


func _state(player: PlayerClass) -> Dictionary:
	if not _state_by_player.has(player):
		_state_by_player[player] = {
			&"permanent_food_ids": {},
			&"permanent_sources": {},
			&"permanent_step_bonus": 0,
			&"permanent_movement_discount": 0,
			&"work_income_bonus": 0,
			&"movement_discounts": [],
			&"movement_step_bonuses": [],
			&"movement_doubles": [],
			&"skip_moving": [],
			&"begin_recovery": [],
			&"movement_discount_remaining": 0,
			&"active_movement_turn": -1,
		}
	return _state_by_player[player]


func _has_permanent(player: PlayerClass, id: StringName) -> bool:
	return bool(_state(player)[&"permanent_food_ids"].get(id, false))


func _apply_permanent(player: PlayerClass, id: StringName, source_name: String, apply: Callable) -> bool:
	if _has_permanent(player, id):
		return false
	_state(player)[&"permanent_food_ids"][id] = true
	_state(player)[&"permanent_sources"][id] = source_name
	apply.call()
	food_state_changed.emit(player)
	return true


func _permanent_source(state: Dictionary, id: StringName) -> String:
	return String(state.get(&"permanent_sources", {}).get(id, ""))


func _add_movement_discount(player: PlayerClass, amount: int, uses: int, source_name: String) -> void:
	_state(player)[&"movement_discounts"].append({
		"amount": maxi(amount, 0), "uses": maxi(uses, 0), "source_name": source_name,
	})
	food_state_changed.emit(player)


func _add_step_bonus(player: PlayerClass, amount: int, source_name: String) -> void:
	_state(player)[&"movement_step_bonuses"].append({"amount": amount, "source_name": source_name})
	food_state_changed.emit(player)


func _add_step_double(player: PlayerClass, source_name: String) -> void:
	_state(player)[&"movement_doubles"].append({"source_name": source_name})
	food_state_changed.emit(player)


func _add_skip(player: PlayerClass, count: int, energy_reward: int, source_name: String) -> void:
	for _index: int in maxi(count, 0):
		_state(player)[&"skip_moving"].append({
			"energy_reward": maxi(energy_reward, 0), "source_name": source_name,
		})
	food_state_changed.emit(player)


func _add_begin_recovery(player: PlayerClass, count: int, source_name: String) -> void:
	_state(player)[&"begin_recovery"].append({
		"remaining": maxi(count, 0), "amount": 1, "source_name": source_name,
	})
	food_state_changed.emit(player)


func _tick_begin_recovery(player: PlayerClass, state: Dictionary) -> void:
	var recoveries: Array = state[&"begin_recovery"]
	for entry: Dictionary in recoveries:
		if int(entry.get("remaining", 0)) <= 0:
			continue
		var amount := int(entry.get("amount", 1))
		var source_name := String(entry.get("source_name", "食物效果"))
		ResourceManager.modify_energy(player, amount, "食物：%s" % source_name)
		_append_phase_message(player, "【%s】生效：回合开始精力+%d。" % [source_name, amount])
		entry["remaining"] = int(entry["remaining"]) - 1
	state[&"begin_recovery"] = recoveries.filter(func(entry: Dictionary) -> bool: return int(entry.get("remaining", 0)) > 0)
	food_state_changed.emit(player)


func _consume_movement_step_effects(player: PlayerClass, state: Dictionary) -> void:
	var permanent_step_sources: Array[String] = []
	for id: StringName in [&"wu_xue_fo_shou_shan_yao", &"ying_shan_yu_mian"]:
		var source_name := _permanent_source(state, id)
		if not source_name.is_empty():
			permanent_step_sources.append(source_name)
	if not permanent_step_sources.is_empty():
		_append_phase_message(player, "【%s】生效：本移动阶段步数+%d。" % ["、".join(permanent_step_sources), permanent_step_sources.size()])
	for entry: Dictionary in state[&"movement_step_bonuses"]:
		_append_phase_message(player, "【%s】生效：本移动阶段步数+%d。" % [String(entry.get("source_name", "食物效果")), int(entry.get("amount", 0))])
	var double_sources: Array[String] = []
	for entry: Dictionary in state[&"movement_doubles"]:
		var source_name := String(entry.get("source_name", "食物效果"))
		if not double_sources.has(source_name):
			double_sources.append(source_name)
	if not double_sources.is_empty():
		_append_phase_message(player, "【%s】生效：本移动阶段步数翻倍。" % "、".join(double_sources))
	state[&"movement_step_bonuses"] = []
	state[&"movement_doubles"] = []
