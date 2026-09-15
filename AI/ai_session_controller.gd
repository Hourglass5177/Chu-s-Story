class_name AISessionController
extends Node

signal action_completed(actor: int, kind: int, success: bool)
signal diagnostic(reason: String, details: Dictionary)

var world := AIWorldAdapter.new()
var policies: Dictionary = {}
var memories: Dictionary = {}
var inheritance := ComputerInheritanceService.new()
var decision_trace := AIDecisionTrace.new()
const SPEED_STEPS: Array[float] = [1.0, 1.5, 2.0, 3.0]
const ACTION_WAIT: float = 0.9
const PHASE_WAIT: float = 0.6
const RESPONSE_WAIT: float = 0.65
const MOVEMENT_BASE_SPEED: float = 0.65

var speed_index: int = 0
var _response_delay: float = 0.0
var busy: bool = false
var pending_ticket: InteractionTicket
var decision_times_usec: Array[int] = []
var _session: int = -1
var _epoch: int = -1
var _dirty: bool = true
var _delay: float = 0.0
var _excluded: Dictionary = {}
var _turn_fingerprints: Dictionary = {}
var _route: Line2D
var _speed: Button
var _inheritance_view: PanelContainer
var _inheritance_image: TextureRect
var _inheritance_label: Label
var _viewer_root: Control

func _ready() -> void:
	add_to_group("AI_SESSION")
	process_mode = Node.PROCESS_MODE_ALWAYS
	InteractionCoordinator.decision_requested.connect(_on_decision_requested)
	TurnManager.phase_changed.connect(_on_phase)
	TurnManager.game_finished.connect(_on_game_finished)
	TurnManager.modal_state_changed.connect(_on_modal)
	HeritageTaskManager.attempt_finished.connect(_on_inheritance_finished)
	set_process(false)

func configure(players: Array[PlayerClass], seed_value: int) -> void:
	_session = TurnManager.get_session_generation()
	decision_trace.enabled = "--ai-trace" in OS.get_cmdline_user_args()
	for player: PlayerClass in players:
		if not player.is_bot: continue
		var policy := AIPolicy.new()
		policy.profile = AIProfile.for_difficulty(player.ai_difficulty)
		policy.trace_enabled = decision_trace.enabled
		policy.configure(seed_value ^ (0x5912 + player.player_index * 104729))
		policies[player.player_index] = policy
		memories[player.player_index] = {}
	inheritance.configure(seed_value ^ 0x79A31)
	if policies.is_empty(): return
	if not GameManager.is_headless_simulation(): _build_viewer()
	set_process(true)

func _build_viewer() -> void:
	# Stay in the HUD canvas so its pause/guide overlays retain their higher z-order.
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 20
	add_child(layer)
	_viewer_root = layer
	var hint := TurnManager.hud.get_node("地图/缩放提示信息") as Label
	var turn_info := TurnManager.hud.get_node("回合信息") as Control
	_speed = Button.new()
	_speed.name = "AISpeedButton"
	_speed.flat = true
	_speed.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_speed.tooltip_text = "点击切换 AI 速度"
	_speed.add_theme_font_override("font", hint.get_theme_font("font"))
	_speed.add_theme_font_size_override("font_size", hint.get_theme_font_size("font_size"))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_speed.add_theme_color_override(state, Color.BLACK)
	_speed.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	_speed.add_theme_constant_override("outline_size", 2)
	layer.add_child(_speed)
	# Mirror the view hint around the centre of the existing turn information.
	var hint_rect := hint.get_global_rect()
	_speed.position = Vector2(2.0 * turn_info.get_global_rect().get_center().x - hint_rect.end.x, hint_rect.position.y)
	_speed.size = hint_rect.size
	_speed.pressed.connect(_cycle_speed)
	_update_speed_label()
	_inheritance_view = PanelContainer.new()
	_inheritance_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inheritance_view.position = Vector2(980, 430)
	_inheritance_view.custom_minimum_size = Vector2(600, 690)
	layer.add_child(_inheritance_view)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 20)
	_inheritance_view.add_child(column)
	_inheritance_image = TextureRect.new()
	_inheritance_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inheritance_image.custom_minimum_size = Vector2(480, 530)
	_inheritance_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inheritance_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_inheritance_image)
	_inheritance_label = Label.new()
	_inheritance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inheritance_label.add_theme_font_size_override("font_size", 32)
	column.add_child(_inheritance_label)
	_inheritance_view.hide()

