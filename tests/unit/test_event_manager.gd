extends GutTest

var _source: PlayerClass
var _target: PlayerClass
var _effect_calls: int = 0

func before_each() -> void:
	EventManager.reset_for_new_game()
	EventManager.auto_resolve_choices = true
	TurnManager.GameOn = true
	TurnManager.now_turn = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	_source = PlayerClass.new()
	_source.player_name = "来源"
	_target = PlayerClass.new()
	_target.player_name = "目标"
	TurnManager.players.assign([_source, _target])
	TurnManager.player_num = 2
	TurnManager.now_player_index = 0
	_effect_calls = 0

func after_each() -> void:
	TurnManager.GameOn = false
	TurnManager.players.clear()
	EventManager.reset_for_new_game()
	_source.free()
	_target.free()

func test_new_status_does_not_consume_already_entered_phase() -> void:
	EventManager.add_status(_target, &"skip_moving", 2)
	assert_false(EventManager.on_phase_entered(_target, TurnManager.TurnPhase.MOVING))
	assert_eq(EventManager.get_status_remaining(_target, &"skip_moving"), 2)
	TurnManager.now_turn = 2
	assert_true(EventManager.on_phase_entered(_target, TurnManager.TurnPhase.MOVING))
	assert_eq(EventManager.get_status_remaining(_target, &"skip_moving"), 1)
	TurnManager.now_turn = 3
	assert_true(EventManager.on_phase_entered(_target, TurnManager.TurnPhase.MOVING))
	assert_eq(EventManager.get_status_remaining(_target, &"skip_moving"), 0)

func test_free_move_status_applies_to_two_future_moving_phases() -> void:
	EventManager.add_status(_target, &"free_move_phases", 2)
	TurnManager.now_turn = 2
	assert_false(EventManager.on_phase_entered(_target, TurnManager.TurnPhase.MOVING))
	var section := MapSection.new()
	assert_eq(EventManager.adjust_movement_cost(_target, 7, 4, section), 0)
	TurnManager.now_turn = 3
	EventManager.on_phase_entered(_target, TurnManager.TurnPhase.BEGIN)
	EventManager.on_phase_entered(_target, TurnManager.TurnPhase.MOVING)
	assert_eq(EventManager.adjust_movement_cost(_target, 5, 3, section), 0)
	assert_eq(EventManager.get_status_remaining(_target, &"free_move_phases"), 0)
	section.free()

func test_emergency_immunity_only_blocks_losses_in_same_action_turn() -> void:
	EventManager._player_status(_target)[&"loss_immunity"] = {"turn": 1}
	assert_true(EventManager.is_loss_immune(_target))
	_target.current_energy = 6
	assert_false(ResourceManager.modify_energy(_target, -3, "测试损失"))
	assert_eq(_target.current_energy, 6)
	TurnManager.now_turn = 2
	assert_false(EventManager.is_loss_immune(_target))
	assert_true(ResourceManager.modify_energy(_target, -3, "下一回合损失"))
	assert_eq(_target.current_energy, 3)

func test_jin_chan_cancels_only_targets_incoming_effect() -> void:
	var jin_chan := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_target.事件牌手牌.append(jin_chan)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		return request.options[0]
	var applied := await EventManager._resolve_incoming_effect(_source, _target, &"event", "测试效果", _mark_effect)
	assert_false(applied)
	assert_eq(_effect_calls, 0)
	assert_false(_target.事件牌手牌.has(jin_chan))
	assert_true(ResourceManager.事件弃牌堆.has(jin_chan))

func test_myth_card_is_available_for_event_but_not_other_effect_kind() -> void:
	var myth := load("res://Cards/非遗牌/武汉/黄鹤楼传说.tres") as 非遗牌
	_target.非遗牌手牌.append(myth)
	assert_true(EventManager._eligible_response_cards(_target, &"event").has(myth))
	assert_false(EventManager._eligible_response_cards(_target, &"ability").has(myth))

