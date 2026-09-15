class_name AIPolicy
extends RefCounted

## No live objects or Autoload access: all planning runs against copied observations.
var profile := AIProfile.new()
var rng := RandomNumberGenerator.new()
var last_nodes: int = 0
var goals := AIGoalPlanner.new()
var trace_candidates: Dictionary = {}
var trace_enabled: bool = false
var _collection_estimates: Dictionary = {}
var _root_goal_potential: float = 0.0
var _root_navigation: float = 0.0
var _root_count: int = 0
var _position_potentials: Dictionary = {}
var _opportunity_routes: Dictionary = {}
var _navigation_map: Dictionary = {}
var _route_costs: Dictionary = {}

func configure(seed_value: int) -> void:
	rng.seed = seed_value

static func food_effect(card: Dictionary, state: Dictionary) -> Dictionary:
	var effect := {"energy": 0, "money": 0, "future": 0.0, "unknown": false}
	var immediate := FoodEffectRules.immediate(String(card.get("food_id", "")), int(card.get("level", -1)), int(state.energy))
	if not immediate.is_empty():
		effect.merge(immediate, true)
		return effect
	match String(card.get("food_id", "")):
		"bai_yang_dou_gan", "huang_zhou_dong_po_rou":
			effect.future = 160.0
			effect.unknown = true
		"jing_men_san_zheng":
			effect.future = 50.0
			effect.unknown = true
		"tian_men_san_zheng":
			effect.energy = 1
			effect.future = 33.0
			effect.unknown = true
		"mian_yang_san_zheng":
			effect.energy = 2
			effect.future = 17.0
			effect.unknown = true
		"du_jia_ji", "you_men_da_xia", "qi_chun_suan_mi_fen": effect.future = 30.0
		"qing_zhuan_cha": effect.future = 65.0
		"huang_shi_gang_bing":
			effect.energy = 2
			effect.future = 5.0
		"tong_shan_bao_tuo":
			effect.energy = 4
			effect.future = -15.0
		"pi_tiao_shan_yu":
			effect.energy = 2
			effect.future = 15.0
		"shen_nong_jia_la_rou":
			effect.energy = 1
			effect.future = 28.0
		"tu_jia_tai_ge_zi", "xiao_gan_mi_jiu", "shang_xiang_feng_gan_ji", "tu_jia_la_rou": effect.future = 10.0
		"wu_xue_fo_shou_shan_yao", "ying_shan_yu_mian": effect.future = 30.0
		"mao_zui_lu_ji", "sui_zhou_mi_zao", "wu_xue_su_tang":
			effect.energy = 1
			effect.future = 10.0
			effect.unknown = true
		"xiang_yang_chan_ti":
			effect.future = 8.0
			effect.unknown = true
		"zao_yang_suan_jiang_mian":
			effect.energy = 1
			effect.future = -15.0
			effect.unknown = true
		"zhang_guan_he_zha":
			effect.energy = 4
			effect.unknown = true
		"san_he_tang", "zhu_shan_lan_dou_fu":
			effect.future = 5.0
			effect.unknown = true
		"qian_zhang_kou_rou":
			effect.energy = -1
			effect.future = 170.0
			effect.unknown = true
		"fang_xian_huang_jiu":
			effect.future = 300.0
			effect.unknown = true
		"tu_jia_you_cha_tang": effect.future = 20.0
		"tuan_feng_gou_jiao": effect.future = 35.0
	return effect

func collection_score(cards: Array, observation: AIObservation) -> int:
	return int(HeritageScoreRules.calculate(cards, observation.state.category_totals, observation.state.region_totals).total_score)

func card_value(card: Dictionary, observation: AIObservation) -> float:
	var own: Dictionary = observation.state.self
	if card.get("type") == "heritage":
		var cards: Array = own.heritage.duplicate(true)
		var present := false
		for existing: Dictionary in cards:
			if existing.id == card.id:
				cards.erase(existing)
				present = true
				break
		var without := collection_score(cards, observation)
		cards.append(card)
		var value := float(collection_score(cards, observation) - without) * profile.score_weight
		if not bool(card.effective):
			var unlocked := cards.duplicate(true)
			unlocked.back()["effective"] = true
			value += maxf(0.0, (collection_score(unlocked, observation) - without) * profile.score_weight * profile.inheritance_chance - 30.0)
		match int(card.category):
			0: value += 65.0 if int(own.energy) < 4 else 18.0
			1: value += 15.0
			2: value += 6.0
			3: value += 22.0
			5: value += 25.0
		return value + (0.0 if present else 1.0)
	if card.get("type") == "food":
		var effect := food_effect(card, own)
		return maxf(8.0, mini(12 - int(own.energy), int(effect.energy)) * profile.energy_weight + float(effect.money) * profile.money_weight + float(effect.future))
	if card.get("type") == "event":
		return 70.0 if card.get("event_id") == "miao_shou_hui_chun" else 30.0
	return 0.0