func _on_phase(_phase: int) -> void:
	if _phase != int(TurnManager.TurnPhase.ACTION):
		world.shop.close()
		world.market_player = null
	_dirty = true
	_excluded.clear()
	_delay = 0.0 if GameManager.is_headless_simulation() else PHASE_WAIT

func _on_modal(_snapshot: Dictionary) -> void:
	_dirty = true
	if _viewer_root != null:
		_viewer_root.visible = TurnManager.GameOn and not user_paused()

func _on_game_finished(_result: GameResult) -> void:
	set_process(false)
	pending_ticket = null
	world.clear()
	if _inheritance_view != null: _inheritance_view.hide()
	if _viewer_root != null: _viewer_root.hide()

func _exit_tree() -> void:
	var trace_error := decision_trace.flush("res://artifacts/ai-traces/session-%d-%d.trace" % [OS.get_process_id(), _session])
	if trace_error != OK: push_warning("AI trace write failed: %d" % trace_error)
	set_process(false)
	pending_ticket = null
	world.clear()
	policies.clear()
	memories.clear()

func user_paused() -> bool:
	var snapshot := TurnManager.get_modal_snapshot()
	for owner in snapshot.get("tree_pause_owners", []):
		if String(owner) not in ["ai_inheritance"]: return true
	return bool(snapshot.get("tree_paused", false)) and int(snapshot.get("tree_pause_depth", 0)) == 0

func _process(delta: float) -> void:
	if _session != TurnManager.get_session_generation() or not TurnManager.GameOn:
		set_process(false)
		return
	if user_paused(): return
	if pending_ticket != null:
		_response_delay = maxf(0.0, _response_delay - delta * get_speed_multiplier())
		if _response_delay <= 0.0: _answer_ticket()
	if busy or not _dirty or TurnManager.is_movement_locked() or not InteractionCoordinator.get_active_snapshot().is_empty(): return
	_delay = maxf(0.0, _delay - delta * get_speed_multiplier())
	if _delay > 0.0: return
	if TurnManager.players.is_empty(): return
	var player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	if not player.is_bot: return
	if _epoch != TurnManager.get_turn_epoch():
		_epoch = TurnManager.get_turn_epoch()
		_excluded.clear()
		# Repeated salary alone is not strategic progress: otherwise free-work professions can stall forever.
		var fingerprint := "%d:%d:%d:%d:%d" % [player.current_energy, player.current_score, player.食物牌手牌.size(), player.事件牌手牌.size(), player.非遗牌手牌.size()]
		var previous: Dictionary = _turn_fingerprints.get(player.player_index, {})
		var positions: Array = previous.get("positions", [])
		var idle := int(previous.get("idle", 0)) + 1 if previous.get("fingerprint", "") == fingerprint and positions.has(player.now_pos) else 0
		positions.append(player.now_pos)
		if positions.size() > 6: positions.pop_front()
		_turn_fingerprints[player.player_index] = {"fingerprint": fingerprint, "idle": idle, "positions": positions}
		memories[player.player_index]["idle_turns"] = idle
		memories[player.player_index]["movement_positions"] = [player.now_pos]
	if TurnManager.now_phase not in [TurnManager.TurnPhase.MOVING, TurnManager.TurnPhase.ACTION]: return
	if TurnManager.modal_resolution_depth > 0: return
	_dirty = false
	busy = true
	_decide_and_execute(player)