func test_jin_chan_is_only_available_for_supported_card_effects() -> void:
	var jin_chan := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_target.事件牌手牌.append(jin_chan)
	assert_true(EventManager._eligible_response_cards(_target, &"event").has(jin_chan))
	assert_true(EventManager._eligible_response_cards(_target, &"food").has(jin_chan))
	assert_true(EventManager._eligible_response_cards(_target, &"feiyi").has(jin_chan))
	assert_false(EventManager._eligible_response_cards(_target, &"ability").has(jin_chan))

func test_miao_shou_hui_chun_revives_before_elimination() -> void:
	var revive := load("res://Cards/事件牌/妙手回春.tres") as 事件牌
	_source.事件牌手牌.append(revive)
	_target.current_energy = 0
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		return true if request.options.has(true) else request.options[0]
	var revived := await EventManager.try_revive_player(_target)
	assert_true(revived)
	assert_eq(_target.current_energy, 3)
	assert_false(_source.事件牌手牌.has(revive))

func test_redirect_chain_gives_new_target_a_fresh_response_window() -> void:
	var third := PlayerClass.new()
	third.player_name = "第三人"
	TurnManager.players.append(third)
	TurnManager.player_num = 3
	var redirect := load("res://Cards/事件牌/移花接木.tres") as 事件牌
	var cancel := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_target.事件牌手牌.append(redirect)
	third.事件牌手牌.append(cancel)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.卡牌:
			if request.options.has(redirect):
				return redirect
			if request.options.has(cancel):
				return cancel
		elif request.kind == EventChoiceRequest.ChoiceKind.玩家 and request.options.has(third):
			return third
		return request.options[0]
	var applied := await EventManager._resolve_incoming_effect(_source, _target, &"event", "连续响应测试", _mark_effect)
	assert_false(applied)
	assert_eq(_effect_calls, 0)
	assert_false(_target.事件牌手牌.has(redirect))
	assert_false(third.事件牌手牌.has(cancel))
	TurnManager.players.erase(third)
	third.free()

func test_redirect_back_to_original_source_cannot_respond_to_own_effect() -> void:
	var redirect := load("res://Cards/事件牌/移花接木.tres") as 事件牌
	var source_cancel := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_target.事件牌手牌.append(redirect)
	_source.事件牌手牌.append(source_cancel)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.卡牌 and request.options.has(redirect):
			return redirect
		if request.kind == EventChoiceRequest.ChoiceKind.玩家 and request.options.has(_source):
			return _source
		return request.options[0]
	var applied := await EventManager._resolve_incoming_effect(_source, _target, &"event", "转回来源测试", _mark_effect)
	assert_true(applied)
	assert_eq(_effect_calls, 1)
	assert_true(_source.事件牌手牌.has(source_cancel), "原出牌者不能用金蝉脱壳响应自己的牌")
	assert_false(_target.事件牌手牌.has(redirect))

func test_group_effect_cancels_only_responder_portion() -> void:
	var cancel := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_target.事件牌手牌.append(cancel)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		return request.options[0]
	var source_applied := await EventManager._resolve_incoming_effect(_source, _source, &"event", "群体效果来源部分", _mark_effect)
	var target_applied := await EventManager._resolve_incoming_effect(_source, _target, &"event", "群体效果目标部分", _mark_effect)
	assert_true(source_applied)
	assert_false(target_applied)
	assert_eq(_effect_calls, 1)

func test_timeout_defaults_optional_to_pass_and_forced_to_legal_option() -> void:
	watch_signals(EventManager)
	var optional := EventChoiceRequest.new(_source, "可选", [1], PackedStringArray(["发动"]), true)
	optional.request_id = 71
	EventManager._pending_request = optional
	EventManager._choice_waiting = true
	EventManager._pending_choice = 99
	EventManager._on_choice_timeout()
	assert_null(EventManager._pending_choice)
	assert_false(EventManager._choice_waiting)
	assert_signal_emit_count(EventManager, "choice_resolved", 1)

	var forced := EventChoiceRequest.new(_source, "强制", [42], PackedStringArray(["唯一合法项"]), false)
	forced.request_id = 72
	EventManager._pending_request = forced
	EventManager._choice_waiting = true
	EventManager._pending_choice = null
	EventManager._on_choice_timeout()
	assert_eq(EventManager._pending_choice, 42)
	assert_false(EventManager._choice_waiting)
	assert_signal_emit_count(EventManager, "choice_resolved", 2)

