extends RefCounted
class_name BalanceTelemetryRecorder

var _report: Dictionary = {}
var _players: Array = []
var _connections: Array[Dictionary] = []
var _food_start_state: Dictionary[int, Dictionary] = {}

func start_match(seed_value: int, player_count: int, strategy: StringName, players: Array) -> void:
	_disconnect_all()
	_food_start_state.clear()
	_players = players.duplicate()
	_report = {
		"schema_version": 1,
		"seed": seed_value,
		"player_count": player_count,
		"strategy": String(strategy),
		"turns": 0,
		"aborted": false,
		"abort_reason": "",
		"money_changes": [],
		"energy_changes": [],
		"score_changes": [],
		"work": [],
		"foods": {},
		"food_outcomes": [],
		"events": {},
		"responses": {},
		"professions": {},
		"market": {},
		"achievements": {},
		"achievement_claims": [],
	}
	_connect(ResourceManager.money_changed, _on_money_changed)
	_connect(ResourceManager.energy_changed, _on_energy_changed)
	_connect(ResourceManager.score_changed, _on_score_changed)
	_connect(ResourceManager.work_completed, _on_work_completed)
	_connect(ResourceManager.food_purchased, _on_food_purchased)
	_connect(FoodManager.food_resolution_started, _on_food_started)
	_connect(FoodManager.food_resolution_finished, _on_food_finished)
	_connect(EventManager.event_finished, _on_event_finished)
	_connect(EventManager.effect_response_resolved, _on_effect_response)
	_connect(ProfessionManager.skill_triggered, _on_skill_triggered)
	_connect(MarketManager.transaction_completed, _on_market_transaction)
	_connect(AchievementManager.achievement_claimed, _on_achievement_claimed)
	_connect(TurnManager.turn_completed, _on_turn_completed)

func finish_match(result: GameResult = null, abort_reason: String = "") -> Dictionary:
	if not abort_reason.is_empty():
		_report["aborted"] = true
		_report["abort_reason"] = abort_reason
	_report["end_reason"] = result.end_reason if result != null else -1
	var ranks: Dictionary[int, int] = {}
	if result != null:
		for entry: GameResultEntry in result.entries:
			ranks[entry.player_index] = entry.rank
	var final_players: Array[Dictionary] = []
	for player: PlayerClass in _players:
		if player == null:
			continue
		var breakdown: Dictionary = ResourceManager.get_score_breakdown(player)
		final_players.append({
			"player_index": player.player_index,
			"profession": ProfessionManager.get_definition(player).profession_name,
			"alive": player.alive,
			"money": player.current_money,
			"energy": player.current_energy,
			"score": int(breakdown.get("total_score", player.current_score)),
			"rank": int(ranks.get(player.player_index, 0)),
			"score_breakdown": _json_safe_breakdown(breakdown),
		})
	_report["players"] = final_players
	if result != null:
		var winners: Array[int] = []
		for entry: GameResultEntry in result.entries:
			if entry.is_winner:
				winners.append(entry.player_index)
		_report["winners"] = winners
	_disconnect_all()
	_players.clear()
	_food_start_state.clear()
	return _report.duplicate(true)

func get_report() -> Dictionary:
	return _report.duplicate(true)

func _connect(signal_value: Signal, callback: Callable) -> void:
	if not signal_value.is_connected(callback):
		signal_value.connect(callback)
	_connections.append({"signal": signal_value, "callback": callback})

func _disconnect_all() -> void:
	for connection: Dictionary in _connections:
		var signal_value: Signal = connection["signal"]
		var callback: Callable = connection["callback"]
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)
	_connections.clear()

func _player_id(player: PlayerClass) -> int:
	return player.player_index if player != null else -1

func _increment(bucket_name: String, key: String, amount: int = 1) -> void:
	var bucket: Dictionary = _report.get(bucket_name, {})
	bucket[key] = int(bucket.get(key, 0)) + amount
	_report[bucket_name] = bucket