func _decide_and_execute(player: PlayerClass) -> void:
	if TurnManager.hud != null:
		await TurnManager.hud.wait_for_card_hand_animations()
	while user_paused() and _session == TurnManager.get_session_generation() and TurnManager.GameOn:
		await get_tree().process_frame
	if _session != TurnManager.get_session_generation() or not TurnManager.GameOn:
		busy = false
		return
	var start := Time.get_ticks_usec()
	var observation := world.observe(player, memories.get(player.player_index, {}))
	var policy: AIPolicy = policies[player.player_index]
	var before_goal := policy.goals.snapshot() if decision_trace.enabled else {}
	var before_rng := policy.rng.state
	var before_excluded := _excluded.duplicate()
	var paused_usec: int = 0
	policy.begin_plan(observation, _excluded)
	while not policy.advance_plan(0 if GameManager.is_headless_simulation() else Time.get_ticks_usec() + policy.profile.frame_budget_usec):
		await get_tree().process_frame
		if user_paused():
			var pause_start := Time.get_ticks_usec()
			while user_paused() and _session == TurnManager.get_session_generation() and TurnManager.GameOn: await get_tree().process_frame
			paused_usec += Time.get_ticks_usec() - pause_start
		if _session != TurnManager.get_session_generation() or not TurnManager.GameOn:
			busy = false
			return
	var action := policy.get_plan_result()
	var elapsed_usec := Time.get_ticks_usec() - start - paused_usec
	decision_times_usec.append(elapsed_usec)
	if action == null or action.session != TurnManager.get_session_generation() or action.epoch != TurnManager.get_turn_epoch() or action.phase != int(TurnManager.now_phase):
		busy = false
		_dirty = true
		return
	player.computer_presentation_speed = MOVEMENT_BASE_SPEED * get_speed_multiplier()
	if action.kind == GameAction.Kind.MOVE: _show_route(player, action)
	var success := false
	if action.kind == GameAction.Kind.INHERIT:
		success = await _perform_inheritance(player, world.objects.get(action.target))
	else:
		success = await world.execute(action, player)
	if _session != TurnManager.get_session_generation() or not is_inside_tree(): return
	if _route != null and is_instance_valid(_route):
		_route.queue_free()
		_route = null
	if not success:
		_excluded[action.key()] = true
		diagnostic.emit("action_rejected", {"action": action.key(), "epoch": action.epoch})
	else:
		_excluded.clear()
		if action.kind == GameAction.Kind.MOVE:
			memories[player.player_index].get_or_add("movement_positions", []).append(action.data.position)
	decision_trace.capture(observation, policy, before_goal, before_rng, before_excluded, action, elapsed_usec, success)
	action_completed.emit(action.actor, action.kind, success)
	busy = false
	_dirty = true
	_delay = 0.0 if GameManager.is_headless_simulation() else ACTION_WAIT

