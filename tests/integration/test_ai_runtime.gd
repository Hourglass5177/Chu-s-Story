extends GutTest

const MAIN := preload("res://main_map.tscn")
var scene: Node
var controller: AISessionController
var first: PlayerClass
var second: PlayerClass
var _previous_profile: GameManager.RuntimeProfile
var _card_cache: Array = []
var _choice_result: Variant

func _capture_choice(request: EventChoiceRequest) -> void:
	_choice_result = await EventManager._request_choice(request)

func _capture_world_action(action: GameAction, player: PlayerClass) -> void:
	_choice_result = await controller.world.execute(action, player)

func before_all() -> void:
	for cards: Array in ResourceManager.地区非遗牌库.values(): _card_cache.append_array(cards)
	_card_cache.append_array(ResourceManager.食物牌库)
	_card_cache.append_array(ResourceManager.事件牌库)

func after_all() -> void:
	_card_cache.clear()

func before_each() -> void:
	_previous_profile = GameManager.runtime_profile
	GameManager.configure_session(9015, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	GameManager.reset_session()
	GameManager.player_data = [{"name": "真人", "job": "美食博主", "location": "十堰", "is_bot": false}, {"name": "电脑", "job": "商业博主", "location": "随州", "is_bot": true}]
	scene = MAIN.instantiate()
	add_child(scene)
	for frame: int in 20:
		await get_tree().process_frame
		if TurnManager.GameOn: break
	controller = get_tree().get_first_node_in_group("AI_SESSION") as AISessionController
	controller.set_process(false)
	first = TurnManager.players[0]
	second = TurnManager.players[1]
	TurnManager.turn_timer.stop()

func after_each() -> void:
	GameManager.reset_session(false)
	GameManager.runtime_profile = _previous_profile
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_observation_filters_hidden_hands_and_future_deck() -> void:
	TurnManager.change_phase(TurnManager.TurnPhase.MOVING)
	TurnManager.turn_timer.stop()
	first.maxMove = 6
	var original := controller.world.observe(first)
	assert_gt(original.actions.size(), 1, "Fairness comparison must exercise a real route decision")
	assert_false(original.state.players[1].has("foods"))
	assert_false(original.state.players[1].has("events"))
	assert_false(_contains_object(original.state))
	var a := 食物牌.new()
	a.food_id = &"re_gan_mian"
	second.食物牌手牌.append(a)
	var with_card := controller.world.observe(first)
	second.食物牌手牌[0] = 食物牌.new()
	ResourceManager.食物牌库.reverse()
	var swapped := controller.world.observe(first)
	assert_eq(with_card.state, swapped.state, "The identity of an opponent's food and future deck order are invisible")
	assert_eq(with_card.state.players[1].food_count, original.state.players[1].food_count + 1)
	for difficulty: int in 3:
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(difficulty)
		policy.configure(7781)
		var before_goal := policy.goals.snapshot()
		var before_random := policy.rng.state
		var selected := policy.choose(with_card)
		assert_not_null(selected)
		policy.goals.restore(before_goal)
		policy.rng.state = before_random
		policy.trace_enabled = true
		var replayed := policy.choose(swapped)
		assert_eq(selected.key() if selected != null else "", replayed.key() if replayed != null else "")

func test_stale_action_rejected_before_mutation() -> void:
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var action := controller.world._action(first, GameAction.Kind.END_PHASE)
	action.epoch -= 1
	assert_false(await controller.world.execute(action, first))
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)

func test_request_waits_for_human_and_routes_bot_after_registration() -> void:
	var human_request := EventChoiceRequest.new(first, "选择", [true], PackedStringArray(["确认"]))
	var human_ticket := InteractionCoordinator.begin_interaction(&"test", 0.0, Callable(), TurnManager.ModalResumePolicy.NO_RESUME, false, {"request": human_request})
	await get_tree().process_frame
	assert_true(human_ticket.is_waiting())
	assert_null(controller.pending_ticket)
	InteractionCoordinator.submit(human_ticket.interaction_id, true)
	await InteractionCoordinator.await_result(human_ticket)
	var bot_request := EventChoiceRequest.new(second, "选择", [true], PackedStringArray(["确认"]))
	EventManager._request_choice(bot_request)
	assert_gt(bot_request.request_id, 0)
	await get_tree().process_frame
	assert_not_null(controller.pending_ticket)
	controller._answer_ticket()
	await get_tree().process_frame
	assert_true(InteractionCoordinator.get_active_snapshot().is_empty())

