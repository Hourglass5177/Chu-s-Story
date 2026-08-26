extends Node

const PLAYER_COUNTS: Array[int] = [2, 3, 6]
const TURN_CAP: int = 500
const WALL_TIME_CAP_MSEC: int = 10000
const ACTION_CAP: int = 32

var _matches_per_mode: int = 108
var _base_seed: int = 20260824
var _exact_seed: int = -1
var _match_index_offset: int = 0
var _replay_match_path: String = ""
var _output_dir: String = "res://artifacts/balance"
var _requested_counts: Array[int] = PLAYER_COUNTS.duplicate()
var _requested_strategies: Array[SimulationDecisionProvider.Strategy] = SimulationDecisionProvider.all_strategies()
var _reports: Array[Dictionary] = []
var _active_strategy: SimulationDecisionProvider = null

func _ready() -> void:
	_parse_arguments()
	call_deferred(&"_run")

func _run() -> void:
	var failed := false
	if not _replay_match_path.is_empty():
		var replay_config := _load_replay_config(_replay_match_path)
		var replay_report := await _run_match(replay_config)
		_reports.append(replay_report)
		failed = bool(replay_report.get("aborted", false))
	else:
		for player_count: int in _requested_counts:
			for strategy: SimulationDecisionProvider.Strategy in _requested_strategies:
				for local_match_index: int in _matches_per_mode:
					var match_index := _match_index_offset + local_match_index
					var config := SimulationSchedule.build_match(player_count, strategy, match_index, _base_seed)
					if _exact_seed >= 0:
						config.world_seed = _exact_seed
						config.decision_seed = _exact_seed + (int(strategy) + 1) * 100_000_000
					var report: Dictionary = await _run_match(config)
					_reports.append(report)
					if bool(report.get("aborted", false)):
						failed = true
	# 最后一局结束后统一解除 Autoload 对场景节点和策略对象的引用，
	# 否则命令行退出时会留下玩家/HUD 引用并掩盖真正的泄漏。
	GameManager.reset_session(false)
	_active_strategy = null
	await get_tree().process_frame
	await get_tree().process_frame
	_write_reports()
	print("BALANCE_SIMULATION matches=%d aborted=%d output=%s" % [_reports.size(), _count_aborted(), ProjectSettings.globalize_path(_output_dir)])
	# 让包含最后一局 PlayerClass 局部变量的协程栈先完整退栈，再退出进程。
	# 直接在本协程内 quit 会让 Godot 在清理阶段误报 player.gd 仍被引用。
	call_deferred(&"_quit_with_status", 1 if failed else 0)

func _quit_with_status(exit_code: int) -> void:
	get_tree().quit(exit_code)