func _perform_inheritance(player: PlayerClass, card: 非遗牌) -> bool:
	var attempt := HeritageTaskManager.begin_attempt(player, card)
	if attempt == null: return false
	var result := inheritance.sample_attempt(attempt, (policies[player.player_index] as AIPolicy).profile)
	if result == null:
		return HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.technical_error(attempt.task_id, &"computer_service_error", "电脑传承服务未返回结果"))
	var lease := TurnManager.acquire_modal(&"ai_inheritance", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	if _inheritance_view != null:
		_inheritance_image.texture = card.image_of_front
		_inheritance_label.text = "%s\n电脑自动传承…" % player.player_name
		_inheritance_view.show()
	var elapsed := 0.0
	while not GameManager.is_headless_simulation() and elapsed < 3.0:
		await get_tree().process_frame
		if _session != TurnManager.get_session_generation() or not TurnManager.GameOn: return false
		if not user_paused(): elapsed += get_process_delta_time() * get_speed_multiplier()
	var success := HeritageTaskManager.finish_attempt(attempt, result)
	TurnManager.release_modal(lease)
	if _inheritance_view != null:
		_inheritance_label.text = result.message
		elapsed = 0.0
		while elapsed < 1.2 and TurnManager.GameOn:
			await get_tree().process_frame
			if _session != TurnManager.get_session_generation(): return success
			if not user_paused(): elapsed += get_process_delta_time() * get_speed_multiplier()
		_inheritance_view.hide()
	return success

func _on_decision_requested(ticket: InteractionTicket) -> void:
	var request = ticket.metadata.get("request")
	var player: PlayerClass
	if request is EventChoiceRequest: player = request.requester
	elif request is ProfessionDrawRequest or request is ProfessionSectionChoiceRequest: player = request.player
	if player != null and player.is_bot and policies.has(player.player_index):
		pending_ticket = ticket
		_response_delay = 0.0 if GameManager.is_headless_simulation() else RESPONSE_WAIT

func _answer_ticket() -> void:
	var ticket := pending_ticket
	if not ticket.is_waiting():
		pending_ticket = null
		return
	if InteractionCoordinator.is_active_suspended(): return
	var request = ticket.metadata.get("request")
	if request == null:
		pending_ticket = null
		return
	var player: PlayerClass = request.requester if request is EventChoiceRequest else request.player
	if player == null or not player.is_bot: return
	var observation := world.observe(player, memories[player.player_index])
	var policy: AIPolicy = policies[player.player_index]
	policy.prepare_choice_observation(observation)
	pending_ticket = null
	if request is ProfessionDrawRequest:
		var ordered: Array = request.cards.duplicate()
		ordered.sort_custom(func(a, b): return policy.card_value(world.card_data(a), observation) > policy.card_value(world.card_data(b), observation))
		if ordered.is_empty(): return
		var chosen = ordered.pop_front()
		var remembered: Array = []
		for card in ordered: remembered.append(world.card_data(card))
		var memory_key := String(request.deck_kind)
		if chosen is 非遗牌: memory_key += ":%d" % int(chosen.region)
		memories[player.player_index][memory_key] = remembered
		ProfessionManager.submit_draw_choice(request.request_id, chosen, ordered)
	elif request is ProfessionSectionChoiceRequest:
		var best: MapSection
		var value := 0.0
		for section: MapSection in request.options:
			var data := world.section_data(section, player)
			var candidate := policy.section_value(data, observation.state.self)
			if bool(data.fresh_scenery) and TurnManager.now_phase == TurnManager.TurnPhase.BEGIN: candidate += mini(3, 12 - player.current_energy) * 18.0
			if candidate > value:
				value = candidate
				best = section
		ProfessionManager.submit_section_choice(request.request_id, best)
	elif request is EventChoiceRequest:
		var choices: Array = []
		for option in request.options:
			var value := _option_value(option, request, observation, policy, player)
			choices.append({"option": option, "value": value})
		choices.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.value) > float(b.value))
		if request.multiple:
			var selected: Array = []
			for choice: Dictionary in choices:
				if selected.size() >= request.max_selections: break
				if selected.size() < request.min_selections or float(choice.value) > 0: selected.append(choice.option)
			EventManager.submit_choice(request.request_id, selected)
		else:
			var selected = null if choices.is_empty() or (request.optional and float(choices[0].value) <= 0) else choices[0].option
			EventManager.submit_choice(request.request_id, selected)
	_dirty = true

func _option_value(option, request: EventChoiceRequest, observation: AIObservation, policy: AIPolicy, player: PlayerClass) -> float:
	return AIChoicePolicy.value(world.choice_option_data(option, player), {"source_id": String(request.source_id), "purpose": String(request.purpose), "context": request.decision_context.duplicate(true)}, observation, policy)

func get_speed_multiplier() -> float:
	return SPEED_STEPS[speed_index]

func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEED_STEPS.size()
	_update_speed_label()

func _update_speed_label() -> void:
	if _speed != null: _speed.text = "AI速度：x%.2f" % get_speed_multiplier()

func _show_route(player: PlayerClass, action: GameAction) -> void:
	if GameManager.is_headless_simulation(): return
	_route = Line2D.new()
	_route.width = 5.0
	_route.default_color = Color(0.92, 0.47, 0.08, 0.9)
	_route.z_index = 10
	player.map.add_child(_route)
	_route.add_point(player.map.to_local(player.global_position))
	for coordinate: Vector3i in action.data.get("coordinates", []):
		_route.add_point(player.map.to_local(player.map.grid_map[coordinate].global_position))

func _on_inheritance_finished(attempt: HeritageTaskAttempt, result: HeritageTaskResult) -> void:
	if result.status == HeritageTaskResult.Status.TECHNICAL_ERROR and attempt.player != null and attempt.player.is_bot and attempt.session_generation == _session:
		world.blocked_inheritance[attempt.card.get_instance_id()] = attempt.turn_epoch