func evaluate(state: Dictionary, observation: AIObservation) -> float:
	if state.has("chance_value"): return float(state.chance_value)
	var score := collection_score(state.heritage, observation) + int(state.achievement_score)
	var highest_other := -1
	var dead := 0
	for player: Dictionary in observation.state.players:
		if int(player.id) != int(state.id): highest_other = maxi(highest_other, int(player.score) + int(state.get("opponent_score_deltas", {}).get(int(player.id), 0)))
		if not bool(player.alive): dead += 1
	var terminal := score >= int(observation.state.target_score) or highest_other >= int(observation.state.target_score) or (bool(state.get("end_turn", false)) and dead + (1 if int(state.energy) <= 0 else 0) >= 2)
	# With one elimination already recorded, ending this zero-energy turn can secure
	# the top final rank. Recovery remains optional, so recognise the available win.
	terminal = terminal or (dead >= 1 and int(state.energy) <= 0 and score >= highest_other)
	if terminal:
		return 1000000.0 + score if score >= highest_other else -1000000.0 + score
	var value := score * profile.score_weight + sqrt(maxf(0, float(state.money))) * 0.9
	# Reserve spending power for the next supply visit; surplus currency has diminishing value.
	var money := maxf(0, float(state.money))
	value += minf(money, 500.0) * 0.08 + clampf(money - 500.0, 0.0, 500.0) * 0.03 + maxf(0.0, money - 1000.0) * 0.005 - sqrt(money) * 0.9
	value += mini(6, int(state.energy)) * 18.0 + maxi(0, int(state.energy) - 6) * 4.0
	if int(state.energy) <= 0:
		var can_revive := false
		for card: Dictionary in state.events:
			if card.get("event_id") == "miao_shou_hui_chun": can_revive = true
		value += 36.0 if can_revive else (-250.0 if bool(state.get("pending_supply", false)) else -profile.unsafe_penalty)
	value += float(state.get("future", 0.0))
	value += goals.potential(state) - _root_goal_potential
	if profile.difficulty == 2: value += 1.5 * (navigation_value(state, observation) - _root_navigation)
	if profile.difficulty == 2: value -= opponent_threat(observation) * maxf(0.0, 1.0 - float(score) / maxf(1, int(observation.state.target_score)))
	var stored_recovery := 0
	for card: Dictionary in state.foods:
		value += 12.0 + minf(20.0, float(food_effect(card, state).future) * 0.25)
		if profile.difficulty == 2 or int(state.energy) <= 4:
			var recovery := mini(8 - stored_recovery, maxi(0, int(food_effect(card, state).energy)))
			stored_recovery += recovery
			value += recovery * 10.0
	for card: Dictionary in state.events: value += 18.0
	return value

func _remove(cards: Array, id: int) -> void:
	for card: Dictionary in cards:
		if int(card.id) == id:
			cards.erase(card)
			return

