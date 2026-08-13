extends GutTest

var _players_backup: Array[PlayerClass]
var _market_backup: Array[非遗牌]
var _event_discard_backup: Array[事件牌]

func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_market_backup = MarketManager.get_inventory()
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)
	MarketManager.reset_for_new_game()
	ResourceManager.事件弃牌堆.clear()
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION

func after_each() -> void:
	TurnManager.GameOn = false
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = TurnManager.players.size()
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	EventManager.reset_for_new_game()

func test_jian_wang_samples_at_most_three_and_leaves_unselected_cards() -> void:
	var player := _make_player("触发者")
	TurnManager.players.assign([player])
	for index in 5:
		MarketManager.deposit_card(_make_feiyi("藏品%d" % index, index), &"test")
	EventManager.choice_strategy = func(request: EventChoiceRequest): return request.options[0]
	await EventManager._event_jian_wang_zhi_lai(player)
	assert_eq(player.非遗牌手牌.size(), 1)
	assert_eq(MarketManager.get_inventory().size(), 4, "只有选中牌离开研究所")
	player.free()

func test_shi_ji_empty_inventory_is_noop() -> void:
	var player := _make_player("触发者")
	TurnManager.players.assign([player])
	await EventManager._event_shi_ji_tao_zhen(player)
	assert_true(player.非遗牌手牌.is_empty())
	player.free()

func test_zhan_yi_forces_choice_between_highest_score_ties() -> void:
	var player := _make_player("触发者")
	var low := _make_feiyi("低分", 1)
	var high_a := _make_feiyi("高分甲", 4)
	var high_b := _make_feiyi("高分乙", 4)
	player.非遗牌手牌.assign([low, high_a, high_b])
	TurnManager.players.assign([player])
	EventManager.choice_strategy = func(request: EventChoiceRequest): return request.options.back()
	await EventManager._event_zhan_yi_gong_yan(player)
	assert_true(player.非遗牌手牌.has(high_a))
	assert_false(player.非遗牌手牌.has(high_b))
	assert_true(MarketManager.get_inventory().has(high_b))
	player.free()

func test_fu_di_uses_redirect_chain_and_final_target_can_cancel() -> void:
	var source := _make_player("来源")
	var first_target := _make_player("第一目标")
	var redirected_target := _make_player("转移目标")
	first_target.非遗牌手牌.append(_make_feiyi("第一目标藏品", 2))
	redirected_target.非遗牌手牌.append(_make_feiyi("转移目标藏品", 2))
	var redirect := _make_retained_event("移花接木", &"yi_hua_jie_mu")
	var cancel := _make_retained_event("金蝉脱壳", &"jin_chan_tuo_qiao")
	first_target.事件牌手牌.append(redirect)
	redirected_target.事件牌手牌.append(cancel)
	TurnManager.players.assign([source, first_target, redirected_target])
	TurnManager.player_num = 3
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.prompt.begins_with("釜底抽薪：选择"):
			return first_target
		if request.requester == first_target and request.kind == EventChoiceRequest.ChoiceKind.卡牌:
			return redirect
		if request.prompt.begins_with("移花接木"):
			return redirected_target
		if request.requester == redirected_target and request.kind == EventChoiceRequest.ChoiceKind.卡牌:
			return cancel
		return request.options[0]
	await EventManager._event_fu_di_chou_xin(source)
	assert_true(MarketManager.get_inventory().is_empty(), "最终目标抵消后不应有牌入库")
	assert_true(ResourceManager.事件弃牌堆.has(redirect))
	assert_true(ResourceManager.事件弃牌堆.has(cancel))
	source.free()
	first_target.free()
	redirected_target.free()

func _make_player(display_name: String) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_name = display_name
	return player

func _make_feiyi(display_name: String, score: int) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.category = 非遗牌.CardCategory.手工技艺
	card.base_score = score
	return card

func _make_retained_event(display_name: String, event_id: StringName) -> 事件牌:
	var card := 事件牌.new()
	card.card_name = display_name
	card.event_id = event_id
	card.retainable = true
	return card