func _run_match(config: SimulationMatchConfig) -> Dictionary:
	GameManager.configure_session(config.world_seed, GameManager.RuntimeProfile.HEADLESS_SIMULATION, config.target_score)
	GameManager.reset_session()
	GameManager.player_data = _build_player_data(config)
	_active_strategy = SimulationDecisionProvider.new(config.strategy, config.decision_seed)
	InteractionCoordinator.decision_provider = _active_strategy.decide
	var scene := (load("res://main_map.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	for _frame: int in 10:
		await get_tree().process_frame
		if TurnManager.GameOn and TurnManager.players.size() == config.player_count:
			break
	var players: Array = []
	players.assign(TurnManager.players)
	var recorder := BalanceTelemetryRecorder.new()
	recorder.start_match(config, players)
	var abort_reason := ""
	var started_at := Time.get_ticks_msec()
	while TurnManager.GameOn and TurnManager.now_turn <= TURN_CAP:
		if Time.get_ticks_msec() - started_at > WALL_TIME_CAP_MSEC:
			abort_reason = "wall_time_cap"
			break
		if not await _drive_current_turn():
			abort_reason = "interaction_stall"
			break
	if TurnManager.GameOn and abort_reason.is_empty():
		abort_reason = "turn_cap"
	var result: GameResult = TurnManager.get_game_result() as GameResult
	var report: Dictionary = recorder.finish_match(result, abort_reason)
	report["match_index"] = config.match_index
	report["match_config"] = config.to_dictionary()
	report["profession_schedule"] = _profession_schedule(players)
	report["modal_snapshot"] = TurnManager.get_modal_snapshot()
	report["interaction_snapshot"] = InteractionCoordinator.get_active_snapshot()
	if not abort_reason.is_empty():
		InteractionCoordinator.cancel_all(&"simulation_abort")
		TurnManager.invalidate_all_modals(&"simulation_abort")
	# 先解除所有 Autoload 对玩家、HUD 与地图的强引用并恢复暂停树，
	# 再释放场景；多人局仍存活的冠军节点否则可能滞留到进程退出。
	GameManager.reset_session(false)
	for player: PlayerClass in players:
		if is_instance_valid(player):
			player.free()
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	players.clear()
	result = null
	scene = null
	recorder = null
	return report

func _drive_current_turn() -> bool:
	if not await _wait_for_quiescence():
		return false
	if not TurnManager.GameOn or TurnManager.players.is_empty():
		return true
	var player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	if TurnManager.now_phase == TurnManager.TurnPhase.BEGIN:
		TurnManager.change_phase(TurnManager.TurnPhase.ROLL_DICE)
		await get_tree().process_frame
		await get_tree().process_frame
	if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.ROLL_DICE:
		TurnManager.change_phase(TurnManager.TurnPhase.MOVING)
		await get_tree().process_frame
	if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		await _perform_movement(player)
		if not await _wait_for_quiescence():
			return false
		TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
		await get_tree().process_frame
	if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		if not await _wait_for_quiescence():
			return false
		await _perform_action(player)
		if not await _wait_for_quiescence():
			return false
		# 与真实 HUD 的“结束”按钮走同一入口，使离开打工格等状态能在回合末
		# 通过 check_and_cancel_work() 正常清理，不能由模拟器直接跳转阶段。
		player.request_end_turn()
		await get_tree().process_frame
	if TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.END:
		if not await _wait_for_quiescence():
			return false
		await TurnManager.now_turn_end()
		await get_tree().process_frame
	return true

func _perform_movement(player: PlayerClass) -> void:
	if player == null or player.map == null or player.maxMove <= 0:
		return
	player.map._show_reachable_areas()
	var options: Array[MapSection] = []
	for section: MapSection in player.map.grid_map.values():
		if section.is_reachable:
			options.append(section)
	if options.is_empty():
		return
	var target := _choose_movement_target(player, options)
	if target != null:
		await player.map._on_section_clicked(target)

func _choose_movement_target(player: PlayerClass, options: Array[MapSection]) -> MapSection:
	if _active_strategy.strategy == SimulationDecisionProvider.Strategy.LEGAL_RANDOM:
		return _active_strategy.pick_value(options) as MapSection
	var best: MapSection = options[0]
	var best_score := -100000
	var has_safe_option := false
	var survival_required := _survival_priority_active() \
		and not _can_close_out_by_elimination(player)
	for section: MapSection in options:
		var path: Dictionary = player.map._best_path(player.now_pos, section.location_index, player.maxMove, 1 << 30, player)
		if path.is_empty():
			continue
		var actual_cost := int(path.cost)
		if not player.武术拳法已生效:
			for card: 非遗牌 in player.非遗牌手牌:
				if card.category == 非遗牌.CardCategory.武术拳法:
					actual_cost = maxi(actual_cost - 1, 0)
					break
		if EventManager.has_free_move_this_phase(player) or (EventManager.can_ignore_special_terrain_this_phase(player) and section.landform != MapSection.LandForm.平原):
			actual_cost = 0
		actual_cost = FoodManager.preview_movement_cost(player, actual_cost)
		var safe := actual_cost < player.current_energy
		if survival_required and safe and not has_safe_option:
			has_safe_option = true
			best_score = -100000
		if survival_required and has_safe_option and not safe:
			continue
		var score := -actual_cost * 20
		match section.type:
			MapSection.SectionType.非遗:
				score += 120 if ResourceManager.has_feiyi_in_region(section.region) else 0
			MapSection.SectionType.风景:
				score += 80
			MapSection.SectionType.事件:
				score += 55
			MapSection.SectionType.商店:
				score += 35 if player.current_money >= 150 else 0
			MapSection.SectionType.研究所:
				score += 25
			MapSection.SectionType.打工:
				score += 20 if player.current_energy >= ProfessionManager.get_work_energy_cost(player) else 0
			_:
				pass
		if score > best_score:
			best_score = score
			best = section
	return best

func _perform_action(player: PlayerClass) -> void:
	if player == null or not player.alive or player.map == null:
		return
	var action_count := 0
	while action_count < ACTION_CAP and TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		action_count += 1
		var candidates: Array[SimulationActionCandidate] = [SimulationActionCandidate.new(SimulationActionCandidate.Kind.END_ACTION, null, 0.0)]
		for retained: 事件牌 in player.事件牌手牌:
			if EventManager.can_play_retained_event_now(retained, player):
				candidates.append(SimulationActionCandidate.new(SimulationActionCandidate.Kind.USE_RETAINED_EVENT, retained, 24.0))
		for food: 食物牌 in player.食物牌手牌:
			if not FoodManager.get_use_check(player, food).allowed:
				continue
			var food_utility := 18.0
			if _survival_priority_active():
				food_utility = 80.0 - player.current_energy * 10.0
			elif _active_strategy.strategy in [SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY, SimulationDecisionProvider.Strategy.SCORE_GREEDY]:
				food_utility = 30.0 + float(food.food_type) * 5.0
			candidates.append(SimulationActionCandidate.new(SimulationActionCandidate.Kind.USE_FOOD, food, food_utility))
		var selected := _active_strategy.pick_action(candidates, SimulationObservation.capture(player))
		if selected == null or selected.kind == SimulationActionCandidate.Kind.END_ACTION:
			break
		if selected.kind == SimulationActionCandidate.Kind.USE_RETAINED_EVENT:
			await EventManager.play_retained_event(player, selected.value as 事件牌)
		elif selected.kind == SimulationActionCandidate.Kind.USE_FOOD:
			await FoodManager.consume_food(player, selected.value as 食物牌)
		if not await _wait_for_quiescence():
			return
	var section: MapSection = player.map.grid_map.get(player.now_pos) as MapSection
	if section == null:
		return
	match section.type:
		MapSection.SectionType.非遗:
			if _survival_priority_active() \
					and player.current_energy <= 1 and not _can_close_out_by_elimination(player):
				return
			await player.execute_tile_action()
		MapSection.SectionType.打工:
			if _survival_priority_active() and player.current_energy <= ProfessionManager.get_work_energy_cost(player):
				return
			await player.execute_tile_action()
		MapSection.SectionType.商店:
			_simulate_food_shop(player)
		MapSection.SectionType.研究所:
			_simulate_market(player)
		_:
			pass
	if action_count >= ACTION_CAP:
		push_error("模拟 ACTION 达到 %d 次操作上限：%s" % [ACTION_CAP, player.player_name])

func _simulate_food_shop(player: PlayerClass) -> void:
	var shelf := ResourceManager.draw_shop_foods(3)
	var refresh_available := ProfessionManager.get_food_shop_refresh_limit(player) > 0 and not ResourceManager.食物牌库.is_empty()
	if refresh_available and (_active_strategy.strategy != SimulationDecisionProvider.Strategy.LEGAL_RANDOM or bool(_active_strategy.pick_value([false, true]))):
		var previous_foods: Array[食物牌] = shelf.duplicate()
		shelf = ResourceManager.draw_shop_foods(3)
		ResourceManager.return_shop_foods_to_bottom(previous_foods)
		ProfessionManager.notify_skill_triggered(player, "刷新商店")
	var ordered: Array[食物牌] = shelf.duplicate()
	if _active_strategy.strategy == SimulationDecisionProvider.Strategy.SCORE_GREEDY \
			or (_active_strategy.strategy == SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY and not _survival_priority_active()):
		ordered.sort_custom(func(first: 食物牌, second: 食物牌) -> bool: return first.food_type > second.food_type)
	elif _active_strategy.strategy == SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY:
		ordered.sort_custom(func(first: 食物牌, second: 食物牌) -> bool: return first.cost < second.cost)
	for card: 食物牌 in ordered:
		if player.current_money >= card.cost and ResourceManager.buy_food(player, card):
			shelf.erase(card)
	ResourceManager.return_shop_foods_to_bottom(shelf)

func _simulate_market(player: PlayerClass) -> void:
	if not MarketManager.begin_visit(player, player.arrival_id):
		return
	if _survival_priority_active() and player.current_money < 250:
		var tradable := MarketManager.get_tradable_cards(player)
		if not tradable.is_empty():
			MarketManager.sell_card(player, tradable[0])
	var inventory := MarketManager.get_inventory()
	if _active_strategy.strategy == SimulationDecisionProvider.Strategy.SCORE_GREEDY \
			or (_active_strategy.strategy == SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY and not _survival_priority_active()):
		inventory.sort_custom(func(first: 非遗牌, second: 非遗牌) -> bool: return first.base_score > second.base_score)
	for card: 非遗牌 in inventory:
		if MarketManager.get_remaining_purchases(player, player.arrival_id) <= 0:
			break
		if player.current_money >= MarketManager.get_buy_price(card, player):
			MarketManager.buy_card(player, card, player.arrival_id)

func _wait_for_quiescence(max_frames: int = 240) -> bool:
	for _index: int in max_frames:
		var map_choice_active := TurnManager.map != null and TurnManager.map.is_section_choice_active()
		if InteractionCoordinator.get_active_snapshot().is_empty() \
				and not EventManager.resolving \
				and not TurnManager.is_movement_locked() \
				and not TurnManager.is_modal_resolution_active() \
				and not map_choice_active:
			await get_tree().process_frame
			return true
		await get_tree().process_frame
	return false

func _can_close_out_by_elimination(player: PlayerClass) -> bool:
	# 单人局没有“累计淘汰 2 人”的胜利路径；唯一玩家存活不能被模拟策略
	# 误判为已经可以靠淘汰条件收官。
	if player == null or TurnManager.players.size() <= 1:
		return false
	var alive_count := 0
	var player_score := int(ResourceManager.get_score_breakdown(player).get("total_score", player.current_score))
	for candidate: PlayerClass in TurnManager.players:
		if candidate.alive:
			alive_count += 1
		elif int(ResourceManager.get_score_breakdown(candidate).get("total_score", candidate.current_score)) > player_score:
			return false
	return alive_count == 1

func _survival_priority_active() -> bool:
	# 有限时域策略先保命；进入后半程后转向得分，避免在资源已稀疏的残局中
	# 仅维持生存而无法抵达正式胜利条件。该阈值只影响模拟决策，不改游戏规则。
	return _active_strategy != null \
		and _active_strategy.strategy == SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY \
		and TurnManager.now_turn < 60

func _build_player_data(config: SimulationMatchConfig) -> Array:
	var data: Array = []
	for index: int in config.player_count:
		data.append({"name": "SIM-P%d" % (index + 1), "location": config.locations[index], "job": config.professions[index]})
	return data

func _profession_schedule(players: Array) -> Array[Dictionary]:
	var schedule: Array[Dictionary] = []
	for player: PlayerClass in players:
		schedule.append({"player_index": player.player_index, "profession": ProfessionManager.get_definition(player).profession_name})
	return schedule

func _strategy_name(strategy: SimulationDecisionProvider.Strategy) -> StringName:
	return SimulationDecisionProvider.strategy_name(strategy)

func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--matches="):
			_matches_per_mode = maxi(int(argument.get_slice("=", 1)), 1)
		elif argument.begins_with("--seed="):
			_base_seed = int(argument.get_slice("=", 1))
		elif argument.begins_with("--exact-seed="):
			_exact_seed = int(argument.get_slice("=", 1))
			_matches_per_mode = 1
		elif argument.begins_with("--match-index="):
			_match_index_offset = maxi(int(argument.get_slice("=", 1)), 0)
		elif argument.begins_with("--out="):
			_output_dir = argument.get_slice("=", 1)
		elif argument.begins_with("--replay-match="):
			_replay_match_path = argument.get_slice("=", 1)
		elif argument.begins_with("--players="):
			_requested_counts.clear()
			for value: String in argument.get_slice("=", 1).split(","):
				var count := int(value)
				if count in PLAYER_COUNTS:
					_requested_counts.append(count)
		elif argument == "--strategy=legal_random":
			_requested_strategies = [SimulationDecisionProvider.Strategy.LEGAL_RANDOM]
		elif argument == "--strategy=balanced_greedy":
			_requested_strategies = [SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY]
		elif argument == "--strategy=survival_greedy":
			_requested_strategies = [SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY]
		elif argument == "--strategy=score_greedy":
			_requested_strategies = [SimulationDecisionProvider.Strategy.SCORE_GREEDY]

func _load_replay_config(path: String) -> SimulationMatchConfig:
	var absolute := path if path.is_absolute_path() else ProjectSettings.globalize_path(path)
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		push_error("无法读取重放配置：%s" % absolute)
		return SimulationSchedule.build_match(2, SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 0, _base_seed)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("match_config"):
		parsed = parsed.match_config
	return SimulationMatchConfig.from_dictionary(parsed if parsed is Dictionary else {})

func _write_reports() -> void:
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var json_file := FileAccess.open(absolute_dir.path_join("matches.json"), FileAccess.WRITE)
	json_file.store_string(JSON.stringify(_reports, "  "))
	var matches_dir := absolute_dir.path_join("matches")
	DirAccess.make_dir_recursive_absolute(matches_dir)
	for report: Dictionary in _reports:
		var match_file := FileAccess.open(matches_dir.path_join("match-%04d.json" % int(report.match_index)), FileAccess.WRITE)
		match_file.store_string(JSON.stringify(report, "  "))
	var csv_file := FileAccess.open(absolute_dir.path_join("matches.csv"), FileAccess.WRITE)
	csv_file.store_line("world_seed,decision_seed,match_index,player_count,strategy,turns,end_reason,aborted,abort_reason,winners")
	for report: Dictionary in _reports:
		csv_file.store_line("%d,%d,%d,%d,%s,%d,%d,%s,%s,%s" % [int(report.world_seed), int(report.decision_seed), int(report.match_index), int(report.player_count), report.strategy, int(report.turns), int(report.end_reason), str(report.aborted).to_lower(), _csv(report.abort_reason), _csv(str(report.get("winners", [])))])
	var markdown := FileAccess.open(absolute_dir.path_join("summary.md"), FileAccess.WRITE)
	markdown.store_string(_build_markdown_summary())

func _build_markdown_summary() -> String:
	return BalanceReportBuilder.build_markdown(_reports)

func _aggregate_profession_stats() -> Dictionary:
	var result: Dictionary = {}
	for report: Dictionary in _reports:
		var winner_ids: Array = report.get("winners", [])
		for player: Dictionary in report.get("players", []):
			var key := String(player.get("profession", "未知"))
			var stats: Dictionary = result.get(key, {"count": 0, "wins": 0, "rank_sum": 0, "score_sum": 0})
			stats.count += 1
			stats.wins += 1 if int(player.player_index) in winner_ids else 0
			stats.rank_sum += int(player.get("rank", 0))
			stats.score_sum += int(player.get("score", 0))
			result[key] = stats
	return result

func _aggregate_seat_stats() -> Dictionary:
	var result: Dictionary = {}
	for report: Dictionary in _reports:
		for player: Dictionary in report.get("players", []):
			var seat := int(player.player_index)
			var stats: Dictionary = result.get(seat, {"count": 0, "score_sum": 0})
			stats.count += 1
			stats.score_sum += int(player.get("score", 0))
			result[seat] = stats
	return result

func _count_aborted() -> int:
	var count := 0
	for report: Dictionary in _reports:
		if bool(report.get("aborted", false)):
			count += 1
	return count

func _csv(value) -> String:
	return "\"%s\"" % String(value).replace("\"", "\"\"")
