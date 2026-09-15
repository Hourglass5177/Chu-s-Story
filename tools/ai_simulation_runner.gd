extends "res://tools/balance_simulation_runner.gd"

var _card_cache: Array = []
var _main_scene: PackedScene
var reports: Array = []
var match_count: int = 1
var offset: int = 0
var output_path: String = ""
var baseline: int = -1
var _errors: Array = []
var difficulty: int = 1
var pair: Array[int] = []
var mixed: bool = false
var unified_chance: bool = false
var seed_base: int = 20260916

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--matches="): match_count = int(argument.get_slice("=", 1))
		if argument.begins_with("--offset="): offset = int(argument.get_slice("=", 1))
		if argument.begins_with("--output="): output_path = argument.get_slice("=", 1)
		if argument.begins_with("--difficulty="): difficulty = int(argument.get_slice("=", 1))
		if argument.begins_with("--seed-base="): seed_base = int(argument.get_slice("=", 1))
		if argument == "--mixed": mixed = true
		if argument == "--unified-chance": unified_chance = true
		if argument.begins_with("--pair="):
			for value: String in argument.get_slice("=", 1).split(","): pair.append(int(value))
		if argument.begins_with("--baseline="): baseline = int(argument.get_slice("=", 1))
	InteractionCoordinator.decision_requested.connect(_answer_baseline)
	_run.call_deferred()

func _run() -> void:
	_main_scene = load("res://main_map.tscn")
	for cards: Array in ResourceManager.地区非遗牌库.values(): _card_cache.append_array(cards)
	_card_cache.append_array(ResourceManager.食物牌库)
	_card_cache.append_array(ResourceManager.事件牌库)
	var failed := false
	for index: int in match_count:
		var report := await _match(index + offset)
		reports.append(report)
		failed = failed or not bool(report.completed) or not report.diagnostics.is_empty()
		print("AI_MATCH ", JSON.stringify(report))
	if output_path.is_empty(): output_path = "res://artifacts/ai-matches.json" if baseline < 0 else "res://artifacts/ai-baseline-%d.json" % baseline
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	GameManager.reset_session(false)
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)

func _match(index: int) -> Dictionary:
	var counts := [2, 3, 6]
	var targets := [15, 20, 25, 30]
	var count: int = counts[index % 3]
	var schedule_index := floori(float(index) / 3.0)
	if not pair.is_empty():
		count = 2
		schedule_index = index / 2
	var config := SimulationSchedule.build_match(count, SimulationDecisionProvider.Strategy.SCORE_GREEDY, schedule_index, seed_base)
	GameManager.configure_session(config.world_seed, GameManager.RuntimeProfile.HEADLESS_SIMULATION, targets[(schedule_index / 36) % 4] if not pair.is_empty() else targets[schedule_index % 4])
	GameManager.reset_session()
	var data: Array = []
	for slot: int in count:
		data.append({"name": "AI%d" % slot, "job": config.professions[slot], "location": config.locations[slot], "is_bot": baseline < 0 or slot == schedule_index % count, "ai_difficulty": pair[(slot + index % 2) % 2] if not pair.is_empty() else ((slot + schedule_index) % 3 if mixed else difficulty)})
	GameManager.player_data = data
	_active_strategy = SimulationDecisionProvider.new(baseline as SimulationDecisionProvider.Strategy, config.decision_seed) if baseline >= 0 else null
	_errors.clear()
	var scene := _main_scene.instantiate()
	get_tree().root.add_child(scene)
	for frame: int in 120:
		await get_tree().process_frame
		if TurnManager.GameOn: break
	var controller := get_tree().get_first_node_in_group("AI_SESSION") as AISessionController
	if unified_chance:
		for policy: AIPolicy in controller.policies.values(): policy.profile.inheritance_chance = 0.8
	controller.diagnostic.connect(func(reason: String, details: Dictionary): _errors.append({"reason": reason, "details": details}))
	var start := Time.get_ticks_msec()
	var steps := 0
	while TurnManager.GameOn and TurnManager.now_turn <= 500 and Time.get_ticks_msec() - start < 60000:
		await get_tree().process_frame
		steps += 1
		if baseline >= 0 and not TurnManager.players[TurnManager.now_player_index].is_bot:
			await _drive_current_turn()
			continue
		# Deterministic clock driver: actions and choices still use the production controller.
		if TurnManager.modal_resolution_depth == 0 and InteractionCoordinator.get_active_snapshot().is_empty() and not controller.busy:
			if TurnManager.now_phase in [TurnManager.TurnPhase.BEGIN, TurnManager.TurnPhase.ROLL_DICE, TurnManager.TurnPhase.END]:
				await TurnManager._on_timer_timeout()
	var result: GameResult = TurnManager.get_game_result()
	var times: Array[int] = controller.decision_times_usec.duplicate()
	times.sort()
	var report := {"difficulty": difficulty, "difficulties": data.map(func(entry: Dictionary): return entry.ai_difficulty), "unified_chance": unified_chance, "index": index, "players": count, "completed": result != null, "turns": TurnManager.now_turn, "steps": steps, "elapsed_ms": Time.get_ticks_msec() - start, "p95_us": times[int(times.size() * 0.95)] if not times.is_empty() else 0, "phase": int(TurnManager.now_phase), "end_reason": int(result.end_reason) if result != null else -1, "target": targets[(schedule_index / 36) % 4] if not pair.is_empty() else targets[schedule_index % 4], "professions": config.professions, "locations": config.locations, "seed": config.world_seed, "baseline": baseline, "diagnostics": _errors.duplicate(true), "winner_seats": [], "final_players": [], "interaction": InteractionCoordinator.get_active_snapshot(), "modals": TurnManager.get_modal_snapshot()}
	report["decision_times_us"] = times
	report["result_entry_count"] = result.entries.size() if result != null else 0
	if result != null:
		for winner: GameResultEntry in result.winners: report.winner_seats.append(winner.player_index)
	for player: PlayerClass in TurnManager.players: report.final_players.append(controller.world.player_data(player, null))
	GameManager.reset_session(false)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return report

func _answer_baseline(ticket: InteractionTicket) -> void:
	if baseline < 0 or _active_strategy == null: return
	var request = ticket.metadata.get("request")
	var player: PlayerClass
	if request is EventChoiceRequest: player = request.requester
	elif request is ProfessionDrawRequest or request is ProfessionSectionChoiceRequest: player = request.player
	if player == null or player.is_bot: return
	InteractionCoordinator.submit(ticket.interaction_id, _active_strategy.decide(ticket))