func _on_money_changed(player: PlayerClass, previous: int, current: int, reason: String) -> void:
	_report["money_changes"].append({"turn": TurnManager.now_turn, "player": _player_id(player), "before": previous, "after": current, "reason": reason})

func _on_energy_changed(player: PlayerClass, previous: int, current: int, reason: String) -> void:
	_report["energy_changes"].append({"turn": TurnManager.now_turn, "player": _player_id(player), "before": previous, "after": current, "reason": reason})

func _on_score_changed(player: PlayerClass, previous: int, current: int, _breakdown: Dictionary) -> void:
	_report["score_changes"].append({"turn": TurnManager.now_turn, "player": _player_id(player), "before": previous, "after": current})

func _on_work_completed(player: PlayerClass, turns: int, income: int) -> void:
	_report["work"].append({"turn": TurnManager.now_turn, "player": _player_id(player), "work_turns": turns, "income": income})

func _on_food_started(player: PlayerClass, card: 食物牌) -> void:
	if player != null and card != null:
		_food_start_state[player.get_instance_id()] = {"energy": player.current_energy, "money": player.current_money, "food_id": String(card.food_id)}

func _on_food_finished(player: PlayerClass, result: FoodResolutionResult) -> void:
	if result == null or result.card == null:
		return
	_increment("foods", String(result.card.food_id) + (":success" if result.success else ":failed"))
	var before: Dictionary = _food_start_state.get(player.get_instance_id(), {}) if player != null else {}
	_report["food_outcomes"].append({
		"turn": TurnManager.now_turn,
		"player": _player_id(player),
		"food_id": String(result.card.food_id),
		"success": result.success,
		"effect_applied": result.effect_applied,
		"energy_delta": player.current_energy - int(before.get("energy", player.current_energy)) if player != null else 0,
		"money_delta": player.current_money - int(before.get("money", player.current_money)) if player != null else 0,
	})
	if player != null:
		_food_start_state.erase(player.get_instance_id())

func _on_food_purchased(_player: PlayerClass, card: 食物牌, _price: int) -> void:
	if card != null:
		_increment("foods", String(card.food_id) + ":purchased")

func _on_event_finished(_player: PlayerClass, card: 事件牌, summary: String) -> void:
	if card == null:
		return
	_increment("events", String(card.event_id))
	if summary.contains("无事发生"):
		_increment("events", String(card.event_id) + ":no_effect")

func _on_effect_response(effect_kind: StringName, response_kind: StringName, _responder: PlayerClass, _target: PlayerClass) -> void:
	_increment("responses", "%s:%s" % [effect_kind, response_kind])

func _on_skill_triggered(_player: PlayerClass, profession_id: StringName, _message: String) -> void:
	_increment("professions", String(profession_id))

func _on_market_transaction(_player: PlayerClass, _card: 非遗牌, kind: StringName, _amount: int) -> void:
	_increment("market", String(kind))

func _on_achievement_claimed(player: PlayerClass, card: 成就牌) -> void:
	if card != null:
		_increment("achievements", String(card.achievement_id))
		_report["achievement_claims"].append({"turn": TurnManager.now_turn, "player": _player_id(player), "achievement_id": String(card.achievement_id)})

func _on_turn_completed(_player: PlayerClass, turn_number: int) -> void:
	_report["turns"] = maxi(int(_report.get("turns", 0)), turn_number)

func _json_safe_breakdown(breakdown: Dictionary) -> Dictionary:
	return {
		"base_score": int(breakdown.get("base_score", 0)),
		"category_combo_score": int(breakdown.get("category_combo_score", 0)),
		"category_completion_score": int(breakdown.get("category_completion_score", 0)),
		"regional_combo_score": int(breakdown.get("regional_combo_score", 0)),
		"achievement_score": int(breakdown.get("achievement_score", 0)),
		"total_score": int(breakdown.get("total_score", 0)),
	}
