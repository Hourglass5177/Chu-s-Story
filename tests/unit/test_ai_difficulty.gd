extends GutTest

func test_profession_move_routes_to_supply_without_spending_last_energy() -> void:
	var observation := view()
	observation.state.self.energy = 1
	observation.state.map = [
		{"position": Vector3i.ZERO, "cost": 1, "type": 1, "occupied": true, "fresh_scenery": false, "supply": true, "region": 0},
		{"position": Vector3i(1,-1,0), "cost": 1, "type": 0, "occupied": false, "fresh_scenery": false},
		{"position": Vector3i(2,-2,0), "cost": 1, "type": 4, "occupied": false, "fresh_scenery": false}]
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		policy.prepare_choice_observation(observation)
		var connector: Dictionary = observation.state.map[1]
		assert_gt(policy.profession_move_value(connector, observation, true), 0.0)
		assert_gt(policy.profession_move_value(connector, observation, false), 0.0)
		assert_eq(observation.state.self.energy, 1)
		assert_eq(observation.state.self.position, Vector3i.ZERO)

func test_profession_end_does_not_award_begin_arrival_recovery() -> void:
	var observation := view()
	observation.state.self.energy = 1
	var tile := {"position": Vector3i(1,-1,0), "cost": 1, "type": 5, "occupied": false, "fresh_scenery": true}
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 0, "occupied": true, "fresh_scenery": false}, tile]
	var policy := AIPolicy.new()
	policy.prepare_choice_observation(observation)
	assert_gt(policy.profession_move_value(tile, observation, true), policy.profession_move_value(tile, observation, false))
	assert_eq(observation.state.self.energy, 1)

func test_position_cache_distinguishes_equal_size_food_hands() -> void:
	var observation := view()
	observation.state.self.energy = 1
	observation.state.map = [
		{"position": Vector3i.ZERO, "cost": 1, "type": 0, "occupied": true, "fresh_scenery": false},
		{"position": Vector3i(1,-1,0), "cost": 1, "type": 0, "occupied": false, "fresh_scenery": false},
		{"position": Vector3i(2,-2,0), "cost": 1, "type": 1, "occupied": false, "fresh_scenery": false, "supply": true, "region": 0}]
	var weak: Dictionary = observation.state.self.duplicate(true)
	weak.foods = [{"food_id": "chi_bi_rou_gao", "level": 1}]
	var strong: Dictionary = observation.state.self.duplicate(true)
	strong.foods = [{"food_id": "jing_zhou_yu_gao", "level": 1}]
	for reverse: bool in [false, true]:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(2)
		policy.build_navigation(observation)
		if reverse: policy.position_opportunity(strong, observation)
		var weak_value := policy.position_opportunity(weak, observation)
		var strong_value := policy.position_opportunity(strong, observation)
		assert_eq(weak_value, 0.0, "Money-only food cannot fund the energy needed to collect")
		assert_gt(strong_value, weak_value, "Recovery opens a reachable collection opportunity regardless of evaluation order")

func view() -> AIObservation:
	var result := AIObservation.new()
	result.state = {"self": {"id": 0, "energy": 3, "money": 500, "score": 0, "heritage": [], "foods": [], "events": [], "food_uses": 0, "food_limit": 1, "collected": false, "worked": false, "position": Vector3i.ZERO, "achievement_score": 0}, "players": [{"id": 0, "alive": true, "score": 0}, {"id": 1, "alive": true, "score": 0}], "category_totals": {}, "region_totals": {}, "target_score": 20, "phase": 3, "map": [], "market": [], "section": {"type": 0, "arrival": false, "fresh_scenery": false}}
	result.actions = [GameAction.new(GameAction.Kind.END_PHASE, 0)]
	return result

func test_profiles_are_independent_and_match_approved_parameters() -> void:
	for difficulty: int in 3:
		var profile := AIProfile.for_difficulty(difficulty)
		assert_eq(profile.planning_depth, [2, 3, 5][difficulty])
		assert_eq(profile.beam_width, [4, 8, 24][difficulty])
		assert_eq(profile.node_budget, [512, 2048, 8192][difficulty])
		assert_eq(profile.goal_horizon, [0, 2, 4][difficulty])
		assert_almost_eq(profile.inheritance_chance, [0.6, 0.8, 1.0][difficulty], 0.00001)
		profile.inheritance_chance = 0.0
		assert_gt(AIProfile.for_difficulty(difficulty).inheritance_chance, 0.0)

