extends GutTest

var _first: PlayerClass
var _second: PlayerClass
var _resource_hud_backup: HUD


func before_each() -> void:
	_first = PlayerClass.new()
	_first.player_name = "职业测试P1"
	_first.player_types = PlayerClass.PlayerCharacter.美食博主
	_prepare_character_art(_first)
	_second = PlayerClass.new()
	_second.player_name = "职业测试P2"
	_second.player_types = PlayerClass.PlayerCharacter.生活博主
	_prepare_character_art(_second)
	_resource_hud_backup = ResourceManager.hud
	ResourceManager.hud = null
	var players: Array[PlayerClass] = [_first, _second]
	ProfessionManager.reset_for_new_game(players)


func after_each() -> void:
	ProfessionManager.reset_for_new_game()
	ResourceManager.hud = _resource_hud_backup
	_first.free()
	_second.free()


func test_six_definitions_are_complete_unique_and_match_player_enum() -> void:
	var definitions: Array[ProfessionDefinition] = ProfessionManager.get_all_definitions()
	assert_eq(definitions.size(), 6)
	var ids: Dictionary[StringName, bool] = {}
	var types: Dictionary[int, bool] = {}
	for definition: ProfessionDefinition in definitions:
		assert_false(definition.profession_id.is_empty())
		assert_false(definition.profession_name.is_empty())
		assert_false(definition.skill_name.is_empty())
		assert_false(definition.description.is_empty())
		assert_false(definition.short_description.is_empty())
		assert_false(ids.has(definition.profession_id), str(definition.profession_id))
		assert_false(types.has(int(definition.profession_type)), definition.profession_name)
		ids[definition.profession_id] = true
		types[int(definition.profession_type)] = true
	assert_eq(
		ProfessionManager.get_definition_by_type(PlayerClass.PlayerCharacter.旅行博主).profession_name,
		"旅行博主"
	)
	var explorer := ProfessionManager.get_definition_by_type(PlayerClass.PlayerCharacter.探险博主)
	assert_true(explorer.can_move_at_begin)
	assert_true(explorer.can_move_at_end)
	assert_string_contains(explorer.description, "准备阶段和结束阶段")


func test_all_profession_definitions_have_selection_portraits() -> void:
	var definitions: Array[ProfessionDefinition] = ProfessionManager.get_all_definitions()
	assert_eq(definitions.size(), PlayerClass.PlayerCharacter.size())
	for definition: ProfessionDefinition in definitions:
		assert_not_null(definition.selection_portrait, "%s 缺少选角立绘" % definition.profession_name)


func test_dynamic_query_and_rule_helpers_follow_current_profession() -> void:
	assert_eq(ProfessionManager.get_definition(_first).profession_id, &"food_blogger")
	assert_eq(ProfessionManager.get_food_use_limit(_first), 3)
	assert_eq(ProfessionManager.get_work_energy_cost(_first), 1)
	_first.player_types = PlayerClass.PlayerCharacter.生活博主
	assert_eq(ProfessionManager.get_definition(_first).profession_id, &"life_blogger")
	assert_eq(ProfessionManager.get_food_use_limit(_first), 1)
	assert_eq(ProfessionManager.get_work_energy_cost(_first), 0)
	_first.player_types = PlayerClass.PlayerCharacter.商业博主
	assert_eq(ProfessionManager.adjust_market_buy_price(_first, 700), 350)
	assert_eq(ProfessionManager.get_market_buy_price(_first, 701), 351)
	assert_eq(ProfessionManager.get_food_shop_refresh_limit(_first), 1)
	_first.player_types = PlayerClass.PlayerCharacter.探险博主
	assert_true(ProfessionManager.can_move_at_begin(_first))
	assert_true(ProfessionManager.can_move_at_end(_first))