func preview(state: Dictionary, action: GameAction, observation: AIObservation) -> Dictionary:
	var next := state.duplicate(true)
	next["future"] = float(next.get("future", 0.0)) - 0.05
	var data := action.data
	match action.kind:
		GameAction.Kind.CLOSE_SHOP, GameAction.Kind.CLOSE_MARKET:
			next["visit"] = ""
			next["visit_closed"] = true
		GameAction.Kind.END_PHASE:
			# A bounded opportunity cost discourages aimless waiting without overriding legality or safety.
			if int(observation.state.phase) == 2 and int(observation.memory.get("idle_turns", 0)) >= 2:
				next.future -= 35.0
			if waiting_concedes_progress(state, observation): next.future -= minf(profile.unsafe_penalty * 2.0, float(observation.memory.get("idle_turns", 0)) * 400.0)
			if action.kind == GameAction.Kind.END_PHASE and int(observation.state.phase) == 2:
				var tile: Dictionary = observation.state.section
				if bool(tile.arrival):
					next.future += section_value(tile, next)
					if bool(tile.fresh_scenery): next.energy = mini(12, int(next.energy) + 3)
					if int(tile.type) == 4 and int(next.money) >= 150 and int(next.get("statuses", {}).get("skip_action", 0)) <= 0: next["pending_supply"] = true
				if profile.difficulty != 2: next.future += navigation_value(next, observation) - navigation_value(state, observation)
			if int(observation.state.phase) == 3:
				next["pending_supply"] = false
				next["end_turn"] = true
				if int(next.energy) <= 0:
					for card: Dictionary in next.events:
						if card.get("event_id") == "miao_shou_hui_chun":
							_remove(next.events, int(card.id))
							next.energy = 3
							break
			next["stop"] = true
		GameAction.Kind.USE_FEIYI:
			_remove(next.heritage, action.target)
			if int(data.category) == 0: next.energy = mini(12, int(next.energy) + 3)
			elif int(data.category) == 1: next.money += 500
			else:
				next.future += minf(7.0, float(next.get("steps", 0))) * (12.0 if int(next.energy) > 3 else 2.0)
				next["stop"] = true
		GameAction.Kind.USE_FOOD:
			_remove(next.foods, action.target)
			next.food_uses += 1
			_advance_achievement(next, "tao_tie", 1)
			_advance_achievement(next, "da_wei_dai", 1)
			var effect := contextual_food_effect(data, next, observation)
			next.energy = clampi(int(next.energy) + int(effect.energy), 0, 12)
			next.money += int(effect.money)
			next.future += float(effect.future)
			next["stop"] = bool(effect.unknown)
		GameAction.Kind.USE_EVENT:
			_remove(next.events, action.target)
			next.future += retained_event_value(data, next, observation)
			next["stop"] = true
		GameAction.Kind.INHERIT:
			next.energy -= 1
			var cards: Array = next.heritage.duplicate(true)
			for card: Dictionary in cards:
				if int(card.id) == action.target: card.effective = true
			var success_state: Dictionary = next.duplicate(true)
			success_state.heritage = cards
			# Evaluate both real outcomes, including final ranking, before taking their expectation.
			next["chance_value"] = profile.inheritance_chance * evaluate(success_state, observation) + (1.0 - profile.inheritance_chance) * evaluate(next, observation)
			next["stop"] = true
		GameAction.Kind.COLLECT:
			next.energy -= 1
			next.future += expected_collection(int(data.get("region", observation.state.section.get("region", -1))), observation)
			next.collected = true
			next["stop"] = true
		GameAction.Kind.WORK:
			next.energy -= int(data.work_cost)
			next.money += int(data.get("work_income", 250))
			next.worked = true
		GameAction.Kind.BUY_FOOD:
			next.money -= int(data.price)
			next.foods.append(data.duplicate(true))
		GameAction.Kind.BUY_FEIYI:
			next.money -= int(data.price)
			next.heritage.append(data.duplicate(true))
			next["market_remaining"] = int(next.get("market_remaining", 3)) - 1
		GameAction.Kind.SELL_FEIYI:
			next.money += int(data.price)
			_remove(next.heritage, action.target)
		GameAction.Kind.OPEN_SHOP:
			next.future += (maxf(12.0, 6 - int(next.energy)) * 12.0 if next.foods.is_empty() else 6.0) if int(next.money) >= 150 else -1.0
			next["stop"] = true
		GameAction.Kind.REFRESH_SHOP:
			next.future += 5.0 if int(next.money) >= 150 and next.foods.is_empty() and int(next.energy) < 5 else -1.0
			next["stop"] = true
		GameAction.Kind.OPEN_MARKET:
			next["visit"] = "market"
		GameAction.Kind.MOVE:
			next.energy -= int(data.energy)
			next.position = data.position
			next.future += section_value(data, next)
			if bool(data.get("fresh_scenery", false)): next.energy = mini(12, int(next.energy) + 3)
			if int(data.type) == 4 and int(next.money) >= 150 and int(next.get("statuses", {}).get("skip_action", 0)) <= 0: next["pending_supply"] = true
			if profile.difficulty != 2: next.future += navigation_value(next, observation) - navigation_value(state, observation)
			if profile.difficulty == 2:
				next.future += position_opportunity(next, observation) - position_opportunity(state, observation)
			var history: Array = observation.memory.get("movement_positions", [])
			if history.has(data.position): next.future -= 55.0 * history.count(data.position)
			next["stop"] = true
	if int(next.energy) >= 12: _advance_achievement(next, "chao_yue_ren_lei", 12, true)
	if action.kind == GameAction.Kind.MOVE and bool(data.get("fresh_scenery", false)):
		_advance_achievement(next, "you_shan_wan_shui", 1)
	return next

func waiting_concedes_progress(state: Dictionary, observation: AIObservation) -> bool:
	if observation.state.get("map", []).is_empty() or int(observation.memory.get("idle_turns", 0)) < 2: return false
	var moving := int(observation.state.phase) == 2
	if moving:
		for card: Dictionary in state.foods:
			if int(food_effect(card, state).energy) > 0: return false
		var tile: Dictionary = observation.state.section
		if bool(tile.get("arrival", false)):
			if int(tile.type) == 4 and int(state.money) >= 150: return false
			if int(tile.type) == 3 and int(state.money) < 400: return false
	var food_state: Dictionary = state.get("food_state", {})
	if not food_state.get("begin_recovery", []).is_empty() or not food_state.get("skip_moving", []).is_empty(): return false
	for card: Dictionary in state.heritage:
		if int(card.category) == 0 and moving: return false
		# Reaching ACTION is productive if an untried inheritance can still improve the score.
		if int(card.category) == 6 and not bool(card.effective) and int(observation.state.phase) == 2: return false
	var highest_other := -1
	var other_dead := false
	for other: Dictionary in observation.state.players:
		if int(other.id) == int(state.id): continue
		highest_other = maxi(highest_other, int(other.score))
		other_dead = other_dead or not bool(other.alive)
	# Repeating a resource-invariant losing/tied turn has no recovery or income value.
	# Compare exploration/collection/inheritance risks rather than assuming endless waiting is safe.
	return other_dead or int(state.score) <= highest_other