func test_probability_boundaries_and_hard_endpoint() -> void:
	for chance: float in [0.6, 0.8]:
		assert_true(ComputerInheritanceService.succeeds(chance - 0.000001, chance))
		assert_false(ComputerInheritanceService.succeeds(chance, chance))
	assert_true(ComputerInheritanceService.succeeds(0.0, 1.0))
	assert_true(ComputerInheritanceService.succeeds(1.0, 1.0))
	assert_false(ComputerInheritanceService.succeeds(-0.01, 1.0))
	assert_false(ComputerInheritanceService.succeeds(1.01, 1.0))

func test_setup_copy_resize_and_legacy_default() -> void:
	var setup := SessionSetup.new(SessionSetup.GameMode.LOCAL, 1, 3)
	for index: int in 3: setup.players[index + 1].ai_difficulty = index as PlayerSetup.AIDifficulty
	var copy := setup.duplicate_snapshot()
	assert_true(copy.is_equivalent_to(setup))
	for index: int in 3: assert_eq(int(copy.to_legacy_player_data()[index + 1].ai_difficulty), index)
	setup.resize_slots(2, 3)
	for index: int in 3: assert_eq(int(setup.players[index + 2].ai_difficulty), index)
	setup.resize_slots(1, 4)
	assert_eq(int(setup.players[4].ai_difficulty), 1)
	copy.players[1].ai_difficulty = PlayerSetup.AIDifficulty.HARD
	assert_false(copy.is_equivalent_to(setup))
	assert_eq(int(PlayerSetup.new().ai_difficulty), 1)
	assert_false(AIProfile.is_valid(-1))
	assert_false(AIProfile.is_valid(3))
	assert_eq(PlayerSetup.legacy_difficulty({}), 1)
	assert_eq(PlayerSetup.legacy_difficulty({"ai_difficulty": 2.0}), 2)
	for value: Variant in [-1, 3, 1.5, "困难", "1", true, null]:
		assert_eq(PlayerSetup.legacy_difficulty({"ai_difficulty": value}), -1)

func test_zero_energy_mid_plan_is_not_an_elimination_terminal() -> void:
	var observation := view()
	observation.state.players[1].alive = false
	observation.state.players[1].score = 10
	observation.state.self.energy = 0
	var policy := AIPolicy.new()
	assert_gt(policy.evaluate(observation.state.self, observation), -100000.0)
	var end := policy.preview(observation.state.self, observation.actions[0], observation)
	assert_lt(policy.evaluate(end, observation), -999000.0)
	observation.state.self.events = [{"id": 91, "event_id": "miao_shou_hui_chun"}]
	end = policy.preview(observation.state.self, observation.actions[0], observation)
	assert_eq(int(end.energy), 3)
	assert_true(end.events.is_empty())
	assert_eq(observation.state.self.events.size(), 1)

func test_all_difficulties_recover_and_preserve_observation() -> void:
	var observation := view()
	observation.state.self.energy = 0
	var food := {"id": 99, "type": "food", "food_id": "city", "level": 0}
	observation.state.self.foods.append(food)
	observation.actions.append(GameAction.new(GameAction.Kind.USE_FOOD, 0, 99, food))
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		assert_eq(policy.choose(observation).kind, GameAction.Kind.USE_FOOD)
	assert_eq(observation.state.self.energy, 0)
	assert_eq(observation.state.self.foods.size(), 1)

func test_food_shared_immediate_preview() -> void:
	for id: String in ["dong_po_bing", "jing_zhou_yu_gao", "chi_bi_rou_gao", "re_gan_mian"]:
		var food := {"food_id": id, "level": 1}
		var actual := FoodEffectRules.immediate(id, 1, 4)
		var preview := AIPolicy.food_effect(food, {"energy": 4})
		assert_eq(int(preview.energy), int(actual.energy))
		assert_eq(int(preview.money), int(actual.money))