func test_timeout_clears_stale_event_overlay_request() -> void:
	var overlay := preload("res://HUDs/event_overlay.tscn").instantiate() as EventOverlay
	add_child_autofree(overlay)
	await get_tree().process_frame
	var request := EventChoiceRequest.new(_target, "响应测试", [1], PackedStringArray(["使用金蝉脱壳"]), true)
	request.request_id = 91
	request.timeout_seconds = 15.0
	EventManager._pending_request = request
	EventManager._choice_waiting = true
	EventManager.reaction_requested.emit(request)
	assert_eq(overlay._active_request, request)
	EventManager._on_choice_timeout()
	await get_tree().process_frame
	assert_null(overlay._active_request)
	assert_eq(overlay._options_box.get_child_count(), 0)
	assert_eq(overlay._instruction_label.text, "结算中")

func test_event_money_loss_uses_maximum_legal_amount() -> void:
	_target.current_money = 120
	EventManager._apply_money(_target, -500, "测试")
	assert_eq(_target.current_money, 0)

func test_emergency_avoidance_without_a_card_cannot_grant_immunity() -> void:
	assert_true(_source.非遗牌手牌.is_empty())
	assert_true(_source.食物牌手牌.is_empty())
	assert_true(_source.事件牌手牌.is_empty())
	await EventManager._event_jin_ji_bi_xian(_source)
	assert_false(EventManager.is_loss_immune(_source))

func test_food_draw_uses_maximum_available_amount() -> void:
	var deck_backup := ResourceManager.食物牌库.duplicate()
	var only_food := 食物牌.new()
	only_food.card_name = "仅剩食物"
	ResourceManager.食物牌库.assign([only_food])
	assert_eq(EventManager._draw_food_cards(_source, 2), 1)
	assert_eq(_source.食物牌手牌.size(), 1)
	assert_true(_source.食物牌手牌.has(only_food))
	ResourceManager.食物牌库.assign(deck_backup)

func test_you_mu_cheng_huai_teleports_and_gains_exactly_five_energy() -> void:
	var scenario := _make_linear_map_with_work_and_scenery()
	var map := scenario["map"] as MAP
	var scenery := scenario["scenery"] as MapSection
	_source.map = map
	_source.now_pos = Vector3i.ZERO
	_source.current_energy = 6
	TurnManager.map = map
	await EventManager._play_you_mu_cheng_huai(_source)
	assert_eq(_source.now_pos, scenery.location_index)
	assert_eq(_source.current_energy, 11)
	TurnManager.map = null
	map.free()

func test_scenery_ban_makes_you_mu_illegal_without_consuming_it() -> void:
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	_source.事件牌手牌.append(card)
	EventManager.add_status(_source, &"scenery_banned", 3)
	assert_false(EventManager.can_play_retained_event_now(card, _source))
	await EventManager.play_retained_event(_source, card)
	assert_true(_source.事件牌手牌.has(card))
	assert_false(ResourceManager.事件弃牌堆.has(card))

func test_work_ban_energy_and_path_filter_forced_work_targets() -> void:
	var scenario := _make_linear_map_with_work_and_scenery()
	var map := scenario["map"] as MAP
	_source.map = map
	_source.now_pos = Vector3i.ZERO
	TurnManager.map = map
	assert_true(EventManager._can_be_forced_to_work(_source))
	_source.current_energy = 0
	assert_false(EventManager._can_be_forced_to_work(_source))
	_source.current_energy = 6
	EventManager.add_status(_source, &"work_banned", 3)
	assert_false(EventManager._can_be_forced_to_work(_source))
	TurnManager.map = null
	map.free()