func _advance_achievement(state: Dictionary, id: String, amount: int, maximum: bool = false) -> void:
	var progress: Dictionary = state.get("achievement_progress", {})
	if not progress.has(id): return
	var achievement: Dictionary = progress[id]
	achievement.current = maxi(int(achievement.current), amount) if maximum else int(achievement.current) + amount
	if int(achievement.state) != 0: return
	if int(achievement.current) < int(achievement.target):
		state.future += 6.0 * amount
		return
	achievement.state = 1
	achievement.owner = int(state.id)
	state.achievement_score += int(achievement.points)
	var replaces := String(achievement.replaces)
	if replaces.is_empty() or not progress.has(replaces): return
	var replaced: Dictionary = progress[replaces]
	if int(replaced.owner) == int(state.id):
		state.achievement_score -= int(replaced.points)
	elif int(replaced.owner) >= 0:
		if not state.has("opponent_score_deltas"): state["opponent_score_deltas"] = {}
		state.opponent_score_deltas[int(replaced.owner)] = -int(replaced.points)
	replaced.state = 2
	replaced.owner = -1

func section_value(data: Dictionary, own: Dictionary) -> float:
	match int(data.type):
		1:
			if not bool(data.supply) or int(own.energy) < 1: return 0.0
			if profile.difficulty == 2 and _plan_observation != null and data.has("region"):
				return 160.0 + clampf((expected_collection(int(data.region), _plan_observation) - 150.0) * 0.25, -40.0, 70.0)
			return 160.0
		2: return 30.0
		3:
			if int(own.money) < 400 and int(own.energy) >= 1 and int(data.visited) == 0:
				return 150.0 if int(own.money) < 150 and own.foods.is_empty() else 30.0
			return -2.0
		4:
			if int(own.money) < 150: return 0.0
			if int(own.energy) <= 3 and own.foods.is_empty(): return 270.0 + (3 - int(own.energy)) * 35.0
			return 48.0 if int(own.energy) < 6 or own.foods.is_empty() else 0.0
		5: return 20.0 if bool(data.get("fresh_scenery", false)) else -5.0
		6: return 24.0 if int(own.money) >= 500 else 0.0
	return -1.0

var _plan_observation: AIObservation
var _plan_excluded: Dictionary = {}
var _plan_tasks: Array = []
var _plan_children: Array = []
var _plan_depth: int = 0
var _plan_cursor: int = 0
var _plan_best: GameAction
var _plan_best_value: float = -INF

func choose(observation: AIObservation, excluded: Dictionary = {}) -> GameAction:
	begin_plan(observation, excluded)
	while not advance_plan(0): pass
	return get_plan_result()

func prepare_choice_observation(observation: AIObservation) -> void:
	_plan_observation = observation
	_collection_estimates.clear()
	_position_potentials.clear()
	build_navigation(observation)

func begin_plan(observation: AIObservation, excluded: Dictionary = {}) -> void:
	last_nodes = 0
	trace_candidates.clear()
	_collection_estimates.clear()
	_position_potentials.clear()
	_plan_observation = observation
	_plan_excluded = excluded.duplicate()
	_plan_depth = 0
	_plan_best = null
	_plan_best_value = -INF
	_plan_children.clear()
	_plan_tasks.clear()
	_plan_cursor = 0
	build_navigation(observation)
	_root_navigation = navigation_value(observation.state.self, observation)
	goals.update(observation, self)
	_root_goal_potential = goals.potential(observation.state.self)
	var state: Dictionary = observation.state.self.duplicate(true)
	state["achievement_score"] = int(state.score) - collection_score(state.heritage, observation)
	state["future"] = 0.0
	if not state.has("visit"):
		state["visit"] = ""
		for action: GameAction in observation.actions:
			if action.kind == GameAction.Kind.CLOSE_MARKET: state.visit = "market"
			if action.kind == GameAction.Kind.CLOSE_SHOP: state.visit = "shop"
	_enqueue_plan_node({"state": state, "first": null, "used": {}})
	_root_count = _plan_tasks.size()

func _enqueue_plan_node(node: Dictionary) -> void:
	if bool(node.state.get("stop", false)): return
	var actions: Array[GameAction] = _plan_observation.actions.duplicate()
	if _plan_depth > 0:
		actions = _continuation_actions(node.state)
	var seen: Dictionary = {}
	for action: GameAction in actions:
		if seen.has(action.key()): continue
		seen[action.key()] = true
		if _plan_excluded.has(action.key()) or node.used.has(action.key()): continue
		if action.kind in [GameAction.Kind.BUY_FOOD, GameAction.Kind.BUY_FEIYI] and int(action.data.price) > int(node.state.money): continue
		if action.kind == GameAction.Kind.BUY_FEIYI and int(node.state.get("market_remaining", 3)) <= 0: continue
		if action.kind == GameAction.Kind.USE_FOOD and (int(node.state.food_uses) >= int(node.state.food_limit) or not _contains(node.state.foods, action.target)): continue
		if action.kind in [GameAction.Kind.SELL_FEIYI, GameAction.Kind.USE_FEIYI, GameAction.Kind.INHERIT] and not _contains(node.state.heritage, action.target): continue
		if action.kind == GameAction.Kind.USE_EVENT and not _contains(node.state.events, action.target): continue
		if action.kind == GameAction.Kind.WORK and bool(node.state.worked): continue
		if action.kind == GameAction.Kind.WORK and int(node.state.energy) < int(action.data.work_cost): continue
		if action.kind == GameAction.Kind.COLLECT and (bool(node.state.collected) or int(node.state.energy) < 1): continue
		if action.kind == GameAction.Kind.INHERIT and int(node.state.energy) < 1: continue
		_plan_tasks.append({"node": node, "action": action})