func test_travel_blogger_reduces_each_scenery_entry_cost_by_one() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.旅行博主
	var flat_scenery := MapSection.new()
	flat_scenery.type = MapSection.SectionType.风景
	flat_scenery.landform = MapSection.LandForm.平原
	flat_scenery.cost = 1
	var mountain_scenery := MapSection.new()
	mountain_scenery.type = MapSection.SectionType.风景
	mountain_scenery.landform = MapSection.LandForm.山地
	mountain_scenery.cost = 2
	var ordinary_mountain := MapSection.new()
	ordinary_mountain.type = MapSection.SectionType.一般
	ordinary_mountain.landform = MapSection.LandForm.山地
	ordinary_mountain.cost = 2

	assert_eq(ProfessionManager.adjust_section_movement_cost(_first, flat_scenery, flat_scenery.cost), 0)
	assert_eq(ProfessionManager.adjust_section_movement_cost(_first, mountain_scenery, mountain_scenery.cost), 1)
	assert_eq(ProfessionManager.adjust_section_movement_cost(_first, ordinary_mountain, ordinary_mountain.cost), 2)
	assert_true(ProfessionManager.block_skill(_first, 1))
	assert_eq(ProfessionManager.adjust_section_movement_cost(_first, mountain_scenery, mountain_scenery.cost), 2)

	flat_scenery.free()
	mountain_scenery.free()
	ordinary_mountain.free()


func test_commercial_starting_bonus_is_once_only_and_does_not_follow_profession_swap() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.商业博主
	_first.current_money = 500
	_second.current_money = 500
	watch_signals(ProfessionManager)
	ProfessionManager.apply_starting_bonuses()
	assert_eq(_first.current_money, 1000)
	assert_eq(_second.current_money, 500)
	assert_signal_not_emitted(ProfessionManager, "skill_triggered", "开局被动到账不得弹出职业技能提示")
	ProfessionManager.apply_starting_bonuses()
	assert_eq(_first.current_money, 1000, "重复初始化不得补发")
	assert_true(ProfessionManager.swap_professions(_first, _second))
	ProfessionManager.apply_starting_bonuses()
	assert_eq(_first.current_money, 1000, "失去职业不扣回")
	assert_eq(_second.current_money, 500, "后来获得职业不补发")


func test_four_turn_block_counts_current_turn_and_restores_after_four_ends() -> void:
	watch_signals(ProfessionManager)
	assert_true(ProfessionManager.block_skill(_first, 4))
	assert_eq(ProfessionManager.get_blocked_turns(_first), 4)
	assert_false(ProfessionManager.is_skill_enabled(_first))
	assert_false(ProfessionManager.is_skill_enabled(_first, PlayerClass.PlayerCharacter.美食博主))
	assert_eq(ProfessionManager.get_food_use_limit(_first), 1)
	assert_eq(ProfessionManager.on_player_turn_finished(_first), 3, "触发当回合 END 立即从4减到3")
	assert_eq(ProfessionManager.on_player_turn_finished(_first), 2)
	assert_eq(ProfessionManager.on_player_turn_finished(_first), 1)
	assert_eq(ProfessionManager.on_player_turn_finished(_first), 0)
	assert_true(ProfessionManager.is_skill_enabled(_first))
	assert_eq(ProfessionManager.get_food_use_limit(_first), 3)
	assert_signal_emit_count(ProfessionManager, "skill_state_changed", 5)


func test_block_stays_with_player_when_professions_are_swapped() -> void:
	watch_signals(ProfessionManager)
	assert_true(ProfessionManager.block_skill(_first, 4))
	assert_true(ProfessionManager.swap_professions(_first, _second))
	assert_eq(_first.player_types, PlayerClass.PlayerCharacter.生活博主)
	assert_eq(_second.player_types, PlayerClass.PlayerCharacter.美食博主)
	assert_eq(_first.animation, &"生活博主")
	assert_eq(_second.animation, &"美食博主")
	assert_eq(ProfessionManager.get_blocked_turns(_first), 4)
	assert_eq(ProfessionManager.get_blocked_turns(_second), 0)
	assert_eq(ProfessionManager.get_work_energy_cost(_first), 1, "封锁中的生活博主仍支付普通打工精力")
	assert_eq(ProfessionManager.get_food_use_limit(_second), 3)
	assert_signal_emitted_with_parameters(ProfessionManager, "profession_changed", [_first, _second])