func test_trace_replays_stable_ids_without_world_state() -> void:
	var observation := view()
	var card := {"id": -9223372000000000000, "name": "市级食物", "type": "food", "food_id": "city", "level": 0}
	observation.state.self.energy = 0
	observation.state.self.foods.append(card)
	observation.actions.append(GameAction.new(GameAction.Kind.USE_FOOD, 0, card.id, card))
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		policy.trace_enabled = true
		var before := policy.goals.snapshot()
		var rng_before := policy.rng.state
		var action := policy.choose(observation)
		var trace := AIDecisionTrace.new()
		trace.enabled = true
		trace.capture(observation, policy, before, rng_before, {}, action, 100, true)
		assert_eq(trace.records.size(), 1)
		assert_true(AIDecisionTrace.replay(trace.records[0]).matches)
		assert_eq(int(trace.records[0].observation.state.self.foods[0].id), 1000000)

func test_goal_invalidates_and_simple_has_no_persistent_goal() -> void:
	var observation := view()
	observation.state.self.energy = 9
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 0, "occupied": true}, {"position": Vector3i(1,-1,0), "cost": 1, "type": 1, "occupied": false, "supply": true, "region": 0, "fresh_scenery": false}]
	var policy := AIPolicy.new()
	policy.choose(observation)
	assert_eq(policy.goals.current.kind, "collect")
	observation.state.map[1].supply = false
	policy.choose(observation)
	assert_true(policy.goals.current.is_empty())
	observation.state.map[1].supply = true
	policy.profile = AIProfile.for_difficulty(0)
	policy.choose(observation)
	assert_true(policy.goals.current.is_empty())

func test_node_budget_does_not_prune_root_actions() -> void:
	var observation := view()
	observation.state.self.energy = 8
	for index: int in 20:
		var food := {"id": 100 + index, "type": "food", "level": 1, "food_id": "chi_bi_rou_gao"}
		observation.state.self.foods.append(food)
		observation.actions.append(GameAction.new(GameAction.Kind.USE_FOOD, 0, food.id, food))
	var policy := AIPolicy.new()
	policy.profile.node_budget = 1
	policy.choose(observation)
	assert_gte(policy.last_nodes, observation.actions.size())
	assert_lte(policy.last_nodes, observation.actions.size() + 1)

func test_low_energy_stops_at_shop_and_can_arrive_with_zero() -> void:
	var observation := view()
	observation.state.phase = 2
	observation.state.self.energy = 1
	observation.state.section = {"type": 4, "arrival": true, "fresh_scenery": false}
	var destination := {"position": Vector3i(1,-1,0), "type": 1, "supply": true, "region": 0, "energy": 0, "fresh_scenery": false}
	observation.actions.append(GameAction.new(GameAction.Kind.MOVE, 0, 42, destination))
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		assert_eq(policy.choose(observation).kind, GameAction.Kind.END_PHASE)
		observation.state.self.energy = 0
		var next := policy.preview(observation.state.self, observation.actions[0], observation)
		assert_true(next.pending_supply)
		assert_gt(policy.evaluate(next, observation), -500.0)
		observation.state.self.energy = 1

func test_inheritance_preview_uses_configured_rate_without_mutation() -> void:
	var observation := view()
	var card := {"id": 81, "name": "国家级", "type": "heritage", "category": 6, "region": 0, "score": 5, "effective": false}
	observation.state.self.heritage.append(card)
	var action := GameAction.new(GameAction.Kind.INHERIT, 0, 81, card)
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		var failure: Dictionary = observation.state.self.duplicate(true)
		failure.energy -= 1
		failure["future"] = -0.05
		var success: Dictionary = failure.duplicate(true)
		success.heritage[0].effective = true
		var chance := policy.profile.inheritance_chance
		var next := policy.preview(observation.state.self, action, observation)
		assert_almost_eq(policy.evaluate(next, observation), chance * policy.evaluate(success, observation) + (1.0 - chance) * policy.evaluate(failure, observation), 0.0001)
	assert_false(observation.state.self.heritage[0].effective)
	assert_eq(observation.state.self.energy, 3)

func test_trace_accepts_integer_keyed_public_statistics() -> void:
	var observation := view()
	var counts: Dictionary[int, int] = {0: 5, 1: 8}
	observation.state.category_totals = counts
	var policy := AIPolicy.new()
	var before := policy.goals.snapshot()
	var random_state := policy.rng.state
	var action := policy.choose(observation)
	var trace := AIDecisionTrace.new()
	trace.enabled = true
	trace.capture(observation, policy, before, random_state, {}, action, 10, true)
	assert_true(AIDecisionTrace.replay(trace.records[0]).matches)

