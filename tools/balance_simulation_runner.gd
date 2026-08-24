extends Node

const PLAYER_COUNTS: Array[int] = [2, 3, 6]
const LOCATION_NAMES: Array[String] = ["十堰", "随州", "孝感", "黄冈", "荆州", "恩施"]
const PROFESSION_NAMES: Array[String] = ["美食博主", "魔术博主", "探险博主", "商业博主", "旅行博主", "生活博主"]
const TURN_CAP: int = 500
const WALL_TIME_CAP_MSEC: int = 10000

var _matches_per_mode: int = 100
var _base_seed: int = 20260824
var _exact_seed: int = -1
var _match_index_offset: int = 0
var _output_dir: String = "res://artifacts/balance"
var _requested_counts: Array[int] = PLAYER_COUNTS.duplicate()
var _requested_strategies: Array[SimulationDecisionProvider.Strategy] = [SimulationDecisionProvider.Strategy.LEGAL_RANDOM, SimulationDecisionProvider.Strategy.BALANCED_GREEDY]
var _reports: Array[Dictionary] = []
var _active_strategy: SimulationDecisionProvider = null

func _ready() -> void:
	_parse_arguments()
	call_deferred(&"_run")

func _run() -> void:
	var failed := false
	for player_count: int in _requested_counts:
		for strategy: SimulationDecisionProvider.Strategy in _requested_strategies:
			for local_match_index: int in _matches_per_mode:
				var match_index := _match_index_offset + local_match_index
				var seed_value := _exact_seed if _exact_seed >= 0 else _base_seed + player_count * 100000 + strategy * 10000 + match_index
				var report: Dictionary = await _run_match(player_count, strategy, seed_value, match_index)
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