func test_automatic_inheritance_once_and_refund_contract() -> void:
	first.is_bot = true
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var card := 非遗牌.new()
	card.category = 非遗牌.CardCategory.国家级非遗
	card.inheritance_task_id = &"yandi_shennong_chuanshuo"
	first.非遗牌手牌.append(card)
	var before := first.current_energy
	var attempt := HeritageTaskManager.begin_attempt(first, card)
	assert_not_null(attempt)
	var service := ComputerInheritanceService.new()
	service.configure(123)
	var result := service.sample_attempt(attempt)
	var random_state := service.rng.state
	assert_same(service.sample_attempt(attempt), result)
	assert_eq(service.rng.state, random_state)
	assert_eq(first.current_energy, before - 1)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.technical_error(card.inheritance_task_id, &"test_error", "测试退款")))
	assert_eq(first.current_energy, before)
	assert_true(HeritageTaskManager.get_attempt_check(first, card).allowed)
	assert_false(HeritageTaskManager.finish_attempt(attempt, result))
	for difficulty: int in 3:
		var profile := AIProfile.for_difficulty(difficulty)
		attempt = HeritageTaskManager.begin_attempt(first, card)
		assert_not_null(attempt)
		result = service.sample_attempt(attempt, profile)
		random_state = service.rng.state
		assert_same(service.sample_attempt(attempt, profile), result)
		assert_eq(service.rng.state, random_state)
		if difficulty == 2: assert_true(result.is_success())
		assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.technical_error(card.inheritance_task_id, &"test_error", "测试退款")))
		assert_eq(first.current_energy, before)

func test_map_query_is_independent_of_highlight_and_deduplicated() -> void:
	TurnManager.change_phase(TurnManager.TurnPhase.MOVING)
	TurnManager.turn_timer.stop()
	first.maxMove = 6
	var before: Dictionary = first.map.query_moves(first)
	for section: MapSection in first.map.grid_map.values(): section.is_reachable = not section.is_reachable
	assert_eq(first.map.query_moves(first), before)
	var ids: Array = []
	for section: MapSection in before:
		assert_false(ids.has(section.get_instance_id()))
		ids.append(section.get_instance_id())
		assert_lte(int(before[section].energy), first.current_energy)

func test_pause_blocks_bot_submission_and_session_cleans_memory() -> void:
	var lease := TurnManager.acquire_modal(&"pause_menu", TurnManager.ModalResumePolicy.RESUME_REMAINING, true)
	assert_true(controller.user_paused())
	TurnManager.release_modal(lease)
	assert_false(controller.user_paused())
	controller.memories[1]["peek"] = [{"id": 123}]
	assert_false(controller.memories.has(0), "Human and other bot knowledge is not shared")
	var epoch := TurnManager.get_session_generation()
	GameManager.reset_session(false)
	assert_ne(TurnManager.get_session_generation(), epoch)
	controller._process(1.0)
	assert_false(controller.is_processing())