func test_equidistant_work_choice_is_requested_from_the_moved_player() -> void:
	var scenario := _make_linear_map_with_work_and_scenery()
	var map := scenario["map"] as MAP
	_source.map = map
	_target.map = map
	_source.now_pos = Vector3i(2, -2, 0)
	_source.current_energy = 0
	_target.now_pos = Vector3i.ZERO
	_target.current_energy = 6
	TurnManager.map = map
	var section_requesters: Array[PlayerClass] = []
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.格子:
			section_requesters.append(request.requester)
		return request.options[0]
	await EventManager._event_zuo_shou_yu_li(_source)
	assert_eq(section_requesters, [_target])
	assert_eq(_target.current_energy, 5)
	assert_eq(_target.current_money, 1125)
	assert_eq(_source.current_money, 1125)
	TurnManager.map = null
	map.free()

func test_no_legal_redirect_keeps_yi_hua_and_applies_effect() -> void:
	var redirect := load("res://Cards/事件牌/移花接木.tres") as 事件牌
	_target.事件牌手牌.append(redirect)
	var response_was_offered := false
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.卡牌:
			response_was_offered = true
		return request.options[0]
	var applied := await EventManager._resolve_incoming_effect(
		_source,
		_target,
		&"event",
		"无合法转移目标",
		_mark_effect,
		true,
		func(candidate: PlayerClass) -> bool: return candidate != _source
	)
	assert_true(applied)
	assert_false(response_was_offered)
	assert_eq(_effect_calls, 1)
	assert_true(_target.事件牌手牌.has(redirect))

func test_reset_clears_revive_modal_ownership() -> void:
	EventManager._revive_modal_owned = true
	EventManager.reset_for_new_game()
	assert_false(EventManager._revive_modal_owned)

func test_jin_chan_does_not_cancel_the_other_players_portion_of_tong_tai() -> void:
	var source_card := 非遗牌.new()
	source_card.card_name = "来源牌"
	source_card.category = 非遗牌.CardCategory.手工技艺
	source_card.rarity = 3
	var target_card := 非遗牌.new()
	target_card.card_name = "目标牌"
	target_card.category = 非遗牌.CardCategory.手工技艺
	target_card.rarity = 1
	var jin_chan := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	_source.非遗牌手牌.append(source_card)
	_target.非遗牌手牌.append(target_card)
	_target.事件牌手牌.append(jin_chan)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.options.has(jin_chan):
			return jin_chan
		return request.options[0]
	await EventManager._event_tong_tai_jing_ji(_source)
	assert_eq(_source.current_money, 1100, "来源玩家的获胜部分应继续结算")
	assert_eq(_target.current_money, 1000, "目标玩家只抵消自己的失分部分")
	assert_false(_target.事件牌手牌.has(jin_chan))

func test_yi_cang_invitation_timeout_means_refusal() -> void:
	var source_card := 非遗牌.new()
	source_card.card_name = "来源牌"
	source_card.category = 非遗牌.CardCategory.手工技艺
	var target_card := 非遗牌.new()
	target_card.card_name = "目标牌"
	target_card.category = 非遗牌.CardCategory.手工技艺
	_source.非遗牌手牌.append(source_card)
	_target.非遗牌手牌.append(target_card)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.requester == _target and request.optional:
			return null
		return request.options[0]
	await EventManager._event_yi_cang_hu_huan(_source)
	assert_true(_source.非遗牌手牌.has(source_card))
	assert_true(_target.非遗牌手牌.has(target_card))
	assert_eq(_source.current_energy, 6)
	assert_eq(_target.current_energy, 6)

func test_redirected_wen_hua_gong_xiang_discards_from_final_target() -> void:
	var third := PlayerClass.new()
	third.player_name = "第三人"
	var redirect := load("res://Cards/事件牌/移花接木.tres") as 事件牌
	_target.事件牌手牌.append(redirect)
	for index in 3:
		var food := 食物牌.new()
		food.card_name = "第三人食物%d" % index
		third.食物牌手牌.append(food)
	TurnManager.players.append(third)
	TurnManager.player_num = 3
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.卡牌 and request.options.has(redirect):
			return redirect
		if request.kind == EventChoiceRequest.ChoiceKind.玩家:
			return _target if request.options.has(_target) else third
		return request.options[0]
	await EventManager._event_wen_hua_gong_xiang(_source)
	assert_eq(third.食物牌手牌.size(), 1)
	assert_eq(_target.食物牌手牌.size(), 0)
	TurnManager.players.erase(third)
	third.free()

