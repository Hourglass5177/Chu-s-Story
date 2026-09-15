class_name AIWorldAdapter
extends RefCounted

## Privileged boundary. Only this adapter translates live objects to plain observations.
var shop := FoodShopVisit.new()
var market_player: PlayerClass
var objects: Dictionary = {}
var blocked_inheritance: Dictionary = {}
var _public_catalog: Array = []

func card_data(card: Resource) -> Dictionary:
	var id := card.get_instance_id()
	objects[id] = card
	var result := {"id": id, "name": card.card_name}
	if card is 非遗牌:
		result.merge({"type": "heritage", "category": int(card.category), "region": int(card.region), "score": card.base_score, "effective": HeritageTaskManager.is_effective_card(card), "sell_price": MarketManager.get_sell_price(card)})
	elif card is 食物牌:
		result.merge({"type": "food", "food_id": String(card.food_id), "level": int(card.food_type), "price": card.cost})
	elif card is 事件牌:
		result.merge({"type": "event", "event_id": String(card.event_id)})
	return result

func player_data(player: PlayerClass, viewer: PlayerClass) -> Dictionary:
	var cards: Array = []
	for card: 非遗牌 in player.非遗牌手牌:
		cards.append(card_data(card))
	var result := {"id": player.player_index, "money": player.current_money, "energy": player.current_energy, "score": player.current_score, "alive": player.alive, "profession": int(player.player_types), "skill_enabled": ProfessionManager.is_skill_enabled(player), "heritage": cards, "food_count": player.食物牌手牌.size(), "event_count": player.事件牌手牌.size(), "position": player.now_pos}
	var statuses: Dictionary = {}
	for status: StringName in [&"skip_moving", &"skip_action", &"work_banned", &"scenery_banned", &"free_move_phases"]:
		statuses[String(status)] = EventManager.get_status_remaining(player, status)
	result["statuses"] = statuses
	if viewer == player:
		var foods: Array = []
		var events: Array = []
		for card: 食物牌 in player.食物牌手牌:
			foods.append(card_data(card))
		for card: 事件牌 in player.事件牌手牌:
			events.append(card_data(card))
		result.merge({"foods": foods, "events": events, "food_uses": player.food_used_count_this_turn, "food_limit": ProfessionManager.get_food_use_limit(player), "food_state": FoodManager.get_state_snapshot(player), "steps": player.maxMove, "collected": player.feiyi_collected_this_turn, "worked": player.now_turn_worked})
	return result

func section_data(section: MapSection, player: PlayerClass) -> Dictionary:
	objects[section.get_instance_id()] = section
	return {"id": section.get_instance_id(), "position": section.location_index, "type": int(section.type), "region": int(section.region), "occupied": section.is_occupied, "fresh_scenery": AchievementManager.can_check_in_scenery(player, section) and not EventManager.is_scenery_banned(player), "arrival": player.has_current_action_arrival_at(section.location_index), "visited": int(section.grid_visit_history.get(player, 0)), "supply": ResourceManager.has_feiyi_in_region(section.region) if section.type == MapSection.SectionType.非遗 else false}