func test_inheritance_success_and_failure_keep_cost_without_minigame_records() -> void:
	first.is_bot = true
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var discovery_before := DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME)
	var preferences_hash := FileAccess.get_sha256(HeritageMinigamePreferences.PATH) if FileAccess.file_exists(HeritageMinigamePreferences.PATH) else ""
	for expected: bool in [true, false]:
		var task_id: StringName = &"yandi_shennong_chuanshuo" if expected else &"xingshan_min_ge"
		var card := 非遗牌.new()
		card.category = 非遗牌.CardCategory.国家级非遗
		card.inheritance_task_id = task_id
		first.非遗牌手牌.append(card)
		var attempt := HeritageTaskManager.begin_attempt(first, card)
		assert_not_null(attempt)
		if attempt == null: continue
		var paid_energy := first.current_energy
		var seed_value := 0
		var probe := RandomNumberGenerator.new()
		while true:
			probe.seed = seed_value
			if ComputerInheritanceService.succeeds(probe.randf()) == expected: break
			seed_value += 1
		var service := ComputerInheritanceService.new()
		service.configure(seed_value)
		var result := service.sample_attempt(attempt)
		assert_eq(result.is_success(), expected)
		assert_true(result.metrics.is_empty(), "Automatic inheritance never fabricates performance metrics")
		assert_true(HeritageTaskManager.finish_attempt(attempt, result))
		assert_eq(first.current_energy, paid_energy)
		assert_eq(HeritageTaskManager.is_inherited(card), expected)
		assert_false(HeritageTaskManager.get_attempt_check(first, card).allowed)
	assert_eq(DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME), discovery_before)
	assert_eq(FileAccess.get_sha256(HeritageMinigamePreferences.PATH) if FileAccess.file_exists(HeritageMinigamePreferences.PATH) else "", preferences_hash)

func test_technical_inheritance_error_is_not_retried_by_controller_in_same_action() -> void:
	first.is_bot = true
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var card := 非遗牌.new()
	card.category = 非遗牌.CardCategory.国家级非遗
	card.inheritance_task_id = &"yandi_shennong_chuanshuo"
	first.非遗牌手牌.append(card)
	var attempt := HeritageTaskManager.begin_attempt(first, card)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.technical_error(card.inheritance_task_id, &"service_error", "服务故障")))
	assert_true(HeritageTaskManager.get_attempt_check(first, card).allowed, "Formal transaction refunds the attempt")
	assert_false(controller.world.legal_actions(first).any(func(a: GameAction): return a.kind == GameAction.Kind.INHERIT), "Controller suppresses a technical retry loop")

func test_last_human_elimination_does_not_end_computer_play() -> void:
	first.current_energy = 0
	TurnManager.change_phase(TurnManager.TurnPhase.END)
	TurnManager.turn_timer.stop()
	await TurnManager.now_turn_end()
	assert_false(first.alive)
	assert_true(TurnManager.GameOn)
	assert_eq(TurnManager.players[TurnManager.now_player_index], second)
	assert_true(second.is_bot)
	second.current_energy = 0
	TurnManager.change_phase(TurnManager.TurnPhase.END)
	TurnManager.turn_timer.stop()
	await TurnManager.now_turn_end()
	var result := TurnManager.get_game_result()
	assert_not_null(result)
	assert_false(TurnManager.GameOn)
	assert_false(controller.is_processing())

func test_bot_multi_selection_meets_constraints_and_does_not_share_memory() -> void:
	var a := 非遗牌.new()
	a.category = 非遗牌.CardCategory.戏曲表演
	var b := 非遗牌.new()
	b.category = 非遗牌.CardCategory.武术拳法
	var c := 非遗牌.new()
	c.category = 非遗牌.CardCategory.民间音乐
	second.非遗牌手牌.assign([a, b, c])
	var request := EventChoiceRequest.new(second, "测试强制弃牌", [a, b, c], PackedStringArray(), false, EventChoiceRequest.ChoiceKind.卡牌)
	request.multiple = true
	request.min_selections = 2
	request.max_selections = 2
	_capture_choice(request)
	await get_tree().process_frame
	assert_not_null(controller.pending_ticket)
	controller._answer_ticket()
	await get_tree().process_frame
	assert_eq((_choice_result as Array).size(), 2)
	assert_false((_choice_result as Array).has(b), "Retain the four-point martial card")
	controller.memories[1]["private"] = [{"id": 123}]
	var view := controller.world.observe(second, controller.memories[1])
	view.memory.private[0].id = 999
	assert_eq(controller.memories[1].private[0].id, 123)

