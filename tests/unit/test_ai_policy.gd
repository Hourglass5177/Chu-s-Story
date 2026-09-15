extends GutTest

func observation() -> AIObservation:
	var result := AIObservation.new()
	result.state = {"self": {"id": 0, "energy": 0, "money": 500, "score": 0, "heritage": [], "foods": [], "events": [], "food_uses": 0, "food_limit": 1, "collected": false, "worked": false, "position": Vector3i.ZERO}, "players": [{"id": 0, "alive": true, "score": 0}, {"id": 1, "alive": true, "score": 0}], "category_totals": {}, "region_totals": {}, "target_score": 20, "phase": 3, "map": [], "market": [], "section": {"type": 0, "arrival": false, "fresh_scenery": false}}
	return result

func test_zero_energy_chooses_recovery_before_end() -> void:
	var view := observation()
	var food := {"id": 5, "type": "food", "level": 0, "food_id": "city"}
	view.state.self.foods.append(food)
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE, 0), GameAction.new(GameAction.Kind.USE_FOOD, 0, 5, food)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.USE_FOOD)
	assert_eq(view.state.self.energy, 0, "Planning never mutates the observation")
	assert_eq(view.state.self.foods.size(), 1)

func test_inheritance_threshold_is_exact() -> void:
	assert_true(ComputerInheritanceService.succeeds(0.0))
	assert_true(ComputerInheritanceService.succeeds(0.799999))
	assert_false(ComputerInheritanceService.succeeds(0.8))
	assert_false(ComputerInheritanceService.succeeds(1.0))

func test_inactive_national_card_does_not_score_or_complete_region() -> void:
	var cards: Array = [{"score": 5, "category": 6, "region": 0, "effective": false}]
	assert_eq(int(HeritageScoreRules.calculate(cards, {6: 1}, {0: 1}).total_score), 0)
	cards[0].effective = true
	assert_eq(int(HeritageScoreRules.calculate(cards, {6: 1}, {0: 1}).total_score), 12)

func test_known_winning_score_outranks_death_risk_and_includes_dead_opponent() -> void:
	var view := observation()
	var state: Dictionary = view.state.self.duplicate(true)
	state["achievement_score"] = 20
	assert_gt(AIPolicy.new().evaluate(state, view), 999999.0)
	view.state.players[1].alive = false
	view.state.players[1].score = 21
	assert_lt(AIPolicy.new().evaluate(state, view), -999000.0)

func test_same_observation_same_decision_without_world_access() -> void:
	var view := observation()
	view.state.self.energy = 3
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE), GameAction.new(GameAction.Kind.COLLECT, 0)]
	var policy := AIPolicy.new()
	policy.configure(7)
	var first := policy.choose(view).key()
	GameManager.randi_between(1, 100)
	assert_eq(policy.choose(view.copy()).key(), first)

func test_preserves_completion_when_selling_low_base_card() -> void:
	var view := observation()
	view.state.self.energy = 8
	var cards: Array = []
	for index: int in 3:
		cards.append({"id": index + 1, "type": "heritage", "category": 1, "region": index, "score": 0, "effective": true})
	view.state.self.heritage = cards
	view.state.self.score = 2
	var sale: Dictionary = cards[0].duplicate()
	sale.price = 250
	view.actions = [GameAction.new(GameAction.Kind.CLOSE_MARKET), GameAction.new(GameAction.Kind.SELL_FEIYI, 0, 1, sale)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.CLOSE_MARKET)

func test_all_event_ids_have_explicit_choice_intents() -> void:
	for event_id: StringName in EventManager.IMPLEMENTED_EVENT_IDS:
		assert_has(AIChoicePolicy.EVENT_INTENTS, String(event_id))

func test_response_distinguishes_reward_and_loss_from_same_event() -> void:
	var view := observation()
	var request := {"source_id": "pou_duo_yi_gua", "purpose": "reaction", "context": {"effect_method": "_apply_money", "amount": 500}}
	var card := {"id": 1, "type": "event", "event_id": "jin_chan_tuo_qiao"}
	assert_lt(AIChoicePolicy.value(card, request, view, AIPolicy.new()), 0.0)
	request.context.amount = -500
	assert_gt(AIChoicePolicy.value(card, request, view, AIPolicy.new()), 0.0)

func test_team_choice_uses_public_rolls() -> void:
	var view := observation()
	var request := {"source_id": "bai_ge_zheng_liu", "purpose": "choose_team", "context": {"rolls": {1: 3, 2: 11}}}
	var low := {"type": "player", "player": {"id": 1}}
	var high := {"type": "player", "player": {"id": 2}}
	assert_gt(AIChoicePolicy.value(high, request, view, AIPolicy.new()), AIChoicePolicy.value(low, request, view, AIPolicy.new()))