func test_set_profession_refreshes_character_before_emitting_change() -> void:
	watch_signals(ProfessionManager)
	assert_true(ProfessionManager.set_profession(_first, PlayerClass.PlayerCharacter.商业博主))
	assert_eq(_first.player_types, PlayerClass.PlayerCharacter.商业博主)
	assert_eq(_first.animation, &"商业博主")
	assert_signal_emitted_with_parameters(ProfessionManager, "profession_changed", [_first, null])


func test_skill_trigger_signal_only_emits_while_current_skill_is_enabled() -> void:
	watch_signals(ProfessionManager)
	assert_true(ProfessionManager.notify_skill_triggered(_first, "享用食物"))
	assert_signal_emitted_with_parameters(
		ProfessionManager,
		"skill_triggered",
		[_first, &"food_blogger", "享用食物"]
	)
	ProfessionManager.block_skill(_first, 4)
	assert_false(ProfessionManager.notify_skill_triggered(_first, "不应触发"))
	assert_signal_emit_count(ProfessionManager, "skill_triggered", 1)


func test_travel_reward_accepts_only_confirmed_scenery_arrival_sources() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.旅行博主
	_first.current_money = 1000
	var scenery := MapSection.new()
	scenery.type = MapSection.SectionType.风景
	watch_signals(ProfessionManager)
	assert_true(ProfessionManager.record_scenery_arrival(_first, scenery))
	assert_eq(_first.current_money, 1250)
	assert_false(ProfessionManager.record_scenery_arrival(_first, scenery, &"explorer"))
	assert_false(ProfessionManager.record_scenery_arrival(_first, scenery, &"teleport"))
	assert_eq(_first.current_money, 1250)
	ProfessionManager.block_skill(_first, 4)
	assert_false(ProfessionManager.record_scenery_arrival(_first, scenery, &"you_mu_cheng_huai"))
	assert_eq(_first.current_money, 1250)
	assert_signal_emit_count(ProfessionManager, "skill_triggered", 1)
	scenery.free()


func test_magic_draw_choice_validates_selection_and_preserves_return_order() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.魔术博主
	var first_card := 非遗牌.new()
	var second_card := 非遗牌.new()
	var third_card := 非遗牌.new()
	var cards: Array = [first_card, second_card, third_card]
	var observation := {&"request": null}
	var choose_second := func(request: ProfessionDrawRequest) -> void:
		observation[&"request"] = request
		ProfessionManager.submit_draw_choice(
			request.request_id,
			second_card,
			[third_card, first_card]
		)
	ProfessionManager.draw_choice_requested.connect(choose_second, CONNECT_ONE_SHOT)
	var result: ProfessionDrawResult = await ProfessionManager.request_draw_choice(_first, cards, &"feiyi")
	var request_seen: ProfessionDrawRequest = observation[&"request"] as ProfessionDrawRequest
	assert_not_null(request_seen)
	assert_eq(request_seen.timeout_seconds, 15.0)
	assert_eq(request_seen.deck_kind, &"feiyi")
	assert_eq(result.selected_card, second_card)
	assert_eq(result.return_order, [third_card, first_card])
	assert_false(result.cancelled)


func test_magic_draw_timeout_uses_first_card_and_original_order() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.魔术博主
	var cards: Array = [非遗牌.new(), 非遗牌.new(), 非遗牌.new()]
	var time_out_now := func(_request: ProfessionDrawRequest) -> void:
		ProfessionManager._on_draw_choice_timeout()
	ProfessionManager.draw_choice_requested.connect(time_out_now, CONNECT_ONE_SHOT)
	var result: ProfessionDrawResult = await ProfessionManager.request_draw_choice(_first, cards, &"feiyi")
	assert_eq(result.selected_card, cards[0])
	assert_eq(result.return_order, [cards[1], cards[2]])