func test_retained_event_uses_the_shared_resolution_context_and_cleanup() -> void:
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	first.事件牌手牌.append(card)
	var view := controller.world.observe(first)
	var action: GameAction
	for candidate: GameAction in view.actions:
		if candidate.kind == GameAction.Kind.USE_EVENT: action = candidate
	assert_not_null(action)
	_choice_result = null
	_capture_world_action(action, first)
	await get_tree().process_frame
	var request: EventChoiceRequest = EventManager._pending_request
	assert_not_null(request)
	assert_true(EventManager.resolving)
	assert_eq(request.source_id, &"you_mu_cheng_huai")
	EventManager.submit_choice(request.request_id, request.options[0])
	await get_tree().process_frame
	assert_true(_choice_result)
	assert_false(EventManager.resolving)
	assert_true(InteractionCoordinator.get_active_snapshot().is_empty())
	assert_eq(TurnManager.modal_resolution_depth, 0)

func test_easy_timeout_pause_profession_swap_and_session_cleanup() -> void:
	await _assert_difficulty_lifecycle(0)

func test_normal_timeout_pause_profession_swap_and_session_cleanup() -> void:
	await _assert_difficulty_lifecycle(1)

func test_hard_timeout_pause_profession_swap_and_session_cleanup() -> void:
	await _assert_difficulty_lifecycle(2)

func _assert_difficulty_lifecycle(difficulty: int) -> void:
	second.ai_difficulty = difficulty
	var policy: AIPolicy = controller.policies[1]
	policy.profile = AIProfile.for_difficulty(difficulty)
	var profession_before := int(first.player_types)
	assert_true(ProfessionManager.swap_professions(first, second))
	var observation := controller.world.observe(second)
	assert_eq(int(observation.state.self.profession), profession_before)
	assert_eq(int(observation.state.self.food_limit), 3, "Swapped food profession is visible immediately")
	assert_eq(second.ai_difficulty, difficulty)
	assert_eq(policy.profile.difficulty, difficulty)
	var request := EventChoiceRequest.new(second, "测试超时", [true], PackedStringArray(["确认"]), true)
	_capture_choice(request)
	await get_tree().process_frame
	var ticket := controller.pending_ticket
	assert_not_null(ticket)
	if ticket == null: return
	var pause := TurnManager.acquire_modal(&"pause_menu", TurnManager.ModalResumePolicy.RESUME_REMAINING, true)
	controller._process(100.0)
	assert_true(ticket.is_waiting(), "Paused bot does not submit even after its presentation delay")
	TurnManager.release_modal(pause)
	assert_true(InteractionCoordinator.resolve_timeout(ticket.interaction_id))
	await get_tree().process_frame
	controller._answer_ticket()
	assert_false(InteractionCoordinator.submit(ticket.interaction_id, true), "Late/duplicate reply cannot resolve an expired ticket")
	assert_true(InteractionCoordinator.get_active_snapshot().is_empty())
	var pending := EventChoiceRequest.new(second, "测试跨局", [true], PackedStringArray(["确认"]), true)
	_capture_choice(pending)
	await get_tree().process_frame
	var old_ticket := controller.pending_ticket
	var stale_action := controller.world._action(second, GameAction.Kind.END_PHASE)
	controller.memories[1]["private_marker"] = [123]
	var old_memories: Dictionary = controller.memories
	GameManager.reset_session(false)
	controller._process(100.0)
	assert_false(controller.is_processing())
	assert_false(await controller.world.execute(stale_action, second))
	if old_ticket != null: assert_false(InteractionCoordinator.submit(old_ticket.interaction_id, true))
	controller.queue_free()
	await get_tree().process_frame
	assert_true(old_memories.is_empty(), "Leaving the scene clears all per-seat knowledge")
	assert_true(InteractionCoordinator.get_active_snapshot().is_empty())

func _contains_object(value) -> bool:
	if value is Object: return true
	if value is Dictionary:
		for key in value:
			if _contains_object(key) or _contains_object(value[key]): return true
	if value is Array:
		for item in value:
			if _contains_object(item): return true
	return false