func test_incremental_planning_matches_unlimited_planning() -> void:
	var view := observation()
	view.state.self.energy = 3
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE), GameAction.new(GameAction.Kind.COLLECT)]
	var policy := AIPolicy.new()
	var unlimited := policy.choose(view).key()
	policy.begin_plan(view)
	var slices := 0
	while not policy.advance_plan(Time.get_ticks_usec()): slices += 1
	assert_gt(slices, 0)
	assert_eq(policy.get_plan_result().key(), unlimited)

func test_big_appetite_replaces_opponents_reward_in_final_ranking() -> void:
	var view := observation()
	view.state.self.energy = 5
	view.state.self.score = 15
	view.state.players[1].score = 21
	view.state.self["achievement_progress"] = {
		"tao_tie": {"current": 11, "target": 6, "state": 1, "owner": 1, "points": 2, "replaces": ""},
		"da_wei_dai": {"current": 11, "target": 12, "state": 0, "owner": -1, "points": 5, "replaces": "tao_tie"}
	}
	var food := {"id": 12, "type": "food", "level": 0, "food_id": "city"}
	view.state.self.foods.append(food)
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE), GameAction.new(GameAction.Kind.USE_FOOD, 0, 12, food)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.USE_FOOD)

func test_shop_purchase_requires_closing_before_consumption() -> void:
	var view := observation()
	var food := {"id": 45, "type": "food", "level": 0, "food_id": "city", "price": 150}
	view.state["shop"] = [food]
	view.state.self["visit"] = "shop"
	view.state["after_visit_actions"] = [{"kind": GameAction.Kind.END_PHASE, "target": 0, "data": {}}]
	view.actions = [GameAction.new(GameAction.Kind.CLOSE_SHOP, 0), GameAction.new(GameAction.Kind.BUY_FOOD, 0, 45, food)]
	var policy := AIPolicy.new()
	assert_eq(policy.choose(view).kind, GameAction.Kind.BUY_FOOD, "Three steps can buy, close, then recover")
	var bought := policy.preview(view.state.self, view.actions[1], view)
	var inside := policy._continuation_actions(bought)
	assert_false(inside.any(func(a: GameAction): return a.kind == GameAction.Kind.USE_FOOD))
	var closed := policy.preview(bought, view.actions[0], view)
	assert_true(policy._continuation_actions(closed).any(func(a: GameAction): return a.kind == GameAction.Kind.USE_FOOD))
	assert_true(view.state.self.foods.is_empty())

func test_money_then_market_purchase_completes_a_collection() -> void:
	var view := observation()
	view.state.self.energy = 6
	view.state.self.money = 0
	var music := {"id": 11, "type": "heritage", "category": 1, "region": 0, "score": 0, "effective": true}
	view.state.self.heritage = [music]
	view.state.market = [{"id": 12, "type": "heritage", "category": 2, "region": 1, "score": 1, "effective": true, "price": 500}]
	view.state.category_totals = {2: 1}
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE, 0), GameAction.new(GameAction.Kind.USE_FEIYI, 0, 11, music), GameAction.new(GameAction.Kind.OPEN_MARKET, 0)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.USE_FEIYI, "Use money card, enter the known market, buy the completing card")

func test_stagnating_worker_leaves_even_when_accumulated_money_is_large() -> void:
	var view := observation()
	view.state.phase = 2
	view.state.self.energy = 1
	view.state.self.money = 140000
	view.memory.idle_turns = 2
	var destination := {"type": 4, "energy": 1, "position": Vector3i(1, -1, 0), "supply": false, "visited": 0}
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE, 0), GameAction.new(GameAction.Kind.MOVE, 0, 42, destination)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.MOVE, "Money alone must not trap an AI in an endless free-work loop")

func test_inheritance_can_contest_a_leading_eliminated_players_score() -> void:
	var view := observation()
	view.state.self.energy = 3
	view.state.self.score = 17
	view.state.players[1].alive = false
	view.state.players[1].score = 21
	var national := {"id": 71, "type": "heritage", "category": 6, "region": 8, "score": 5, "effective": false}
	view.state.self.heritage = [national]
	view.actions = [GameAction.new(GameAction.Kind.END_PHASE, 0), GameAction.new(GameAction.Kind.INHERIT, 0, 71, national)]
	assert_eq(AIPolicy.new().choose(view).kind, GameAction.Kind.INHERIT, "An 80% winning chance outranks conceding a certain loss")