func observe(player: PlayerClass, memory: Dictionary = {}) -> AIObservation:
	var result := AIObservation.new()
	result.memory = memory.duplicate(true)
	var players: Array = []
	for other: PlayerClass in TurnManager.players:
		players.append(player_data(other, player))
	result.state = {"self": player_data(player, player), "players": players, "phase": int(TurnManager.now_phase), "target_score": TurnManager.target_score, "category_totals": ResourceManager.类别非遗牌上限字典.duplicate(), "region_totals": ResourceManager.地区非遗牌上限字典.duplicate(), "market": [], "shop": [], "section": section_data(player.map.grid_map[player.now_pos], player)}
	for card: 非遗牌 in MarketManager.get_inventory():
		var data := card_data(card)
		data["price"] = MarketManager.get_buy_price(card, player)
		result.state.market.append(data)
	if shop.is_current() and shop.player == player:
		for card: 食物牌 in shop.shelf:
			result.state.shop.append(card_data(card))
	# This complete catalogue is public and never filters by actual remaining deck contents.
	if _public_catalog.is_empty():
		for card: 非遗牌 in ResourceManager.非遗牌库:
			_public_catalog.append({"id": String(card.resource_path), "name": card.card_name, "type": "heritage", "category": int(card.category), "region": int(card.region), "score": card.base_score, "effective": card.category != 非遗牌.CardCategory.国家级非遗})
		_public_catalog.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	result.state["public_catalog"] = _public_catalog.duplicate(true)
	result.state["epoch"] = TurnManager.get_turn_epoch()
	result.state["map"] = []
	var seen: Dictionary = {}
	for section: MapSection in player.map.grid_map.values():
		if seen.has(section): continue
		seen[section] = true
		var data := section_data(section, player)
		data["cost"] = ProfessionManager.adjust_section_movement_cost(player, section, section.cost)
		result.state.map.append(data)
	result.state.self["achievement_progress"] = {}
	for achievement: 成就牌 in AchievementManager.get_all_achievements():
		var progress := AchievementManager.get_progress(player, achievement.achievement_id)
		var owner := AchievementManager.get_achievement_owner(achievement.achievement_id)
		progress["owner"] = owner.player_index if owner != null else -1
		progress["points"] = achievement.score_value
		progress["replaces"] = String(achievement.replaces_achievement_id)
		result.state.self.achievement_progress[String(achievement.achievement_id)] = progress
	result.actions = legal_actions(player)
	result.state.self["visit"] = "shop" if shop.is_current() and shop.player == player else ("market" if market_player == player else "")
	result.state.self["market_remaining"] = MarketManager.get_remaining_purchases(player, player.arrival_id)
	result.state["after_visit_actions"] = []
	if result.state.self.visit != "":
		for action: GameAction in legal_actions(player, true):
			result.state.after_visit_actions.append({"kind": int(action.kind), "target": action.target, "data": action.data.duplicate(true)})
	return result

func _action(player: PlayerClass, kind: GameAction.Kind, target: int = 0, data: Dictionary = {}) -> GameAction:
	var action := GameAction.new(kind, player.player_index, target, data)
	action.session = TurnManager.get_session_generation()
	action.epoch = TurnManager.get_turn_epoch()
	action.phase = TurnManager.now_phase
	return action

func legal_actions(player: PlayerClass, after_visit: bool = false) -> Array[GameAction]:
	var actions: Array[GameAction] = []
	if player == null or not TurnManager.players.has(player) or not player.alive or not player.onTurn or not TurnManager.GameOn or TurnManager.is_movement_locked() or not InteractionCoordinator.get_active_snapshot().is_empty():
		return actions
	if not after_visit and shop.is_current() and shop.player == player:
		actions.append(_action(player, GameAction.Kind.CLOSE_SHOP))
		for card: 食物牌 in shop.shelf:
			if card.cost <= player.current_money:
				actions.append(_action(player, GameAction.Kind.BUY_FOOD, card.get_instance_id(), card_data(card)))
		if shop.can_refresh():
			actions.append(_action(player, GameAction.Kind.REFRESH_SHOP))
		return actions
	if not after_visit and market_player == player:
		actions.append(_action(player, GameAction.Kind.CLOSE_MARKET))
		for card: 非遗牌 in MarketManager.get_inventory():
			if MarketManager.get_remaining_purchases(player, player.arrival_id) > 0 and MarketManager.get_buy_price(card, player) <= player.current_money:
				var data := card_data(card)
				data["price"] = MarketManager.get_buy_price(card, player)
				actions.append(_action(player, GameAction.Kind.BUY_FEIYI, card.get_instance_id(), data))
		for card: 非遗牌 in MarketManager.get_tradable_cards(player):
			var data := card_data(card)
			data["price"] = MarketManager.get_sell_price(card)
			actions.append(_action(player, GameAction.Kind.SELL_FEIYI, card.get_instance_id(), data))
		return actions
	if TurnManager.modal_resolution_depth > 0 or TurnManager.now_phase not in [TurnManager.TurnPhase.MOVING, TurnManager.TurnPhase.ACTION]:
		return actions
	actions.append(_action(player, GameAction.Kind.END_PHASE))
	for card: 非遗牌 in player.非遗牌手牌:
		if card.can_use(player):
			actions.append(_action(player, GameAction.Kind.USE_FEIYI, card.get_instance_id(), card_data(card)))
		if HeritageTaskManager.get_attempt_check(player, card).allowed and int(blocked_inheritance.get(card.get_instance_id(), -1)) != TurnManager.get_turn_epoch():
			actions.append(_action(player, GameAction.Kind.INHERIT, card.get_instance_id(), card_data(card)))
	for card: 食物牌 in player.食物牌手牌:
		if FoodManager.get_use_check(player, card).allowed:
			actions.append(_action(player, GameAction.Kind.USE_FOOD, card.get_instance_id(), card_data(card)))
	for card: 事件牌 in player.事件牌手牌:
		if EventManager.can_play_retained_event_now(card, player):
			actions.append(_action(player, GameAction.Kind.USE_EVENT, card.get_instance_id(), card_data(card)))
	if TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		var moves: Dictionary = player.map.query_moves(player)
		for section: MapSection in moves:
			var data := section_data(section, player)
			data.merge(moves[section])
			actions.append(_action(player, GameAction.Kind.MOVE, section.get_instance_id(), data))
	elif player.can_execute_tile_action():
		var section: MapSection = player.map.grid_map[player.now_pos]
		var kinds := {MapSection.SectionType.非遗: GameAction.Kind.COLLECT, MapSection.SectionType.打工: GameAction.Kind.WORK, MapSection.SectionType.商店: GameAction.Kind.OPEN_SHOP, MapSection.SectionType.研究所: GameAction.Kind.OPEN_MARKET}
		if kinds.has(section.type):
			var data := section_data(section, player)
			data["work_cost"] = ProfessionManager.get_work_energy_cost(player)
			data["work_income"] = ResourceManager.get_work_salary(player, player.work_turns + 1 if player.is_working else 1)
			actions.append(_action(player, kinds[section.type], 0, data))
	return actions