func _continuation_actions(state: Dictionary) -> Array[GameAction]:
	var actions: Array[GameAction] = []
	var actor := int(state.id)
	match String(state.get("visit", "")):
		"shop":
			actions.append(GameAction.new(GameAction.Kind.CLOSE_SHOP, actor))
			for card: Dictionary in _plan_observation.state.get("shop", []):
				if not _contains(state.foods, card.id): actions.append(GameAction.new(GameAction.Kind.BUY_FOOD, actor, card.id, card))
		"market":
			actions.append(GameAction.new(GameAction.Kind.CLOSE_MARKET, actor))
			for card: Dictionary in _plan_observation.state.market:
				if not _contains(state.heritage, card.id): actions.append(GameAction.new(GameAction.Kind.BUY_FEIYI, actor, card.id, card))
			for card: Dictionary in state.heritage:
				if int(card.category) == 6 or not bool(card.effective): continue
				var sale: Dictionary = card.duplicate(true)
				sale.price = int(card.get("sell_price", 250 + 50 * int(card.score)))
				actions.append(GameAction.new(GameAction.Kind.SELL_FEIYI, actor, card.id, sale))
		_:
			for action: GameAction in _plan_observation.actions:
				if action.kind not in [GameAction.Kind.BUY_FOOD, GameAction.Kind.REFRESH_SHOP, GameAction.Kind.CLOSE_SHOP, GameAction.Kind.BUY_FEIYI, GameAction.Kind.SELL_FEIYI, GameAction.Kind.CLOSE_MARKET]: actions.append(action)
			for saved: Dictionary in _plan_observation.state.get("after_visit_actions", []):
				actions.append(GameAction.new(int(saved.kind) as GameAction.Kind, actor, int(saved.target), saved.data))
			for card: Dictionary in state.foods:
				if int(_plan_observation.state.phase) == 3: actions.append(GameAction.new(GameAction.Kind.USE_FOOD, actor, card.id, card))
			for card: Dictionary in state.heritage:
				if int(_plan_observation.state.phase) == 3 and int(card.category) in [0, 1]: actions.append(GameAction.new(GameAction.Kind.USE_FEIYI, actor, card.id, card))
			if bool(state.get("visit_closed", false)):
				actions = actions.filter(func(a: GameAction): return a.kind not in [GameAction.Kind.OPEN_SHOP, GameAction.Kind.OPEN_MARKET])
	return actions

func _contains(cards: Array, id: int) -> bool:
	for card: Dictionary in cards:
		if int(card.id) == id: return true
	return false

## deadline_usec=0 drives the identical planner without yielding in batch tests.
func advance_plan(deadline_usec: int) -> bool:
	while true:
		if _plan_depth > 0 and last_nodes - _root_count >= profile.node_budget: return true
		if _plan_cursor >= _plan_tasks.size():
			_plan_depth += 1
			if _plan_depth >= profile.planning_depth or _plan_children.is_empty(): return true
			_plan_children.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.value) > float(b.value))
			var beam: Array = _plan_children.slice(0, profile.beam_width)
			# Keep self-rescue and finishing branches even when ordinary beam pruning is full.
			for candidate: Dictionary in _plan_children:
				if beam.has(candidate): continue
				if float(candidate.value) >= 999999.0 or (int(_plan_observation.state.self.energy) <= 1 and int(candidate.state.energy) > 0):
					beam.append(candidate)
					if beam.size() >= profile.beam_width + 4: break
			_plan_tasks.clear()
			_plan_children.clear()
			_plan_cursor = 0
			for node: Dictionary in beam: _enqueue_plan_node(node)
			if _plan_tasks.is_empty(): return true
		var task: Dictionary = _plan_tasks[_plan_cursor]
		_plan_cursor += 1
		var node: Dictionary = task.node
		var action: GameAction = task.action
		var next := preview(node.state, action, _plan_observation)
		var value := evaluate(next, _plan_observation)
		last_nodes += 1
		var first: GameAction = action if node.first == null else node.first
		if trace_enabled:
			var key := first.key()
			if not trace_candidates.has(key) or value > float(trace_candidates[key].value):
				trace_candidates[key] = {"action": key, "value": value, "depth": _plan_depth + 1, "score": collection_score(next.heritage, _plan_observation), "energy": next.energy, "money": next.money, "future": next.get("future", 0.0), "goal": goals.potential(next) - _root_goal_potential}
		if value > _plan_best_value:
			_plan_best_value = value
			_plan_best = first
		var used: Dictionary = node.used.duplicate()
		used[action.key()] = true
		_plan_children.append({"state": next, "first": first, "used": used, "value": value})
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec: return false
	return true