func test_stagnation_does_not_force_an_unsafe_move() -> void:
	var observation := view()
	observation.state.phase = 2
	observation.state.self.energy = 1
	observation.memory.idle_turns = 10
	var destination := {"position": Vector3i(1,-1,0), "type": 0, "energy": 1, "fresh_scenery": false}
	observation.actions.append(GameAction.new(GameAction.Kind.MOVE, 0, 55, destination))
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		assert_eq(policy.choose(observation).kind, GameAction.Kind.END_PHASE)

func test_productive_wait_is_kept_but_a_trapped_player_can_improve_final_score() -> void:
	var observation := view()
	observation.state.self.energy = 1
	observation.memory.idle_turns = 8
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 0, "occupied": true, "fresh_scenery": false}]
	var policy := AIPolicy.new()
	assert_true(policy.waiting_concedes_progress(observation.state.self, observation))
	observation.state.self["food_state"] = {"begin_recovery": [{"remaining": 1}]}
	assert_false(policy.waiting_concedes_progress(observation.state.self, observation))
	observation.state.self.food_state = {"permanent_food_ids": {"qing_zhuan_cha": true}}
	assert_true(policy.waiting_concedes_progress(observation.state.self, observation), "Movement discounts do not recover energy while waiting")
	observation.state.self.food_state = {}
	var card := {"id": 82, "type": "heritage", "category": 6, "region": 0, "score": 5, "effective": false}
	observation.state.self.heritage.append(card)
	observation.actions.append(GameAction.new(GameAction.Kind.INHERIT, 0, 82, card))
	assert_eq(policy.choose(observation).kind, GameAction.Kind.INHERIT)

func test_money_conversion_changes_supply_access_in_preview() -> void:
	var observation := view()
	observation.state.self.money = 100
	observation.state.self.energy = 6
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 0, "occupied": true, "fresh_scenery": false}, {"position": Vector3i(1,-1,0), "cost": 1, "type": 4, "occupied": false, "fresh_scenery": false}]
	var policy := AIPolicy.new()
	policy.build_navigation(observation)
	var funded: Dictionary = observation.state.self.duplicate(true)
	funded.money = 350
	assert_gt(policy.navigation_value(funded, observation), policy.navigation_value(observation.state.self, observation))

func test_available_winning_end_is_not_rejected_for_zero_energy() -> void:
	var observation := view()
	observation.state.players[1].alive = false
	observation.state.players[1].score = 2
	observation.state.self.energy = 0
	observation.state.self.heritage = [{"id": 83, "category": 4, "region": 0, "score": 3, "effective": true}]
	assert_gt(AIPolicy.new().evaluate(observation.state.self, observation), 999999.0)

func test_hard_buys_needed_food_when_purchase_crosses_cash_threshold() -> void:
	var observation := view()
	observation.state.self.money = 200
	observation.state.self.energy = 2
	observation.state.self["visit"] = "shop"
	observation.state.section = {"type": 4, "arrival": true, "fresh_scenery": false}
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 4, "occupied": true, "fresh_scenery": false}]
	var food := {"id": 84, "type": "food", "level": 0, "food_id": "city", "price": 150}
	observation.state["shop"] = [food]
	observation.actions = [GameAction.new(GameAction.Kind.CLOSE_SHOP, 0), GameAction.new(GameAction.Kind.BUY_FOOD, 0, 84, food)]
	var policy := AIPolicy.new()
	policy.profile = AIProfile.for_difficulty(2)
	assert_eq(policy.choose(observation).kind, GameAction.Kind.BUY_FOOD)

func test_work_income_does_not_make_the_onward_supply_route_less_safe() -> void:
	var observation := view()
	observation.state.self.money = 50
	observation.state.map = [{"position": Vector3i.ZERO, "cost": 1, "type": 3, "occupied": true, "fresh_scenery": false}, {"position": Vector3i(1,-1,0), "cost": 1, "type": 0, "occupied": false, "fresh_scenery": false}, {"position": Vector3i(2,-2,0), "cost": 1, "type": 4, "occupied": false, "fresh_scenery": false}]
	var policy := AIPolicy.new()
	policy.build_navigation(observation)
	var funded: Dictionary = observation.state.self.duplicate(true)
	funded.money = 300
	funded.energy -= 1
	assert_gte(policy.navigation_value(funded, observation), policy.navigation_value(observation.state.self, observation))