func execute(action: GameAction, player: PlayerClass) -> bool:
	if action == null or action.actor != player.player_index or action.session != TurnManager.get_session_generation() or action.epoch != TurnManager.get_turn_epoch() or action.phase != int(TurnManager.now_phase):
		return false
	var legal := false
	for candidate: GameAction in legal_actions(player):
		if candidate.key() == action.key():
			legal = true
			break
	if not legal:
		return false
	var target = objects.get(action.target)
	match action.kind:
		GameAction.Kind.MOVE: return await player.map.execute_move(player, target) == "success"
		GameAction.Kind.END_PHASE:
			if TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
				await player.check_and_cancel_work()
			TurnManager._emit_next_phase(TurnManager.TurnPhase.ACTION if action.phase == int(TurnManager.TurnPhase.MOVING) else TurnManager.TurnPhase.END)
		GameAction.Kind.USE_FEIYI: ResourceManager.use_feiyi(player, target)
		GameAction.Kind.USE_FOOD: await FoodManager.consume_food(player, target)
		GameAction.Kind.USE_EVENT: await EventManager.request_play_retained_event(player, target)
		GameAction.Kind.COLLECT, GameAction.Kind.WORK: await player.execute_tile_action()
		GameAction.Kind.OPEN_SHOP:
			return shop.begin(player)
		GameAction.Kind.BUY_FOOD: return shop.buy(target)
		GameAction.Kind.REFRESH_SHOP: return shop.refresh()
		GameAction.Kind.CLOSE_SHOP: shop.close()
		GameAction.Kind.OPEN_MARKET:
			if not MarketManager.begin_visit(player, player.arrival_id): return false
			market_player = player
		GameAction.Kind.BUY_FEIYI: return MarketManager.buy_card(player, target, player.arrival_id)
		GameAction.Kind.SELL_FEIYI: return MarketManager.sell_card(player, target)
		GameAction.Kind.CLOSE_MARKET: market_player = null
		_: return false
	return true

func clear() -> void:
	shop.close()
	market_player = null
	objects.clear()
	blocked_inheritance.clear()

func choice_option_data(option, viewer: PlayerClass) -> Dictionary:
	if option is PlayerClass: return {"type": "player", "player": player_data(option, viewer)}
	if option is MapSection: return {"type": "section", "section": section_data(option, viewer)}
	if option is Resource:
		var data := card_data(option)
		data["owned"] = (option is 非遗牌 and viewer.非遗牌手牌.has(option)) or (option is 食物牌 and viewer.食物牌手牌.has(option)) or (option is 事件牌 and viewer.事件牌手牌.has(option))
		return data
	if option is bool: return {"type": "bool", "value": option}
	if option is int or option is float: return {"type": "number", "value": option}
	return {"type": "text", "value": String(option)}