func get_plan_result() -> GameAction:
	return _plan_best


var _rescue_distances: Dictionary = {}
var _goal_distances: Dictionary = {}
var _scenery_distances: Dictionary = {}
var _shop_distances: Dictionary = {}
var _work_distances: Dictionary = {}

func build_navigation(observation: AIObservation) -> void:
	_rescue_distances.clear()
	_goal_distances.clear()
	var map: Dictionary = {}
	var rescue: Array = []
	var goals: Array = []
	var scenery: Array = []
	var shops: Array = []
	var workplaces: Array = []
	for tile: Dictionary in observation.state.get("map", []):
		map[tile.position] = tile
		var available: bool = not bool(tile.occupied) or tile.position == observation.state.self.position
		if bool(tile.get("fresh_scenery", false)) and available: scenery.append(tile.position)
		if int(tile.type) == 4 and available: shops.append(tile.position)
		if int(tile.type) == 3 and available and (int(tile.get("visited", 0)) == 0 or tile.position == observation.state.self.position): workplaces.append(tile.position)
		if bool(tile.get("fresh_scenery", false)) and not bool(tile.occupied): rescue.append(tile.position)
		if int(tile.type) == 4 and int(observation.state.self.money) >= 150 and not bool(tile.occupied): rescue.append(tile.position)
		if int(tile.type) == 3 and int(tile.get("visited", 0)) == 0 and int(observation.state.self.money) < 150 and not bool(tile.occupied): rescue.append(tile.position)
		if int(tile.type) == 1 and bool(tile.supply) and not bool(tile.occupied): goals.append(tile.position)
	_navigation_map = map
	var costs: Dictionary = {}
	for position: Vector3i in map: costs[position] = int(map[position].cost)
	# These reverse paths depend only on public topology and movement costs, not on
	# cards, supply, occupancy, chosen goals or random state. Keep them across decisions.
	if costs != _route_costs:
		_route_costs = costs
		_opportunity_routes.clear()
	_rescue_distances = _distances(map, rescue)
	_goal_distances = _distances(map, goals)
	_scenery_distances = _distances(map, scenery)
	_shop_distances = _distances(map, shops)
	# Work supplies money, not energy. Include the onward trip to a shop so earning
	# enough to buy food cannot make the same route appear suddenly less safe.
	var work_costs: Dictionary = {}
	for workplace: Vector3i in workplaces:
		work_costs[workplace] = int(_shop_distances.get(workplace, 30)) + (0 if int(observation.state.self.get("profession", -1)) == 5 else 1)
	_work_distances = _distances(map, workplaces, work_costs)

func _distances(map: Dictionary, sources: Array, initial_costs: Dictionary = {}) -> Dictionary:
	var distance: Dictionary = {}
	var frontier: Array = sources.duplicate()
	for source in sources: distance[source] = int(initial_costs.get(source, 0))
	var directions: Array[Vector3i] = [Vector3i(1,-1,0),Vector3i(1,0,-1),Vector3i(0,1,-1),Vector3i(-1,1,0),Vector3i(-1,0,1),Vector3i(0,-1,1)]
	while not frontier.is_empty():
		var position: Vector3i = frontier.pop_front()
		for direction: Vector3i in directions:
			var next := position + direction
			if not map.has(next): continue
			var cost: int = int(distance[position]) + int(map[position].cost)
			if cost < int(distance.get(next, 10000)):
				distance[next] = cost
				frontier.append(next)
	return distance

func navigation_value(state: Dictionary, _observation: AIObservation) -> float:
	var supply := int(_scenery_distances.get(state.position, 30))
	# A purchase converts spending power into an owned supply. Do not charge an
	# abrupt second survival penalty for crossing the cash threshold within a plan.
	# The next real observation recomputes access from the new wallet and inventory.
	var available_money := maxi(int(state.money), int(_observation.state.self.money))
	if available_money >= 150:
		supply = mini(supply, int(_shop_distances.get(state.position, 30)))
	elif int(state.get("statuses", {}).get("work_banned", 0)) <= 0:
		supply = mini(supply, int(_work_distances.get(state.position, 30)))
	var energy := int(state.energy)
	for card: Dictionary in state.foods: energy += maxi(0, int(food_effect(card, state).energy))
	for card: Dictionary in state.heritage:
		if int(card.category) == 0: energy += 3
	var goal := int(_goal_distances.get(state.position, 30))
	var value := -float(goal) * 5.0
	if energy < supply + 2:
		value -= 120.0 + (supply - energy) * 30.0
		value -= supply * 15.0
	else:
		value -= supply * 2.0
	return value