func test_redirected_chuan_yi_draws_from_final_target() -> void:
	var third := PlayerClass.new()
	third.player_name = "第三人"
	var redirect := load("res://Cards/事件牌/移花接木.tres") as 事件牌
	var original_card := 非遗牌.new()
	original_card.card_name = "原目标牌"
	original_card.category = 非遗牌.CardCategory.手工技艺
	var redirected_card := 非遗牌.new()
	redirected_card.card_name = "新目标牌"
	redirected_card.category = 非遗牌.CardCategory.手工技艺
	_target.事件牌手牌.append(redirect)
	_target.非遗牌手牌.append(original_card)
	third.非遗牌手牌.append(redirected_card)
	TurnManager.players.append(third)
	TurnManager.player_num = 3
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.卡牌 and request.options.has(redirect):
			return redirect
		if request.kind == EventChoiceRequest.ChoiceKind.玩家:
			return _target if request.options.has(_target) else third
		return request.options[0]
	await EventManager._event_chuan_yi_hu_jian(_source)
	assert_true(_target.非遗牌手牌.has(original_card), "原目标的牌不得在转移后被拿走")
	assert_false(third.非遗牌手牌.has(redirected_card))
	assert_true(_source.非遗牌手牌.has(redirected_card))
	TurnManager.players.erase(third)
	third.free()

func test_retained_event_usage_matches_current_phase() -> void:
	var action_card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	var moving_card := load("res://Cards/事件牌/畅行无阻.tres") as 事件牌
	_source.事件牌手牌.assign([action_card, moving_card])
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	assert_true(EventManager.can_play_retained_event_now(action_card, _source))
	assert_false(EventManager.can_play_retained_event_now(moving_card, _source))
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	assert_false(EventManager.can_play_retained_event_now(action_card, _source))
	assert_true(EventManager.can_play_retained_event_now(moving_card, _source))

func test_direct_retained_event_use_removes_card_and_applies_effect() -> void:
	var moving_card := load("res://Cards/事件牌/畅行无阻.tres") as 事件牌
	var was_already_discarded := ResourceManager.事件弃牌堆.has(moving_card)
	_source.事件牌手牌.append(moving_card)
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	await EventManager.request_play_retained_event(_source, moving_card)
	assert_false(_source.事件牌手牌.has(moving_card))
	assert_true(ResourceManager.事件弃牌堆.has(moving_card))
	assert_true(EventManager.can_ignore_special_terrain_this_phase(_source))
	assert_eq(TurnManager.modal_resolution_depth, 0)
	if not was_already_discarded:
		ResourceManager.事件弃牌堆.erase(moving_card)

func test_next_alive_filters_eliminated_players_in_2_3_and_6_player_games() -> void:
	for player_count in [2, 3, 6]:
		var players: Array[PlayerClass] = []
		for index in player_count:
			var player := PlayerClass.new()
			player.player_name = "P%d" % index
			player.alive = index in [0, player_count - 1]
			players.append(player)
		TurnManager.players.assign(players)
		TurnManager.player_num = player_count
		assert_eq(EventManager._next_alive(players[0]), players[player_count - 1], "%d 人局应跳过中间淘汰玩家" % player_count)
		for player: PlayerClass in players:
			player.free()
	TurnManager.players.assign([_source, _target])
	TurnManager.player_num = 2

func _mark_effect(_player: PlayerClass) -> void:
	_effect_calls += 1

func _make_linear_map_with_work_and_scenery() -> Dictionary:
	var map := MAP.new()
	for coordinate in range(-2, 3):
		var section := MapSection.new()
		section.location_index = Vector3i(coordinate, -coordinate, 0)
		section.section_name = "测试格%d" % coordinate
		section.type = MapSection.SectionType.一般
		if coordinate in [-1, 1]:
			section.type = MapSection.SectionType.打工
		elif coordinate == 2:
			section.type = MapSection.SectionType.风景
		map.add_child(section)
		map.grid_map[section.location_index] = section
	return {
		"map": map,
		"scenery": map.grid_map[Vector3i(2, -2, 0)],
	}