func _run_match(player_count: int, strategy: SimulationDecisionProvider.Strategy, seed_value: int, match_index: int) -> Dictionary:
	GameManager.configure_session(seed_value, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	GameManager.reset_session()
	GameManager.player_data = _build_player_data(player_count, match_index)
	_active_strategy = SimulationDecisionProvider.new(strategy)
	InteractionCoordinator.decision_provider = _active_strategy.decide
	var scene := (load("res://main_map.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	for _frame: int in 10:
		await get_tree().process_frame
		if TurnManager.GameOn and TurnManager.players.size() == player_count:
			break
	var players: Array = []
	players.assign(TurnManager.players)
	var recorder := BalanceTelemetryRecorder.new()
	recorder.start_match(seed_value, player_count, _strategy_name(strategy), players)
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
	report["match_index"] = match_index
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
		return GameManager.pick_from(options) as MapSection
	var best: MapSection = options[0]
	var best_score := -100000
	var has_safe_option := false
	var survival_required := not _can_close_out_by_elimination(player)
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
	await _play_retained_event_by_policy(player)
	if not TurnManager.GameOn or TurnManager.now_phase != TurnManager.TurnPhase.ACTION:
		return
	await _consume_food_by_policy(player)
	var section: MapSection = player.map.grid_map.get(player.now_pos) as MapSection
	if section == null:
		return
	match section.type:
		MapSection.SectionType.非遗:
			if _active_strategy.strategy == SimulationDecisionProvider.Strategy.BALANCED_GREEDY \
					and player.current_energy <= 1 and not _can_close_out_by_elimination(player):
				return
			await player.execute_tile_action()
		MapSection.SectionType.打工:
			if _active_strategy.strategy == SimulationDecisionProvider.Strategy.BALANCED_GREEDY and player.current_energy <= ProfessionManager.get_work_energy_cost(player):
				return
			await player.execute_tile_action()
		MapSection.SectionType.商店:
			_simulate_food_shop(player)
		MapSection.SectionType.研究所:
			_simulate_market(player)
		_:
			pass


func _play_retained_event_by_policy(player: PlayerClass) -> void:
	var playable: Array[事件牌] = []
	for card: 事件牌 in player.事件牌手牌:
		if EventManager.can_play_retained_event_now(card, player):
			playable.append(card)
	if playable.is_empty():
		return
	if _active_strategy.strategy == SimulationDecisionProvider.Strategy.LEGAL_RANDOM \
			and GameManager.randi_between(0, 1) == 0:
		return
	var selected := GameManager.pick_from(playable) as 事件牌 \
			if _active_strategy.strategy == SimulationDecisionProvider.Strategy.LEGAL_RANDOM else playable[0]
	if selected != null:
		await EventManager.play_retained_event(player, selected)

func _consume_food_by_policy(player: PlayerClass) -> void:
	var attempts := ProfessionManager.get_food_use_limit(player)
	while attempts > 0:
		var candidates: Array[食物牌] = []
		for card: 食物牌 in player.食物牌手牌:
			if FoodManager.get_use_check(player, card).allowed:
				candidates.append(card)
		if candidates.is_empty():
			return
		if _active_strategy.strategy == SimulationDecisionProvider.Strategy.BALANCED_GREEDY and player.current_energy > 7:
			return
		var card := GameManager.pick_from(candidates) as 食物牌
		var result: FoodResolutionResult = await FoodManager.consume_food(player, card)
		if result == null or not result.success:
			return
		attempts -= 1

func _simulate_food_shop(player: PlayerClass) -> void:
	var shelf := ResourceManager.draw_shop_foods(3)
	var purchased: 食物牌 = null
	for card: 食物牌 in shelf:
		if player.current_money >= card.cost:
			purchased = card
			break
	if purchased != null:
		ResourceManager.buy_food(player, purchased)
		shelf.erase(purchased)
	ResourceManager.return_shop_foods_to_bottom(shelf)

func _simulate_market(player: PlayerClass) -> void:
	if not MarketManager.begin_visit(player, player.arrival_id):
		return
	for card: 非遗牌 in MarketManager.get_inventory():
		if player.current_money >= MarketManager.get_buy_price(card, player):
			MarketManager.buy_card(player, card, player.arrival_id)
			break
	if player.current_money < 250:
		var tradable := MarketManager.get_tradable_cards(player)
		if not tradable.is_empty():
			MarketManager.sell_card(player, tradable[0])

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
	if player == null:
		return false
	var alive_count := 0
	var player_score := int(ResourceManager.get_score_breakdown(player).get("total_score", player.current_score))
	for candidate: PlayerClass in TurnManager.players:
		if candidate.alive:
			alive_count += 1
		elif int(ResourceManager.get_score_breakdown(candidate).get("total_score", candidate.current_score)) > player_score:
			return false
	return alive_count == 1

func _build_player_data(player_count: int, match_index: int) -> Array:
	var data: Array = []
	for index: int in player_count:
		data.append({"name": "SIM-P%d" % (index + 1), "location": LOCATION_NAMES[index], "job": PROFESSION_NAMES[(match_index + index) % PROFESSION_NAMES.size()]})
	return data

func _profession_schedule(players: Array) -> Array[Dictionary]:
	var schedule: Array[Dictionary] = []
	for player: PlayerClass in players:
		schedule.append({"player_index": player.player_index, "profession": ProfessionManager.get_definition(player).profession_name})
	return schedule

func _strategy_name(strategy: SimulationDecisionProvider.Strategy) -> StringName:
	return &"legal_random" if strategy == SimulationDecisionProvider.Strategy.LEGAL_RANDOM else &"balanced_greedy"

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
		elif argument.begins_with("--players="):
			_requested_counts.clear()
			for value: String in argument.get_slice("=", 1).split(","):
				var count := int(value)
				if count in PLAYER_COUNTS:
					_requested_counts.append(count)
		elif argument == "--strategy=legal_random":
			_requested_strategies = [SimulationDecisionProvider.Strategy.LEGAL_RANDOM]
		elif argument == "--strategy=balanced_greedy":
			_requested_strategies = [SimulationDecisionProvider.Strategy.BALANCED_GREEDY]

func _write_reports() -> void:
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var json_file := FileAccess.open(absolute_dir.path_join("matches.json"), FileAccess.WRITE)
	json_file.store_string(JSON.stringify(_reports, "  "))
	var matches_dir := absolute_dir.path_join("matches")
	DirAccess.make_dir_recursive_absolute(matches_dir)
	for report: Dictionary in _reports:
		var match_file := FileAccess.open(matches_dir.path_join("seed-%d.json" % int(report.seed)), FileAccess.WRITE)
		match_file.store_string(JSON.stringify(report, "  "))
	var csv_file := FileAccess.open(absolute_dir.path_join("matches.csv"), FileAccess.WRITE)
	csv_file.store_line("seed,player_count,strategy,turns,end_reason,aborted,abort_reason,winners")
	for report: Dictionary in _reports:
		csv_file.store_line("%d,%d,%s,%d,%d,%s,%s,%s" % [int(report.seed), int(report.player_count), report.strategy, int(report.turns), int(report.end_reason), str(report.aborted).to_lower(), _csv(report.abort_reason), _csv(str(report.get("winners", [])))])
	var markdown := FileAccess.open(absolute_dir.path_join("summary.md"), FileAccess.WRITE)
	markdown.store_string(_build_markdown_summary())

func _build_markdown_summary() -> String:
	var lines: Array[String] = ["# Beta 平衡模拟报告", "", "- 对局数：%d" % _reports.size(), "- 异常终止：%d" % _count_aborted(), "", "| 人数 | 策略 | 对局 | 平均回合 |", "|---:|---|---:|---:|"]
	for player_count: int in _requested_counts:
		for strategy: SimulationDecisionProvider.Strategy in _requested_strategies:
			var name := String(_strategy_name(strategy))
			var count := 0
			var turns := 0
			for report: Dictionary in _reports:
				if int(report.player_count) == player_count and report.strategy == name:
					count += 1
					turns += int(report.turns)
			lines.append("| %d | %s | %d | %.2f |" % [player_count, name, count, float(turns) / maxf(count, 1)])
	lines.append_array(["", "## 职业基线", "", "| 职业 | 样本 | 胜率 | 95% CI | 平均名次 | 平均分 |", "|---|---:|---:|---:|---:|---:|"])
	var profession_stats := _aggregate_profession_stats()
	var profession_names: Array = profession_stats.keys()
	profession_names.sort()
	for profession_name in profession_names:
		var stats: Dictionary = profession_stats[profession_name]
		var sample_count := int(stats.count)
		var win_rate := float(stats.wins) / maxf(sample_count, 1)
		var margin := 1.96 * sqrt(maxf(win_rate * (1.0 - win_rate) / maxf(sample_count, 1), 0.0))
		lines.append("| %s | %d | %.1f%% | %.1f%%–%.1f%% | %.2f | %.2f |" % [profession_name, sample_count, win_rate * 100.0, maxf(win_rate - margin, 0.0) * 100.0, minf(win_rate + margin, 1.0) * 100.0, float(stats.rank_sum) / sample_count, float(stats.score_sum) / sample_count])
	lines.append_array(["", "## 座位基线", "", "| 座位 | 样本 | 平均分 |", "|---:|---:|---:|"])
	var seat_stats := _aggregate_seat_stats()
	var seats: Array = seat_stats.keys()
	seats.sort()
	for seat in seats:
		var stats: Dictionary = seat_stats[seat]
		lines.append("| %d | %d | %.2f |" % [int(seat) + 1, int(stats.count), float(stats.score_sum) / maxf(int(stats.count), 1)])
	lines.append("")
	lines.append("置信区间为职业胜率的正态近似 95% 区间；小样本只用于烟雾验证。报告仅记录现状，不自动调整玩法数值。")
	return "\n".join(lines) + "\n"

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