func inheritance_gain(card: Dictionary, observation: AIObservation) -> int:
	var cards: Array = observation.state.self.heritage.duplicate(true)
	var before := collection_score(cards, observation)
	for item: Dictionary in cards:
		if item.id == card.id: item.effective = true
	return collection_score(cards, observation) - before

func region_completion_progress(region: int, own: Dictionary) -> int:
	var count := 0
	for card: Dictionary in own.heritage:
		if bool(card.effective) and int(card.region) == region: count += 1
	return count

func expected_collection(region: int, observation: AIObservation) -> float:
	if _collection_estimates.has(region): return float(_collection_estimates[region])
	var own: Dictionary = observation.state.self
	var cards: Array = own.heritage.duplicate(true)
	var base := collection_score(cards, observation)
	var value := 0.0
	var count := 0
	for entry: Dictionary in observation.state.get("public_catalog", []):
		if region >= 0 and int(entry.region) != region: continue
		# Subtract only cards publicly visible in collections/market, never peek at remaining decks.
		var visible := false
		for player: Dictionary in observation.state.players:
			for card: Dictionary in player.get("heritage", []):
				if card.get("name") == entry.name: visible = true
		for card: Dictionary in observation.state.market:
			if card.get("name") == entry.name: visible = true
		if visible: continue
		var candidate := entry.duplicate(true)
		candidate.id = -1
		cards.append(candidate)
		var gain := float(collection_score(cards, observation) - base) * profile.score_weight
		if int(entry.category) == 6:
			candidate.effective = true
			gain = (collection_score(cards, observation) - base) * profile.score_weight * profile.inheritance_chance - 30.0
		elif int(entry.category) == 4:
			gain += mini(3, 12 - int(own.energy)) * 18.0 + 50.0
		elif int(entry.category) == 0: gain += 35.0 if int(own.energy) < 6 else 10.0
		cards.pop_back()
		value += maxf(0.0, gain)
		count += 1
	var result := value / count if count > 0 else 150.0
	_collection_estimates[region] = result
	return result

func contextual_food_effect(card: Dictionary, state: Dictionary, observation: AIObservation) -> Dictionary:
	var effect := food_effect(card, state)
	var id := String(card.get("food_id", ""))
	var horizon := maxi(1, profile.goal_horizon)
	var energy_value := 28.0 if int(state.energy) < 5 else 12.0
	match id:
		"san_he_tang", "zhu_shan_lan_dou_fu":
			effect.future = -1.0
			for other: Dictionary in observation.state.players:
				if int(other.id) != int(state.id) and bool(other.alive): effect.future = maxf(effect.future, exchange_value(other, observation))
		"zao_yang_suan_jiang_mian":
			var threat := 0.0
			for other: Dictionary in observation.state.players:
				if int(other.id) != int(state.id) and bool(other.alive) and int(other.score) >= int(observation.state.target_score) - 5: threat = 70.0
			effect.future = threat - 80.0
		"zhang_guan_he_zha":
			var least_help := INF
			for other: Dictionary in observation.state.players:
				if int(other.id) == int(state.id) or not bool(other.alive): continue
				least_help = minf(least_help, mini(4, 12 - int(other.energy)) * (12.0 if int(other.score) >= int(state.score) else 5.0))
			effect.future = -least_help if is_finite(least_help) else 0.0
		"bai_yang_dou_gan": effect.future = expected_collection(1, observation)
		"huang_zhou_dong_po_rou": effect.future = expected_collection(2, observation)
		"jing_men_san_zheng": effect.future = 3.0 * (28.0 if state.foods.size() < 2 else 12.0)
		"tian_men_san_zheng": effect.future = 2.0 * (28.0 if state.foods.size() < 2 else 12.0)
		"mian_yang_san_zheng": effect.future = 28.0 if state.foods.size() < 2 else 12.0
		"du_jia_ji", "you_men_da_xia": effect.future = 4.0 * energy_value
		"qi_chun_suan_mi_fen": effect.future = mini(2, horizon) * 2.0 * energy_value
		"qing_zhuan_cha": effect.future = horizon * energy_value
		"huang_shi_gang_bing": effect.future = mini(2, horizon) * (2.0 * energy_value - 35.0)
		"tong_shan_bao_tuo": effect.future = -35.0
		"pi_tiao_shan_yu": effect.future = mini(2, horizon) * energy_value
		"shen_nong_jia_la_rou": effect.future = mini(4, horizon) * energy_value
		"tu_jia_tai_ge_zi", "xiao_gan_mi_jiu", "shang_xiang_feng_gan_ji", "tu_jia_la_rou": effect.future = 24.0 if int(state.energy) >= 4 else 4.0
		"wu_xue_fo_shou_shan_yao", "ying_shan_yu_mian": effect.future = horizon * 10.0
		"tu_jia_you_cha_tang": effect.future = horizon * (35.0 if int(state.money) < 700 else 10.0)
		"qian_zhang_kou_rou", "fang_xian_huang_jiu":
			var values: Array[float] = []
			for entry: Dictionary in observation.state.market: values.append(card_value(entry, observation))
			values.sort()
			effect.future = 0.0
			if not values.is_empty():
				for value: float in values: effect.future += value / values.size()
				if id == "fang_xian_huang_jiu": effect.future *= minf(2.0, values.size())
		"mao_zui_lu_ji", "sui_zhou_mi_zao", "wu_xue_su_tang", "xiang_yang_chan_ti":
			var payment := 50 if id == "wu_xue_su_tang" else (200 if id == "xiang_yang_chan_ti" else 100)
			effect.future = 0.0
			for other: Dictionary in observation.state.players:
				if int(other.id) == int(state.id) or not bool(other.alive): continue
				var gain := mini(payment, int(other.money)) * 0.08
				if id == "xiang_yang_chan_ti": effect.future = maxf(effect.future, gain)
				else: effect.future += gain
			if id in ["mao_zui_lu_ji", "sui_zhou_mi_zao"]: effect.energy = 1
		"tuan_feng_gou_jiao": effect.future = 40.0 + (30.0 if int(state.energy) < 4 else 0.0)
	var permanent: Dictionary = state.get("food_state", {}).get("permanent_food_ids", {})
	if bool(permanent.get(id, false)): effect.future = 0.0
	return effect