func test_magic_draw_timeout_uses_latest_reordered_first_card_and_top_order() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.魔术博主
	var cards: Array = [非遗牌.new(), 非遗牌.new(), 非遗牌.new()]
	var reordered: Array = [cards[2], cards[0], cards[1]]
	var reorder_then_timeout := func(request: ProfessionDrawRequest) -> void:
		assert_true(ProfessionManager.update_draw_choice_order(request.request_id, reordered))
		ProfessionManager._on_draw_choice_timeout()
	ProfessionManager.draw_choice_requested.connect(reorder_then_timeout, CONNECT_ONE_SHOT)
	var result: ProfessionDrawResult = await ProfessionManager.request_draw_choice(_first, cards, &"feiyi")
	assert_eq(result.selected_card, cards[2], "超时应选玩家最后排列中的第一张")
	assert_eq(result.return_order, [cards[0], cards[1]], "其余牌按玩家最后排列顺序回顶")


func test_explorer_section_choice_is_optional_and_timeout_returns_null() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.探险博主
	var first_section := MapSection.new()
	var second_section := MapSection.new()
	var options: Array[MapSection] = [first_section, second_section]
	var time_out_now := func(request: ProfessionSectionChoiceRequest) -> void:
		assert_true(request.optional)
		ProfessionManager._on_section_choice_timeout()
	ProfessionManager.section_choice_requested.connect(time_out_now, CONNECT_ONE_SHOT)
	var selected: MapSection = await ProfessionManager.request_section_choice(
		_first,
		options,
		"邻格探索",
		"请选择移动终点"
	)
	assert_null(selected)
	first_section.free()
	second_section.free()


func test_session_reset_wakes_pending_draw_and_section_choices() -> void:
	_first.player_types = PlayerClass.PlayerCharacter.魔术博主
	var cards: Array = [非遗牌.new(), 非遗牌.new(), 非遗牌.new()]
	var reset_draw := func(_request: ProfessionDrawRequest) -> void:
		ProfessionManager.reset_for_new_game()
	ProfessionManager.draw_choice_requested.connect(reset_draw, CONNECT_ONE_SHOT)
	var draw_result: ProfessionDrawResult = await ProfessionManager.request_draw_choice(_first, cards, &"event")
	assert_true(draw_result.cancelled)
	assert_null(draw_result.selected_card)

	_first.player_types = PlayerClass.PlayerCharacter.探险博主
	var section := MapSection.new()
	var options: Array[MapSection] = [section]
	var reset_section := func(_request: ProfessionSectionChoiceRequest) -> void:
		ProfessionManager.reset_for_new_game()
	ProfessionManager.section_choice_requested.connect(reset_section, CONNECT_ONE_SHOT)
	var selected: MapSection = await ProfessionManager.request_section_choice(
		_first,
		options,
		"邻格探索",
		"请选择移动终点"
	)
	assert_null(selected)
	section.free()


func test_reset_clears_blocks_registered_players_and_pending_state() -> void:
	assert_true(ProfessionManager.block_skill(_first, 4))
	ProfessionManager.reset_for_new_game()
	assert_eq(ProfessionManager.get_blocked_turns(_first), 0)
	assert_true(ProfessionManager.get_registered_players().is_empty())
	assert_null(ProfessionManager.get_pending_draw_request())
	assert_null(ProfessionManager.get_pending_section_choice_request())


func _prepare_character_art(player: PlayerClass) -> void:
	player.sprite_frames = SpriteFrames.new()
	for profession_type: PlayerClass.PlayerCharacter in PlayerClass.PlayerCharacter.values():
		var animation_name := StringName(PlayerClass.PlayerCharacter.find_key(profession_type))
		if not player.sprite_frames.has_animation(animation_name):
			player.sprite_frames.add_animation(animation_name)
		player.立绘精一图组[profession_type] = null
		player.立绘精二图组[profession_type] = null