## The other player has not submitted a secret card. Compare the worst public offer,
## retaining our best legal offer, rather than assuming their chosen card is known.
func exchange_value(other: Dictionary, observation: AIObservation) -> float:
	var cards: Array = observation.state.self.heritage
	var before := collection_score(cards, observation)
	var best := -INF
	for offered: Dictionary in cards:
		if int(offered.category) == 6: continue
		var remaining := cards.duplicate(true)
		_remove(remaining, int(offered.id))
		var worst := INF
		for received: Dictionary in other.get("heritage", []):
			if int(received.category) == 6: continue
			remaining.append(received)
			worst = minf(worst, (collection_score(remaining, observation) - before) * profile.score_weight)
			remaining.pop_back()
		if is_finite(worst): best = maxf(best, worst)
	return best if is_finite(best) else -1000.0

func retained_event_value(card: Dictionary, state: Dictionary, observation: AIObservation) -> float:
	match String(card.get("event_id", "")):
		"you_mu_cheng_huai":
			var benefit := mini(5, 12 - int(state.energy)) * 30.0
			for tile: Dictionary in observation.state.get("map", []):
				if int(tile.type) == 5 and not bool(tile.occupied):
					var next := state.duplicate(true)
					next.position = tile.position
					benefit = maxf(benefit, mini(5, 12 - int(state.energy)) * 30.0 + navigation_value(next, observation) - navigation_value(state, observation))
			return benefit - 25.0
		"chang_xing_wu_zu":
			# Current legal moves are already capped by remaining energy. The card opens
			# routes beyond that cap, so include the visible remaining movement allowance.
			var expense := minf(6.0, float(state.get("steps", 0)))
			for action: GameAction in observation.actions:
				if action.kind == GameAction.Kind.MOVE: expense = maxf(expense, float(action.data.get("energy", 0)))
			return minf(expense, 6.0) * (25.0 if int(state.energy) <= 5 else 10.0) - 25.0
	return -1.0

func opponent_threat(observation: AIObservation) -> float:
	var threat := 0.0
	for other: Dictionary in observation.state.players:
		if int(other.id) == int(observation.state.self.id) or not bool(other.alive): continue
		var score := float(other.score)
		for card: Dictionary in other.get("heritage", []):
			if not bool(card.effective) and int(other.get("energy", 0)) > 1: score += 5.0
		if score >= int(observation.state.target_score) - 3: threat = maxf(threat, 80.0 + maxf(0, score - int(observation.state.target_score)) * 20.0)
	return threat

func position_opportunity(state: Dictionary, observation: AIObservation) -> float:
	var reserves := int(state.energy)
	for card: Dictionary in state.foods:
		reserves += maxi(0, int(food_effect(card, state).energy))
	# Equal hand sizes can provide entirely different recovery. Cache the actual
	# reachable-energy input so sibling purchase/use plans cannot borrow a result.
	var key := "%s:%d" % [state.position, reserves]
	if _position_potentials.has(key): return float(_position_potentials[key])
	var best := 0.0
	for tile: Dictionary in observation.state.get("map", []):
		if int(tile.type) != 1 or not bool(tile.supply) or (bool(tile.occupied) and tile.position != state.position): continue
		var distance := maxi(absi(tile.position.x - state.position.x), maxi(absi(tile.position.y - state.position.y), absi(tile.position.z - state.position.z)))
		if distance > 7 * profile.goal_horizon: continue
		if not _opportunity_routes.has(tile.position): _opportunity_routes[tile.position] = _distances(_navigation_map, [tile.position])
		distance = int(_opportunity_routes[tile.position].get(state.position, 10000))
		if distance + 2 > reserves: continue
		var reward := expected_collection(int(tile.region), observation)
		var viable := reward / (1.0 + distance * 0.3) - distance * 12.0
		best = maxf(best, viable)
	var result := minf(200.0, best * 0.65)
	_position_potentials[key] = result
	return result
