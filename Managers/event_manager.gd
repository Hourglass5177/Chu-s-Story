extends Node

signal event_revealed(player: PlayerClass, card: 事件牌)
signal gameplay_event_triggered(player: PlayerClass, card: 事件牌)
signal choice_requested(request: EventChoiceRequest)
signal reaction_requested(request: EventChoiceRequest)
signal choice_resolved(request_id: int, timed_out: bool)
signal event_finished(player: PlayerClass, card: 事件牌, summary: String)
signal interaction_finished(player: PlayerClass)
signal retained_cards_changed(player: PlayerClass)
signal effect_response_resolved(effect_kind: StringName, response_kind: StringName, responder: PlayerClass, target: PlayerClass)


class EventResolutionContext extends RefCounted:
	var session_token: int
	var resolution_id: int
	var cancelled: bool = false
	var source_card: 事件牌 = null
	var modal_lease_id: int = -1

	func _init(current_session_token: int, current_resolution_id: int, card: 事件牌 = null) -> void:
		session_token = current_session_token
		resolution_id = current_resolution_id
		source_card = card

const CHOICE_TIMEOUT_SECONDS: float = 15.0
const IMPLEMENTED_EVENT_IDS: Array[StringName] = [
	&"zuo_shou_yu_li", &"bai_ge_zheng_liu", &"pou_duo_yi_gua", &"gu_zhu_yi_zhi", &"ba_geng_xie_ye",
	&"yi_chuang_zeng_shou", &"wen_hua_xin_feng", &"jiao_huan_ren_sheng",
	&"mei_mei_yu_gong", &"yang_jing_xu_rui", &"miao_shou_hui_chun", &"cun_bu_nan_xing",
	&"jing_pi_li_jin", &"bi_men_xie_ke", &"juan_yi_xiu_zheng", &"you_mu_cheng_huai",
	&"chen_jin_ti_yan", &"yi_wai_zhi_xi", &"xin_huo_xiang_chuan", &"you_shi_tong_xiang",
	&"chuan_yi_hu_jian", &"yi_cang_hu_huan", &"tai_jiu_huan_xin", &"wen_hua_gong_xiang",
	&"tong_tai_jing_ji", &"yi_shi_hui_you", &"gu_di_chong_you", &"dou_zhuan_xing_yi",
	&"chang_xing_wu_zu", &"ri_xing_qian_li", &"yi_jing_xun_zong", &"tong_xing_feng_cai",
	&"guo_bao_hu_hang", &"jin_chan_tuo_qiao", &"yi_hua_jie_mu", &"jin_ji_bi_xian",
	&"jian_wang_zhi_lai", &"fu_di_chou_xin", &"zhan_yi_gong_yan", &"shi_ji_tao_zhen",
]

var hud: HUD = null
var event_overlay: Control = null
var resolving: bool = false
var auto_resolve_choices: bool = false
var choice_strategy: Callable = Callable()

var _request_sequence: int = 0
var _pending_request: EventChoiceRequest = null
var _pending_choice = null
var _choice_waiting: bool = false
var _choice_timer: Timer = null
var _status_by_player: Dictionary = {}
var _phase_message_by_player: Dictionary = {}
var _last_consumed_status_source: String = "事件效果"
var _skip_current_action_after_event: bool = false
var _session_token: int = 0
var _resolution_sequence: int = 0
var _active_resolution_contexts: Array[EventResolutionContext] = []
var _resolution_context_stack: Array[EventResolutionContext] = []
var _current_resolution_context: EventResolutionContext = null

func _ready() -> void:
	_choice_timer = Timer.new()
	_choice_timer.one_shot = true
	_choice_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_choice_timer)
	_choice_timer.timeout.connect(_on_choice_timeout)

func bind_runtime(target_hud: HUD, overlay: Control = null) -> void:
	if hud != null and hud != target_hud:
		hud.cancel_event_presentation(&"runtime_rebind")
	hud = target_hud
	event_overlay = overlay

func reset_for_new_game() -> void:
	if hud != null:
		hud.cancel_event_presentation(&"session_reset")
	_cancel_all_resolution_contexts()
	_release_revive_modal()
	if _pending_request != null:
		InteractionCoordinator.cancel(_pending_request.request_id, &"event_reset")
	_session_token += 1
	resolving = false
	_request_sequence = 0
	_pending_request = null
	_pending_choice = null
	_choice_waiting = false
	_status_by_player.clear()
	_phase_message_by_player.clear()
	_skip_current_action_after_event = false
	auto_resolve_choices = false
	choice_strategy = Callable()
	if _choice_timer != null:
		_choice_timer.stop()
	interaction_finished.emit(null)


## 只取消当前尚未完成的交互事务，不清空本局持续状态或牌库。
## TurnManager 在回合交接发现脏状态时调用；旧协程会通过 resolution context
## 失效检查自行退出，不能继续修改下一位玩家的回合。
func cancel_active_resolution(reason: StringName = &"cancelled") -> void:
	if hud != null:
		hud.cancel_event_presentation(reason)
	if _pending_request != null:
		InteractionCoordinator.cancel(_pending_request.request_id, reason)
	_cancel_all_resolution_contexts()
	_release_revive_modal()
	resolving = false
	_pending_request = null
	_pending_choice = null
	_choice_waiting = false
	_skip_current_action_after_event = false
	if _choice_timer != null:
		_choice_timer.stop()
	interaction_finished.emit(null)


func _begin_resolution_context(card: 事件牌 = null) -> EventResolutionContext:
	_resolution_sequence += 1
	var context := EventResolutionContext.new(_session_token, _resolution_sequence, card)
	_active_resolution_contexts.append(context)
	_resolution_context_stack.append(context)
	_current_resolution_context = context
	return context


func _finish_resolution_context(context: EventResolutionContext) -> void:
	if context == null:
		return
	# 正常路径应在进入这里前按明确策略释放。这个防线保证以后
	# 新增早退分支时也不会把事件模态留给下一个回合。
	_release_resolution_modal(context, TurnManager.ModalResumePolicy.NO_RESUME)
	_active_resolution_contexts.erase(context)
	_resolution_context_stack.erase(context)
	_current_resolution_context = _resolution_context_stack.back() if not _resolution_context_stack.is_empty() else null


func _cancel_all_resolution_contexts() -> void:
	for context: EventResolutionContext in _active_resolution_contexts:
		context.cancelled = true
		_release_resolution_modal(context, TurnManager.ModalResumePolicy.NO_RESUME)
	_active_resolution_contexts.clear()
	_resolution_context_stack.clear()
	_current_resolution_context = null


func _acquire_resolution_modal(
	context: EventResolutionContext,
	owner: StringName,
	resume_policy: TurnManager.ModalResumePolicy
) -> int:
	if context == null:
		return -1
	if context.modal_lease_id >= 0:
		return context.modal_lease_id
	context.modal_lease_id = TurnManager.acquire_modal(owner, resume_policy)
	return context.modal_lease_id


func _release_resolution_modal(
	context: EventResolutionContext,
	resume_policy_override: int = -1
) -> bool:
	if context == null or context.modal_lease_id < 0:
		return false
	var lease_id := context.modal_lease_id
	context.modal_lease_id = -1
	return TurnManager.release_modal(lease_id, resume_policy_override)


func _is_resolution_context_cancelled(context: EventResolutionContext) -> bool:
	return context != null and (
		context.cancelled
		or context.session_token != _session_token
		or not _active_resolution_contexts.has(context)
	)

func submit_choice(request_id: int, choice) -> void:
	if not _choice_waiting or _pending_request == null:
		return
	if request_id != _pending_request.request_id:
		return
	if _pending_request.multiple:
		if not choice is Array \
				or choice.size() < _pending_request.min_selections \
				or choice.size() > _pending_request.max_selections:
			return
		var unique_choices: Array = []
		for selected in choice:
			if not _pending_request.options.has(selected) or unique_choices.has(selected):
				return
			unique_choices.append(selected)
	elif choice != null and not _pending_request.options.has(choice):
		return
	var candidate_choice = choice.duplicate() if choice is Array else choice
	if InteractionCoordinator.submit(request_id, choice):
		_pending_choice = candidate_choice
		return
	# 协调器仍持有这个请求时，提交失败表示它正被指南挂起或已不再接收输入。
	# 不能跌入旧式兼容路径，否则背景 UI 会在说明页上方偷偷结束选择。
	if _coordinator_owns_request(request_id):
		return
	# 兼容测试夹具和仍在迁移中的外部调用：它们会直接构造旧式请求，
	# 但不能因此让地图选择界面永久等待一个并不存在的协调器票据。
	_pending_choice = candidate_choice
	_choice_waiting = false
	if _choice_timer != null:
		_choice_timer.stop()
	choice_resolved.emit(request_id, false)
	_pending_request = null

func submit_choice_preview(request_id: int, choice: Array) -> void:
	if not _choice_waiting or _pending_request == null or request_id != _pending_request.request_id:
		return
	if not _pending_request.multiple or choice.size() > _pending_request.max_selections:
		return
	for selected in choice:
		if not _pending_request.options.has(selected):
			return
	var candidate_preview := choice.duplicate()
	if InteractionCoordinator.update_preview(request_id, candidate_preview):
		_pending_choice = candidate_preview
		return
	if _coordinator_owns_request(request_id):
		return
	# 只为没有协调器票据的旧式测试夹具保留本地预览。
	_pending_choice = candidate_preview

func get_choice_time_left(request_id: int = -1) -> float:
	if not _choice_waiting or _pending_request == null:
		return 0.0
	if request_id >= 0 and request_id != _pending_request.request_id:
		return 0.0
	if _coordinator_owns_request(_pending_request.request_id):
		return maxf(0.0, InteractionCoordinator.get_time_left(_pending_request.request_id))
	return _choice_timer.time_left if _choice_timer != null else 0.0


func _coordinator_owns_request(request_id: int) -> bool:
	var snapshot: Dictionary = InteractionCoordinator.get_active_snapshot()
	return int(snapshot.get("interaction_id", -1)) == request_id

func _request_choice(request: EventChoiceRequest, is_reaction: bool = false):
	var resolution_context := _current_resolution_context
	if _is_resolution_context_cancelled(resolution_context):
		return null
	if request.options.is_empty():
		return null
	# EventManager 只有一组 pending 状态。新请求必须先确认没有既有请求，且只有
	# InteractionCoordinator 接受票据后才能发布 pending；否则并发失败会覆盖并清空
	# 仍在等待的首个请求，表现为选择界面卡死到超时。
	if _choice_waiting or _pending_request != null:
		push_warning("EventManager: 仍有事件选择等待中，拒绝新请求。")
		return null
	# 外部玩法（目前主要是食物）只复用本管理器的选择和响应链，
	# 不属于一张事件牌的完整结算，因此不会在末尾发送 interaction_finished。
	# 明确要求遮罩随本次选择关闭，避免永久停留在“结算中”。
	request.close_overlay_on_resolve = resolution_context == null
	request.timeout_seconds = CHOICE_TIMEOUT_SECONDS
	var ticket := InteractionCoordinator.begin_interaction(&"event", request.timeout_seconds, _resolve_choice_timeout, TurnManager.ModalResumePolicy.NO_RESUME, false, {"request": request})
	if ticket == null:
		return null
	request.request_id = ticket.interaction_id
	_request_sequence = maxi(_request_sequence, request.request_id)
	_pending_request = request
	_pending_choice = [] if request.multiple else null
	_choice_waiting = true
	if request.multiple:
		InteractionCoordinator.update_preview(request.request_id, _pending_choice)
	if is_reaction:
		reaction_requested.emit(request)
	else:
		choice_requested.emit(request)
	if choice_strategy.is_valid():
		var chosen_by_strategy = choice_strategy.call(request)
		InteractionCoordinator.submit(request.request_id, chosen_by_strategy)
	elif auto_resolve_choices or event_overlay == null:
		var automatic = _default_multiple_choice(request) if request.multiple else (null if request.optional else request.options[0])
		InteractionCoordinator.submit(request.request_id, automatic)
	var interaction_result: InteractionResult = await InteractionCoordinator.await_result(ticket)
	if _pending_request == request:
		_choice_waiting = false
	choice_resolved.emit(request.request_id, interaction_result.timed_out)
	if _is_resolution_context_cancelled(resolution_context):
		return null
	var result = interaction_result.value
	if _pending_request == request:
		_pending_request = null
		_pending_choice = null
	return result

func _resolve_choice_timeout(ticket: InteractionTicket):
	var request: EventChoiceRequest = ticket.metadata.get("request") as EventChoiceRequest if ticket != null else null
	if request == null or request.options.is_empty():
		return null
	if request.multiple:
		var selected: Array = ticket.preview.duplicate() if ticket.preview is Array else []
		if not request.optional:
			for option in request.options:
				if selected.size() >= request.min_selections:
					break
				if not selected.has(option):
					selected.append(option)
		return selected
	return null if request.optional else request.options[0]

func _on_choice_timeout() -> void:
	if not _choice_waiting or _pending_request == null:
		return
	if InteractionCoordinator.resolve_timeout(_pending_request.request_id):
		return
	# 仍由协调器持有时，false 只表示尚未到期或正被指南挂起。
	# 旧 Timer/隐藏 UI 的回调不能越权结算它。
	if _coordinator_owns_request(_pending_request.request_id):
		return
	# 旧式请求的超时也遵循统一裁定，随后只结束一次 UI 生命周期。
	if _pending_request.multiple:
		_pending_choice = _pending_choice.duplicate() if _pending_choice is Array else []
		if not _pending_request.optional:
			for option in _pending_request.options:
				if _pending_choice.size() >= _pending_request.min_selections:
					break
				if not _pending_choice.has(option):
					_pending_choice.append(option)
	else:
		_pending_choice = null if _pending_request.optional else _pending_request.options[0]
	_choice_waiting = false
	if _choice_timer != null:
		_choice_timer.stop()
	var resolved_request_id := _pending_request.request_id
	choice_resolved.emit(resolved_request_id, true)
	_pending_request = null


func _default_multiple_choice(request: EventChoiceRequest) -> Array:
	if request == null or request.optional:
		return []
	return request.options.slice(0, mini(request.min_selections, request.options.size()))

func _labels_for_players(players: Array[PlayerClass]) -> PackedStringArray:
	var labels := PackedStringArray()
	for player: PlayerClass in players:
		labels.append(player.player_name)
	return labels

func is_event_implemented(event_id: StringName) -> bool:
	return event_id in IMPLEMENTED_EVENT_IDS

func _labels_for_cards(cards: Array) -> PackedStringArray:
	var labels := PackedStringArray()
	for card in cards:
		labels.append(card.card_name)
	return labels

func _alive_players() -> Array[PlayerClass]:
	var result: Array[PlayerClass] = []
	for player: PlayerClass in TurnManager.players:
		if player.alive:
			result.append(player)
	return result

func _player_status(player: PlayerClass) -> Dictionary:
	if not _status_by_player.has(player):
		_status_by_player[player] = {}
	return _status_by_player[player]

func add_status(player: PlayerClass, status_id: StringName, phases: int, source_name: String = "事件效果") -> void:
	var statuses := _player_status(player)
	statuses[status_id] = {
		"remaining": maxi(phases, 0),
		"applied_turn": TurnManager.now_turn,
		"source_name": source_name,
	}


func take_phase_message(player: PlayerClass) -> String:
	var message := String(_phase_message_by_player.get(player, ""))
	_phase_message_by_player.erase(player)
	return message


func _set_phase_message(player: PlayerClass, message: String) -> void:
	if player != null and not message.is_empty():
		var previous := String(_phase_message_by_player.get(player, ""))
		_phase_message_by_player[player] = message if previous.is_empty() else "%s\n%s" % [previous, message]

func get_status_remaining(player: PlayerClass, status_id: StringName) -> int:
	var status: Dictionary = _player_status(player).get(status_id, {})
	return int(status.get("remaining", 0))

func has_status(player: PlayerClass, status_id: StringName) -> bool:
	return get_status_remaining(player, status_id) > 0

func _consume_status_phase(player: PlayerClass, status_id: StringName) -> bool:
	var statuses := _player_status(player)
	if not statuses.has(status_id):
		return false
	var status: Dictionary = statuses[status_id]
	if int(status.get("remaining", 0)) <= 0:
		statuses.erase(status_id)
		return false
	if TurnManager.now_turn <= int(status.get("applied_turn", -1)):
		return false
	_last_consumed_status_source = String(status.get("source_name", "事件效果"))
	status["remaining"] = int(status["remaining"]) - 1
	statuses[status_id] = status
	if int(status["remaining"]) <= 0:
		statuses.erase(status_id)
	return true

func on_phase_entered(player: PlayerClass, phase: TurnManager.TurnPhase) -> bool:
	_phase_message_by_player.erase(player)
	if phase == TurnManager.TurnPhase.BEGIN:
		var statuses := _player_status(player)
		statuses.erase(&"free_move_this_phase")
		statuses.erase(&"ignore_special_terrain_this_phase")
	elif phase == TurnManager.TurnPhase.MOVING:
		if _consume_status_phase(player, &"free_move_phases"):
			_player_status(player)[&"free_move_this_phase"] = {"remaining": 1, "applied_turn": TurnManager.now_turn}
			_set_phase_message(player, "【%s】生效：本移动阶段移动不消耗精力。" % _last_consumed_status_source)
		if _consume_status_phase(player, &"skip_moving"):
			_set_phase_message(player, "【%s】生效：跳过移动阶段。" % _last_consumed_status_source)
			return true
	elif phase == TurnManager.TurnPhase.ACTION:
		if _consume_status_phase(player, &"skip_action"):
			_set_phase_message(player, "【%s】生效：跳过行动阶段。" % String(_last_consumed_status_source))
			return true
	elif phase == TurnManager.TurnPhase.END:
		_tick_end_of_turn_status(player, &"work_banned")
		_tick_end_of_turn_status(player, &"scenery_banned")
	return false

func _tick_end_of_turn_status(player: PlayerClass, status_id: StringName) -> void:
	var statuses := _player_status(player)
	if not statuses.has(status_id):
		return
	var status: Dictionary = statuses[status_id]
	if TurnManager.now_turn <= int(status.get("applied_turn", -1)):
		return
	status["remaining"] = int(status.get("remaining", 0)) - 1
	if int(status["remaining"]) <= 0:
		statuses.erase(status_id)
	else:
		statuses[status_id] = status

func is_work_banned(player: PlayerClass) -> bool:
	return has_status(player, &"work_banned")

func is_scenery_banned(player: PlayerClass) -> bool:
	return has_status(player, &"scenery_banned")

func is_loss_immune(player: PlayerClass) -> bool:
	var status: Dictionary = _player_status(player).get(&"loss_immunity", {})
	return int(status.get("turn", -1)) == TurnManager.now_turn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION

func adjust_movement_cost(player: PlayerClass, total_cost: int, base_steps: int, target: MapSection) -> int:
	var statuses := _player_status(player)
	if statuses.has(&"free_move_this_phase"):
		return 0
	if statuses.has(&"ignore_special_terrain_this_phase") and target.landform != MapSection.LandForm.平原:
		statuses.erase(&"ignore_special_terrain_this_phase")
		return 0
	return total_cost

func has_free_move_this_phase(player: PlayerClass) -> bool:
	return _player_status(player).has(&"free_move_this_phase")

func can_ignore_special_terrain_this_phase(player: PlayerClass) -> bool:
	return _player_status(player).has(&"ignore_special_terrain_this_phase")

func open_retained_event_menu(player: PlayerClass) -> void:
	if resolving or TurnManager.is_modal_resolution_active() or player == null:
		return
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size():
		return
	if player != TurnManager.players[TurnManager.now_player_index]:
		return
	var playable: Array[事件牌] = []
	for card: 事件牌 in player.事件牌手牌:
		if _can_play_retained_now(card, player):
			playable.append(card)
	if playable.is_empty():
		if hud != null:
			hud._update_game_informs("暂无可用事件牌。")
		return
	var resolution_context := _begin_resolution_context()
	resolving = true
	_acquire_resolution_modal(
		resolution_context,
		&"retained_event_menu",
		TurnManager.ModalResumePolicy.RESET_ACTION
			if TurnManager.now_phase == TurnManager.TurnPhase.ACTION
			else TurnManager.ModalResumePolicy.RESUME_REMAINING
	)
	var request := EventChoiceRequest.new(player, "选择要使用的保留事件牌", playable, _labels_for_cards(playable), true, EventChoiceRequest.ChoiceKind.卡牌)
	var selected = await _request_choice(request)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if selected is 事件牌:
		resolution_context.source_card = selected as 事件牌
		await play_retained_event(player, selected as 事件牌)
		if _is_resolution_context_cancelled(resolution_context):
			return
	resolving = false
	_release_resolution_modal(
		resolution_context,
		TurnManager.ModalResumePolicy.RESET_ACTION
			if TurnManager.now_phase == TurnManager.TurnPhase.ACTION
			else TurnManager.ModalResumePolicy.RESUME_REMAINING
	)
	_finish_resolution_context(resolution_context)
	interaction_finished.emit(player)

func can_play_retained_event_now(card: 事件牌, player: PlayerClass = null) -> bool:
	if resolving or TurnManager.is_modal_resolution_active() or card == null or player == null or not player.事件牌手牌.has(card):
		return false
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size():
		return false
	return player == TurnManager.players[TurnManager.now_player_index] and _can_play_retained_now(card, player)

func get_retained_event_usage_hint(card: 事件牌, player: PlayerClass = null) -> String:
	if card == null:
		return ""
	match card.event_id:
		&"you_mu_cheng_huai":
			return "行动阶段" if player == null or not is_scenery_banned(player) else "闭门谢客期间不可用"
		&"chang_xing_wu_zu":
			return "移动阶段"
		&"miao_shou_hui_chun":
			return "淘汰前响应"
		&"jin_chan_tuo_qiao", &"yi_hua_jie_mu":
			return "受他人卡牌影响时响应"
		_:
			return "按牌面时机使用"

func request_play_retained_event(player: PlayerClass, card: 事件牌) -> void:
	if not can_play_retained_event_now(card, player):
		if hud != null:
			hud._update_game_informs(get_retained_event_usage_hint(card, player))
		return
	var resolution_context := _begin_resolution_context(card)
	resolving = true
	_acquire_resolution_modal(
		resolution_context,
		&"retained_event",
		TurnManager.ModalResumePolicy.RESET_ACTION
			if TurnManager.now_phase == TurnManager.TurnPhase.ACTION
			else TurnManager.ModalResumePolicy.RESUME_REMAINING
	)
	await play_retained_event(player, card)
	if _is_resolution_context_cancelled(resolution_context):
		return
	resolving = false
	_release_resolution_modal(
		resolution_context,
		TurnManager.ModalResumePolicy.RESET_ACTION
			if TurnManager.now_phase == TurnManager.TurnPhase.ACTION
			else TurnManager.ModalResumePolicy.RESUME_REMAINING
	)
	_finish_resolution_context(resolution_context)
	interaction_finished.emit(player)

func _can_play_retained_now(card: 事件牌, player: PlayerClass = null) -> bool:
	if card.event_id == &"you_mu_cheng_huai":
		return TurnManager.now_phase == TurnManager.TurnPhase.ACTION and (player == null or not is_scenery_banned(player))
	if card.event_id == &"chang_xing_wu_zu":
		return TurnManager.now_phase == TurnManager.TurnPhase.MOVING
	return false

func play_retained_event(player: PlayerClass, card: 事件牌) -> void:
	var resolution_context := _current_resolution_context
	if not player.事件牌手牌.has(card) or not _can_play_retained_now(card, player):
		return
	ResourceManager.remove_event_card(player, card)
	ResourceManager.discard_event(card)
	retained_cards_changed.emit(player)
	if card.event_id == &"chang_xing_wu_zu":
		_player_status(player)[&"ignore_special_terrain_this_phase"] = {"remaining": 1, "applied_turn": TurnManager.now_turn}
		if player.map != null:
			player.map._clear_all_highlights()
			player.map._show_reachable_areas()
		if hud != null:
			hud._update_game_informs("【畅行无阻】已生效：本次移动到特殊地形无需精力。")
	elif card.event_id == &"you_mu_cheng_huai":
		await _play_you_mu_cheng_huai(player)
		if _is_resolution_context_cancelled(resolution_context):
			return

func trigger_arrival_event(player: PlayerClass, section: MapSection, arrival_id: int) -> void:
	if resolving or section == null or section.type != MapSection.SectionType.事件:
		return
	if arrival_id <= 0 or not player.has_current_action_arrival_at(section.location_index):
		return
	if arrival_id <= player.last_resolved_event_arrival_id:
		return
	player.last_resolved_event_arrival_id = arrival_id
	var card: 事件牌 = await ResourceManager.draw_event_card_with_profession(player)
	if card == null:
		if hud != null:
			hud._update_game_informs("事件牌已抽完。\n无事发生！")
		return
	await resolve_event(player, card)

func resolve_event(player: PlayerClass, card: 事件牌) -> void:
	if player == null or card == null or not card.is_available():
		return
	var resolution_context := _begin_resolution_context(card)
	resolving = true
	_skip_current_action_after_event = false
	_acquire_resolution_modal(
		resolution_context,
		&"event_resolution",
		TurnManager.ModalResumePolicy.RESET_ACTION
	)
	gameplay_event_triggered.emit(player, card)
	event_revealed.emit(player, card)
	if _is_resolution_context_cancelled(resolution_context):
		return
	var reveal_request := EventChoiceRequest.new(player, "确认后结算", [true], PackedStringArray(["结算"]), false, EventChoiceRequest.ChoiceKind.确认)
	await _request_choice(reveal_request)
	if _is_resolution_context_cancelled(resolution_context):
		return
	var effect_applied := false
	if card.retainable:
		ResourceManager.add_event_card(player, card)
		retained_cards_changed.emit(player)
		effect_applied = true
		if hud != null:
			await hud.wait_for_card_hand_animations()
			if _is_resolution_context_cancelled(resolution_context):
				return
		if _is_resolution_context_cancelled(resolution_context):
			return
		if hud != null:
			hud._update_game_informs("%s 获得事件牌【%s】。" % [player.player_name, card.card_name])
	else:
		if event_overlay != null:
			event_overlay.hide()
		if hud != null:
			hud.begin_event_presentation(card)
		var effect_state_before := _capture_effect_state()
		await _execute_event(player, card)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if hud != null:
			await hud.wait_for_card_hand_animations()
			if _is_resolution_context_cancelled(resolution_context):
				return
		effect_applied = effect_state_before != _capture_effect_state()
		if hud != null:
			await hud.finish_event_presentation("结算完成" if effect_applied else "无事发生！")
			if _is_resolution_context_cancelled(resolution_context):
				return
		ResourceManager.discard_event(card)
	var summary := "事件【%s】结算完成。" % card.card_name if effect_applied else "事件【%s】：无事发生！" % card.card_name
	event_finished.emit(player, card, summary)
	if _is_resolution_context_cancelled(resolution_context):
		return
	resolving = false
	var skip_current_action := _skip_current_action_after_event
	_skip_current_action_after_event = false
	_release_resolution_modal(
		resolution_context,
		TurnManager.ModalResumePolicy.NO_RESUME
			if skip_current_action
			else TurnManager.ModalResumePolicy.RESET_ACTION
	)
	_finish_resolution_context(resolution_context)
	interaction_finished.emit(player)
	if skip_current_action and TurnManager.GameOn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		TurnManager._emit_next_phase(TurnManager.TurnPhase.END)

func _capture_effect_state() -> Array:
	var state: Array = []
	for player: PlayerClass in TurnManager.players:
		state.append([
			player.get_instance_id(), player.current_energy, player.current_money, player.current_score,
			player.maxMove, player.now_pos, player.alive, player.is_working, player.player_types,
			ProfessionManager.get_blocked_turns(player),
			_card_instance_ids(player.非遗牌手牌),
			_card_instance_ids(player.食物牌手牌),
			_card_instance_ids(player.事件牌手牌),
			_player_status(player).duplicate(true),
		])
	state.append(_card_instance_ids(MarketManager.get_inventory()))
	state.append(_skip_current_action_after_event)
	return state

func _card_instance_ids(cards: Array) -> Array[int]:
	var result: Array[int] = []
	for card in cards:
		if card is Object:
			result.append((card as Object).get_instance_id())
	return result

func _execute_event(player: PlayerClass, card: 事件牌) -> void:
	match card.event_id:
		&"zuo_shou_yu_li": await _event_zuo_shou_yu_li(player)
		&"bai_ge_zheng_liu": await _event_bai_ge_zheng_liu(player)
		&"pou_duo_yi_gua": await _event_pou_duo_yi_gua(player)
		&"gu_zhu_yi_zhi": ProfessionManager.block_skill(player, 4)
		&"ba_geng_xie_ye": add_status(player, &"work_banned", 3, "罢耕歇业")
		&"yi_chuang_zeng_shou": _event_yi_chuang_zeng_shou(player)
		&"wen_hua_xin_feng": await _event_wen_hua_xin_feng(player)
		&"jiao_huan_ren_sheng": await _event_jiao_huan_ren_sheng(player)
		&"mei_mei_yu_gong": await _event_mei_mei_yu_gong(player)
		&"yang_jing_xu_rui": _event_yang_jing_xu_rui(player)
		&"cun_bu_nan_xing": await _event_cun_bu_nan_xing(player)
		&"jing_pi_li_jin": ResourceManager.modify_energy(player, -3, "事件：精疲力尽")
		&"bi_men_xie_ke": add_status(player, &"scenery_banned", 3, "闭门谢客")
		&"juan_yi_xiu_zheng": await _event_juan_yi_xiu_zheng(player)
		&"chen_jin_ti_yan": await _event_chen_jin_ti_yan(player)
		&"yi_wai_zhi_xi": _draw_food_cards(player, 2)
		&"xin_huo_xiang_chuan": await _event_xin_huo_xiang_chuan(player)
		&"you_shi_tong_xiang": await _event_you_shi_tong_xiang(player)
		&"chuan_yi_hu_jian": await _event_chuan_yi_hu_jian(player)
		&"yi_cang_hu_huan": await _event_yi_cang_hu_huan(player)
		&"tai_jiu_huan_xin": await _discard_cards_from_player(player, 2, "汰旧焕新")
		&"wen_hua_gong_xiang": await _event_wen_hua_gong_xiang(player)
		&"tong_tai_jing_ji": await _event_tong_tai_jing_ji(player)
		&"yi_shi_hui_you": await _event_yi_shi_hui_you(player)
		&"gu_di_chong_you": _event_gu_di_chong_you(player)
		&"dou_zhuan_xing_yi": await _event_dou_zhuan_xing_yi(player)
		&"ri_xing_qian_li": await _event_ri_xing_qian_li(player)
		&"yi_jing_xun_zong": await _event_yi_jing_xun_zong(player)
		&"tong_xing_feng_cai": await _event_tong_xing_feng_cai(player)
		&"guo_bao_hu_hang": _event_guo_bao_hu_hang()
		&"jin_ji_bi_xian": await _event_jin_ji_bi_xian(player)
		&"jian_wang_zhi_lai": await _event_jian_wang_zhi_lai(player)
		&"fu_di_chou_xin": await _event_fu_di_chou_xin(player)
		&"zhan_yi_gong_yan": await _event_zhan_yi_gong_yan(player)
		&"shi_ji_tao_zhen": await _event_shi_ji_tao_zhen(player)
		_:
			# 依赖牌不应进入牌库；若数据配置错误，明确报错而不是静默空结算。
			push_error("EventManager: 尚未实现或不应入库的事件效果 %s (%s)" % [card.card_name, card.event_id])

func _choose_player(requester: PlayerClass, prompt: String, candidates: Array[PlayerClass], optional: bool = false) -> PlayerClass:
	var resolution_context := _current_resolution_context
	if candidates.is_empty():
		return null
	var request := EventChoiceRequest.new(requester, prompt, candidates, _labels_for_players(candidates), optional, EventChoiceRequest.ChoiceKind.玩家)
	request.presentation = EventChoiceRequest.Presentation.地图
	_apply_choice_source(request, resolution_context)
	var selected := await _request_choice(request) as PlayerClass
	return null if _is_resolution_context_cancelled(resolution_context) else selected


func _choose_players(
	requester: PlayerClass,
	prompt: String,
	candidates: Array[PlayerClass],
	selection_count: int
) -> Array[PlayerClass]:
	var resolution_context := _current_resolution_context
	var required_count := mini(maxi(selection_count, 0), candidates.size())
	if required_count <= 0:
		return []
	var options: Array = []
	options.assign(candidates)
	var request := EventChoiceRequest.new(requester, prompt, options, _labels_for_players(candidates), false, EventChoiceRequest.ChoiceKind.玩家)
	request.presentation = EventChoiceRequest.Presentation.地图
	request.multiple = true
	request.min_selections = required_count
	request.max_selections = required_count
	_apply_choice_source(request, resolution_context)
	var chosen = await _request_choice(request)
	if _is_resolution_context_cancelled(resolution_context) or not chosen is Array:
		return []
	var selected: Array[PlayerClass] = []
	for option in chosen:
		if option is PlayerClass and candidates.has(option) and not selected.has(option):
			selected.append(option as PlayerClass)
	return selected

func _choose_card(requester: PlayerClass, prompt: String, cards: Array, optional: bool = false):
	var resolution_context := _current_resolution_context
	if cards.is_empty():
		return null
	var request := EventChoiceRequest.new(requester, prompt, cards, _labels_for_cards(cards), optional, EventChoiceRequest.ChoiceKind.卡牌)
	var selected = await _request_choice(request)
	return null if _is_resolution_context_cancelled(resolution_context) else selected

func _choose_section(requester: PlayerClass, prompt: String, sections: Array[MapSection], optional: bool = false) -> MapSection:
	var resolution_context := _current_resolution_context
	if sections.is_empty():
		return null
	var labels := PackedStringArray()
	for section: MapSection in sections:
		labels.append(section.section_name if not section.section_name.is_empty() else "格子 %d" % section.logical_index)
	var request := EventChoiceRequest.new(requester, prompt, sections, labels, optional, EventChoiceRequest.ChoiceKind.格子)
	request.presentation = EventChoiceRequest.Presentation.地图
	_apply_choice_source(request, resolution_context)
	var selected := await _request_choice(request) as MapSection
	return null if _is_resolution_context_cancelled(resolution_context) else selected

func _choose_market_card(requester: PlayerClass, prompt: String, cards: Array[非遗牌]) -> 非遗牌:
	var resolution_context := _current_resolution_context
	if cards.is_empty():
		return null
	var options: Array = []
	options.assign(cards)
	var request := EventChoiceRequest.new(requester, prompt, options, _labels_for_cards(cards), false, EventChoiceRequest.ChoiceKind.卡牌)
	request.presentation = EventChoiceRequest.Presentation.研究所
	_apply_choice_source(request, resolution_context)
	var selected := await _request_choice(request) as 非遗牌
	return null if _is_resolution_context_cancelled(resolution_context) else selected

func _apply_choice_source(request: EventChoiceRequest, resolution_context: EventResolutionContext) -> void:
	if request == null or resolution_context == null or resolution_context.source_card == null:
		return
	request.source_name = resolution_context.source_card.card_name
	request.source_description = resolution_context.source_card.description

func _choose_option(requester: PlayerClass, prompt: String, options: Array, labels: PackedStringArray, optional: bool = false):
	var resolution_context := _current_resolution_context
	if options.is_empty():
		return null
	var request := EventChoiceRequest.new(requester, prompt, options, labels, optional, EventChoiceRequest.ChoiceKind.选项)
	var selected = await _request_choice(request)
	return null if _is_resolution_context_cancelled(resolution_context) else selected


## 供食物等外部玩法复用本管理器唯一的 15 秒选择与响应链。
func request_external_player_choice(
	requester: PlayerClass,
	prompt: String,
	candidates: Array[PlayerClass],
	optional: bool = false
) -> PlayerClass:
	return await _choose_player(requester, prompt, candidates, optional)


func request_external_card_choice(requester: PlayerClass, prompt: String, cards: Array, optional: bool = false):
	return await _choose_card(requester, prompt, cards, optional)


func request_external_market_multi_choice(
	requester: PlayerClass,
	prompt: String,
	cards: Array[非遗牌],
	max_selections: int
) -> Array:
	if cards.is_empty() or max_selections <= 0:
		return []
	var options: Array = []
	options.assign(cards)
	var request := EventChoiceRequest.new(requester, prompt, options, _labels_for_cards(cards), true, EventChoiceRequest.ChoiceKind.卡牌)
	request.presentation = EventChoiceRequest.Presentation.研究所
	request.multiple = true
	request.max_selections = mini(max_selections, cards.size())
	var selected = await _request_choice(request)
	return selected if selected is Array else []


func resolve_external_food_target(
	effect_source: PlayerClass,
	target: PlayerClass,
	prompt: String,
	redirect_validator: Callable = Callable()
) -> PlayerClass:
	return await _resolve_effect_target(effect_source, target, &"food", prompt, true, redirect_validator)

func _next_alive(player: PlayerClass, direction: int = 1) -> PlayerClass:
	var players: Array[PlayerClass] = TurnManager.players
	var start := players.find(player)
	if start < 0:
		return null
	for offset in range(1, players.size() + 1):
		var index := posmod(start + direction * offset, players.size())
		if players[index].alive and players[index] != player:
			return players[index]
	return null

func _unique_sections(section_type: int = -1) -> Array[MapSection]:
	var result: Array[MapSection] = []
	var seen: Dictionary[int, bool] = {}
	if TurnManager.map == null:
		return result
	for value in TurnManager.map.grid_map.values():
		var section := value as MapSection
		if section == null or seen.has(section.get_instance_id()):
			continue
		seen[section.get_instance_id()] = true
		if section_type < 0 or section.type == section_type:
			result.append(section)
	return result

func _nearest_sections(player: PlayerClass, section_type: MapSection.SectionType) -> Array[MapSection]:
	var nearest: Array[MapSection] = []
	var best_distance := 1 << 30
	for section: MapSection in _unique_sections(section_type):
		var distance := _shortest_step_distance(player.now_pos, section.location_index)
		if distance < 0:
			continue
		if distance < best_distance:
			best_distance = distance
			nearest.assign([section])
		elif distance == best_distance:
			nearest.append(section)
	return nearest

func _teleport_player(player: PlayerClass, section: MapSection) -> bool:
	if player == null or section == null or player.map == null:
		return false
	var old_section: MapSection = player.map.grid_map.get(player.now_pos)
	player.map.vacate_player_section(player, old_section)
	player.now_pos = section.location_index
	player.map.occupy_player_section(player, section)
	player.position = player.map.to_local(section.global_position)
	if player.hud != null:
		player.hud._update_player_stats(player)
		if player.hud.event_presentation_director != null \
				and not player.hud.event_presentation_director.active_event_id.is_empty():
			player.hud.event_presentation_director.note_map_action(
				player,
				"%s → %s%d" % [player.player_name, MapSection.REGION.find_key(section.region), section.logical_index]
			)
		else:
			player.hud.update_camera_view(0.25)
	return true

func _swap_player_positions(first: PlayerClass, second: PlayerClass) -> void:
	if first == null or second == null or first.map == null:
		return
	var first_section: MapSection = first.map.grid_map.get(first.now_pos)
	var second_section: MapSection = second.map.grid_map.get(second.now_pos)
	if first_section == null or second_section == null:
		return
	var first_pos := first.now_pos
	first.map.vacate_player_section(first, first_section)
	first.map.vacate_player_section(second, second_section)
	first.now_pos = second.now_pos
	second.now_pos = first_pos
	first.map.occupy_player_section(first, second_section)
	first.map.occupy_player_section(second, first_section)
	first.position = first.map.to_local(second_section.global_position)
	second.position = second.map.to_local(first_section.global_position)
	if hud != null:
		hud._update_player_stats(first)
		hud._update_player_stats(second)
		# ALT 聚焦模式的相机目标取自当前玩家的位置；换位后需要立即重算。
		# 非聚焦模式下 update_camera_view() 会继续保持全图视角。
		if hud.event_presentation_director != null \
				and not hud.event_presentation_director.active_event_id.is_empty():
			hud.event_presentation_director.note_map_action(first, "%s 与 %s 互换位置" % [first.player_name, second.player_name])
		else:
			hud.update_camera_view(0.25)

func _non_national_feiyi(player: PlayerClass) -> Array[非遗牌]:
	var result: Array[非遗牌] = []
	for card: 非遗牌 in ResourceManager.get_effective_feiyi_cards(player):
		if card.category != 非遗牌.CardCategory.国家级非遗:
			result.append(card)
	return result

func _all_hand_cards(player: PlayerClass) -> Array:
	var result: Array = []
	result.append_array(player.非遗牌手牌)
	result.append_array(player.食物牌手牌)
	result.append_array(player.事件牌手牌)
	return result

func _discard_player_card(player: PlayerClass, card) -> void:
	if card is 食物牌 and player.食物牌手牌.has(card):
		ResourceManager.remove_food_card(player, card)
		ResourceManager.return_food_to_bottom(card)
	elif card is 非遗牌 and player.非遗牌手牌.has(card):
		ResourceManager.desert_feiyi(player, card)
	elif card is 事件牌 and player.事件牌手牌.has(card):
		ResourceManager.remove_event_card(player, card)
		ResourceManager.discard_event(card)
		retained_cards_changed.emit(player)

func _discard_cards_from_player(player: PlayerClass, count: int, reason: String) -> void:
	var resolution_context := _current_resolution_context
	var discard_count := mini(count, _all_hand_cards(player).size())
	for index in discard_count:
		var cards := _all_hand_cards(player)
		var selected = await _choose_card(player, "%s：选择弃牌（还需 %d 张）" % [reason, discard_count - index], cards)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if selected == null:
			break
		_discard_player_card(player, selected)

func _draw_food_cards(player: PlayerClass, count: int) -> int:
	var drawn := 0
	for _index in mini(count, ResourceManager.食物牌库.size()):
		var card := ResourceManager.draw_card(player, 卡牌基类.CardType.食物牌, MapSection.REGION.未知)
		if card != null:
			drawn += 1
	return drawn

func _apply_money(target: PlayerClass, amount: int, reason: String) -> void:
	var legal_amount := maxi(amount, -maxi(target.current_money, 0)) if amount < 0 else amount
	ResourceManager.modify_money(target, legal_amount, reason)

func _apply_energy(target: PlayerClass, amount: int, reason: String) -> void:
	ResourceManager.modify_energy(target, amount, reason)

func _apply_status(target: PlayerClass, status_id: StringName, phases: int, source_name: String = "事件效果") -> void:
	add_status(target, status_id, phases, source_name)

func _apply_swap_with_source(target: PlayerClass, source: PlayerClass) -> void:
	_swap_player_positions(source, target)

func _eligible_response_cards(target: PlayerClass, effect_kind: StringName) -> Array:
	var cards: Array = []
	if effect_kind not in [&"event", &"food", &"feiyi"]:
		return cards
	var has_redirect_target := _alive_players().size() > 1
	for event_card: 事件牌 in target.事件牌手牌:
		if event_card.event_id == &"jin_chan_tuo_qiao":
			cards.append(event_card)
		elif event_card.event_id == &"yi_hua_jie_mu" and has_redirect_target:
			cards.append(event_card)
	if effect_kind in [&"event", &"food"]:
		for feiyi: 非遗牌 in ResourceManager.get_effective_feiyi_cards(target):
			if feiyi.category == 非遗牌.CardCategory.神话传说:
				cards.append(feiyi)
	return cards

func _redirect_targets(target: PlayerClass, validator: Callable = Callable()) -> Array[PlayerClass]:
	var redirects: Array[PlayerClass] = []
	for candidate: PlayerClass in _alive_players():
		if candidate == target:
			continue
		if validator.is_valid() and not validator.call(candidate):
			continue
		redirects.append(candidate)
	return redirects

func _resolve_effect_target(
	effect_source: PlayerClass,
	target: PlayerClass,
	effect_kind: StringName,
	prompt: String,
	allow_reaction: bool = true,
	redirect_validator: Callable = Callable()
) -> PlayerClass:
	var resolution_context := _current_resolution_context
	if _is_resolution_context_cancelled(resolution_context):
		return null
	if target == null or not target.alive:
		return null
	var redirects := _redirect_targets(target, redirect_validator)
	var response_cards := _eligible_response_cards(target, effect_kind) if allow_reaction and effect_source != target else []
	if redirects.is_empty():
		for response_card in response_cards.duplicate():
			if response_card is 事件牌 and response_card.event_id == &"yi_hua_jie_mu":
				response_cards.erase(response_card)
	if not response_cards.is_empty():
		var request := EventChoiceRequest.new(
			target,
			"%s\n%s 是否使用响应牌？" % [prompt, target.player_name],
			response_cards,
			_labels_for_cards(response_cards),
			true,
			EventChoiceRequest.ChoiceKind.卡牌
		)
		var response = await _request_choice(request, true)
		if _is_resolution_context_cancelled(resolution_context):
			return null
		if response is 事件牌:
			var event_response := response as 事件牌
			ResourceManager.remove_event_card(target, event_response)
			ResourceManager.discard_event(event_response)
			retained_cards_changed.emit(target)
			if event_response.event_id == &"jin_chan_tuo_qiao":
				effect_response_resolved.emit(effect_kind, &"cancel", target, null)
				return null
			if event_response.event_id == &"yi_hua_jie_mu":
				var redirected := await _choose_player(target, "移花接木：选择新的合法目标", redirects)
				if _is_resolution_context_cancelled(resolution_context):
					return null
				if redirected == null:
					effect_response_resolved.emit(effect_kind, &"cancel", target, null)
					return null
				effect_response_resolved.emit(effect_kind, &"redirect", target, redirected)
				var resolved_target := await _resolve_effect_target(effect_source, redirected, effect_kind, prompt, true, redirect_validator)
				return null if _is_resolution_context_cancelled(resolution_context) else resolved_target
		elif response is 非遗牌:
			var myth := response as 非遗牌
			ResourceManager.desert_feiyi(target, myth)
			var modes: Array = [&"cancel"]
			var labels := PackedStringArray(["抵消"])
			if not redirects.is_empty():
				modes.append(&"redirect")
				labels.append("转移")
			var mode = await _choose_option(target, "选择响应效果", modes, labels)
			if _is_resolution_context_cancelled(resolution_context):
				return null
			if mode == &"redirect":
				var redirected := await _choose_player(target, "选择新的合法目标", redirects)
				if _is_resolution_context_cancelled(resolution_context):
					return null
				if redirected != null:
					effect_response_resolved.emit(effect_kind, &"redirect", target, redirected)
					var resolved_target := await _resolve_effect_target(effect_source, redirected, effect_kind, prompt, true, redirect_validator)
					return null if _is_resolution_context_cancelled(resolution_context) else resolved_target
			effect_response_resolved.emit(effect_kind, &"cancel", target, null)
			return null
	return target

func _resolve_incoming_effect(
	effect_source: PlayerClass,
	target: PlayerClass,
	effect_kind: StringName,
	prompt: String,
	apply_callable: Callable,
	allow_reaction: bool = true,
	redirect_validator: Callable = Callable()
) -> bool:
	var resolution_context := _current_resolution_context
	var presentation: EventPresentationDirector = hud.event_presentation_director if hud != null else null
	var uses_sequential_presentation := presentation != null \
			and not presentation.active_event_id.is_empty() \
			and presentation.get_tier(presentation.active_event_id) == EventPresentationDirector.Tier.SEQUENTIAL \
			and presentation.active_event_id != &"mei_mei_yu_gong"
	if uses_sequential_presentation:
		await presentation.focus_player(target, prompt)
		if _is_resolution_context_cancelled(resolution_context):
			return false
	var final_target := await _resolve_effect_target(effect_source, target, effect_kind, prompt, allow_reaction, redirect_validator)
	if _is_resolution_context_cancelled(resolution_context):
		return false
	if final_target == null:
		if uses_sequential_presentation:
			await presentation.show_status_applied(target, "效果已抵消")
		return false
	if uses_sequential_presentation and final_target != target:
		await presentation.focus_player(final_target, "效果转移至 %s" % final_target.player_name)
		if _is_resolution_context_cancelled(resolution_context):
			return false
	var money_before := final_target.current_money
	var energy_before := final_target.current_energy
	apply_callable.call(final_target)
	if uses_sequential_presentation:
		var energy_delta := final_target.current_energy - energy_before
		var money_delta := final_target.current_money - money_before
		if energy_delta != 0:
			await presentation.show_resource_delta(final_target, &"energy", energy_delta)
		elif money_delta != 0:
			await presentation.show_resource_delta(final_target, &"money", money_delta)
		else:
			await presentation.show_status_applied(final_target, prompt)
	return true

func _can_be_forced_to_work(player: PlayerClass) -> bool:
	return player != null \
		and player.alive \
		and not is_work_banned(player) \
		and player.current_energy >= ProfessionManager.get_work_energy_cost(player) \
		and not _nearest_sections(player, MapSection.SectionType.打工).is_empty()

func _event_zuo_shou_yu_li(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var candidates: Array[PlayerClass] = []
	for player: PlayerClass in _alive_players():
		if _can_be_forced_to_work(player):
			candidates.append(player)
	var selected: Array[PlayerClass] = await _choose_players(source, "坐收渔利：选择两名打工者", candidates, 2)
	if _is_resolution_context_cancelled(resolution_context):
		return
	for worker: PlayerClass in selected:
		var final_worker := await _resolve_effect_target(source, worker, &"event", "坐收渔利：前往打工并结算工资", true, _can_be_forced_to_work)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if final_worker == null:
			continue
		var nearest := _nearest_sections(final_worker, MapSection.SectionType.打工)
		var work_section := await _choose_section(final_worker, "选择最近的打工点", nearest) if nearest.size() > 1 else (nearest[0] if not nearest.is_empty() else null)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if work_section == null:
			continue
		if hud != null and hud.event_presentation_director != null:
			await hud.event_presentation_director.focus_player(final_worker, "%s 前往打工" % final_worker.player_name)
			if _is_resolution_context_cancelled(resolution_context):
				return
		_teleport_player(final_worker, work_section)
		var energy_before := final_worker.current_energy
		var work_energy_cost: int = ProfessionManager.get_work_energy_cost(final_worker)
		if work_energy_cost > 0:
			ResourceManager.modify_energy(final_worker, -work_energy_cost, "事件：坐收渔利打工消耗")
		if hud != null and hud.event_presentation_director != null and final_worker.current_energy != energy_before:
			await hud.event_presentation_director.show_resource_delta(final_worker, &"energy", final_worker.current_energy - energy_before)
		var salary: int = FoodManager.adjust_work_income(final_worker, 250)
		if final_worker == source:
			_apply_money(final_worker, salary, "事件：坐收渔利工资")
			if hud != null and hud.event_presentation_director != null:
				await hud.event_presentation_director.show_resource_delta(final_worker, &"money", salary)
		else:
			var worker_share: int = salary / 2
			_apply_money(final_worker, worker_share, "事件：坐收渔利工资分成")
			_apply_money(source, salary - worker_share, "事件：坐收渔利工资分成")
			if hud != null and hud.event_presentation_director != null:
				await hud.event_presentation_director.show_resource_delta(final_worker, &"money", worker_share)
				await hud.event_presentation_director.focus_player(source, "%s 分得工资" % source.player_name)
				await hud.event_presentation_director.show_resource_delta(source, &"money", salary - worker_share)

func _event_bai_ge_zheng_liu(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var opponent := _next_alive(source, -1)
	if opponent == null:
		return
	var source_rolls: Array[int] = []
	var opponent_rolls: Array[int] = []
	source_rolls.append(await _roll_2d6_presented(source))
	opponent_rolls.append(await _roll_2d6_presented(opponent))
	var source_team: Array[PlayerClass] = [source]
	var opponent_team: Array[PlayerClass] = [opponent]
	for player: PlayerClass in _alive_players():
		if player in [source, opponent]:
			continue
		var team = await _choose_option(player, "百舸争流：%s 首骰 %d，%s 首骰 %d，请选择队伍" % [source.player_name, source_rolls[0], opponent.player_name, opponent_rolls[0]], [source, opponent], PackedStringArray([source.player_name, opponent.player_name]))
		if _is_resolution_context_cancelled(resolution_context):
			return
		if team == source:
			source_team.append(player)
		else:
			opponent_team.append(player)
	for _index in 2:
		source_rolls.append(await _roll_2d6_presented(source))
		opponent_rolls.append(await _roll_2d6_presented(opponent))
	var source_total: int = 0
	var opponent_total: int = 0
	for value: int in source_rolls:
		source_total += value
	for value: int in opponent_rolls:
		opponent_total += value
	if source_total == opponent_total:
		await _show_bai_ge_result(source, source_rolls, opponent, opponent_rolls, "平局，双方均无奖惩")
		if _is_resolution_context_cancelled(resolution_context):
			return
		if hud != null:
			hud._update_game_informs("百舸争流平局，双方均无奖惩。")
		return
	var winners := source_team if source_total > opponent_total else opponent_team
	var losers := opponent_team if source_total > opponent_total else source_team
	var winning_captain := source if source_total > opponent_total else opponent
	await _show_bai_ge_result(source, source_rolls, opponent, opponent_rolls, "%s 方获胜" % winning_captain.player_name)
	if _is_resolution_context_cancelled(resolution_context):
		return
	for winner: PlayerClass in winners:
		await _resolve_incoming_effect(source, winner, &"event", "百舸争流获胜奖励", _apply_money.bind(200, "事件：百舸争流获胜"))
		if _is_resolution_context_cancelled(resolution_context):
			return
	for loser: PlayerClass in losers:
		await _resolve_incoming_effect(source, loser, &"event", "百舸争流失败惩罚", _apply_money.bind(-200, "事件：百舸争流失败"))
		if _is_resolution_context_cancelled(resolution_context):
			return

func _show_bai_ge_result(
	source: PlayerClass,
	source_rolls: Array[int],
	opponent: PlayerClass,
	opponent_rolls: Array[int],
	result_text: String
) -> void:
	var resolution_context := _current_resolution_context
	var source_total := _sum_rolls(source_rolls)
	var opponent_total := _sum_rolls(opponent_rolls)
	var prompt := "%s：%s，共 %d 点\n%s：%s，共 %d 点\n结果：%s" % [
		source.player_name, _format_rolls(source_rolls), source_total,
		opponent.player_name, _format_rolls(opponent_rolls), opponent_total,
		result_text,
	]
	if hud != null and hud.event_presentation_director != null:
		await hud.event_presentation_director.show_status_applied(source, prompt)
	else:
		await _choose_option(source, prompt, [true], PackedStringArray(["结算"]))
	if _is_resolution_context_cancelled(resolution_context):
		return

func _sum_rolls(rolls: Array[int]) -> int:
	var total := 0
	for value: int in rolls:
		total += value
	return total

func _format_rolls(rolls: Array[int]) -> String:
	var labels := PackedStringArray()
	for value: int in rolls:
		labels.append(str(value))
	return " / ".join(labels)

func _event_pou_duo_yi_gua(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var players := _alive_players()
	if players.is_empty():
		return
	var highest := players[0].current_money
	var lowest := players[0].current_money
	for player: PlayerClass in players:
		highest = maxi(highest, player.current_money)
		lowest = mini(lowest, player.current_money)
	for player: PlayerClass in players:
		if player.current_money == highest:
			await _resolve_incoming_effect(source, player, &"event", "裒多益寡：积分点最多者失去500积分点", _apply_money.bind(-500, "事件：裒多益寡"))
			if _is_resolution_context_cancelled(resolution_context):
				return
	for player: PlayerClass in players:
		if player.current_money == lowest:
			await _resolve_incoming_effect(source, player, &"event", "裒多益寡：积分点最少者获得500积分点", _apply_money.bind(500, "事件：裒多益寡"))
			if _is_resolution_context_cancelled(resolution_context):
				return

func _event_yi_chuang_zeng_shou(player: PlayerClass) -> void:
	if player.player_types in [PlayerClass.PlayerCharacter.魔术博主, PlayerClass.PlayerCharacter.旅行博主, PlayerClass.PlayerCharacter.商业博主]:
		ResourceManager.modify_money(player, 300, "事件：艺创增收")
	else:
		ResourceManager.modify_energy(player, 2, "事件：艺创增收")

func _event_wen_hua_xin_feng(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var players := _alive_players()
	var maximum := 0
	var effective_cards_by_player: Dictionary[PlayerClass, Array] = {}
	for player: PlayerClass in players:
		var effective_cards: Array[非遗牌] = ResourceManager.get_effective_feiyi_cards(player)
		effective_cards_by_player[player] = effective_cards
		maximum = maxi(maximum, effective_cards.size())
	for player: PlayerClass in players:
		var effective_cards: Array = effective_cards_by_player.get(player, [])
		if effective_cards.size() == maximum:
			await _resolve_incoming_effect(source, player, &"event", "文化新风：非遗牌数量最多奖励", _apply_money.bind(100, "事件：文化新风"))
			if _is_resolution_context_cancelled(resolution_context):
				return
		var has_national := false
		for card: 非遗牌 in effective_cards:
			if card.category == 非遗牌.CardCategory.国家级非遗:
				has_national = true
				break
		if has_national:
			await _resolve_incoming_effect(source, player, &"event", "文化新风：国家级非遗奖励", _apply_money.bind(100, "事件：文化新风"))
			if _is_resolution_context_cancelled(resolution_context):
				return

func _event_jiao_huan_ren_sheng(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var target := _next_alive(source)
	if target == null:
		return
	await _resolve_incoming_effect(
		source, target, &"event", "交换人生：与事件触发者永久交换职业",
		_apply_swap_job.bind(source), true,
		func(candidate: PlayerClass) -> bool: return candidate != source
	)
	if _is_resolution_context_cancelled(resolution_context):
		return

func _apply_swap_job(target: PlayerClass, source: PlayerClass) -> void:
	ProfessionManager.swap_professions(source, target)

func _event_mei_mei_yu_gong(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	for player: PlayerClass in _alive_players_from(source):
		if hud != null and hud.event_presentation_director != null:
			await hud.event_presentation_director.focus_player(player, "%s 准备投骰" % player.player_name)
			if _is_resolution_context_cancelled(resolution_context):
				return
		var amount := _roll_d6()
		if hud != null and hud.event_presentation_director != null:
			await hud.event_presentation_director.show_dice(player, [amount])
			if _is_resolution_context_cancelled(resolution_context):
				return
		var final_target := await _resolve_effect_target(source, player, &"event", "美美与共：获得%d点精力" % amount, true)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if final_target == null:
			if hud != null and hud.event_presentation_director != null:
				await hud.event_presentation_director.show_status_applied(player, "效果已抵消")
			continue
		if final_target != player and hud != null and hud.event_presentation_director != null:
			await hud.event_presentation_director.focus_player(final_target, "效果转移至 %s" % final_target.player_name)
			if _is_resolution_context_cancelled(resolution_context):
				return
		var energy_before := final_target.current_energy
		_apply_energy(final_target, amount, "事件：美美与共")
		var actual_delta := final_target.current_energy - energy_before
		if hud != null and hud.event_presentation_director != null:
			await hud.event_presentation_director.show_resource_delta(final_target, &"energy", actual_delta)
			if _is_resolution_context_cancelled(resolution_context):
				return

func _alive_players_from(source: PlayerClass) -> Array[PlayerClass]:
	var result: Array[PlayerClass] = []
	var players: Array[PlayerClass] = TurnManager.players
	var start := players.find(source)
	if start < 0:
		return _alive_players()
	for offset: int in players.size():
		var candidate: PlayerClass = players[posmod(start + offset, players.size())]
		if candidate.alive:
			result.append(candidate)
	return result

func _event_yang_jing_xu_rui(player: PlayerClass) -> void:
	ResourceManager.modify_energy(player, player.current_energy, "事件：养精蓄锐")
	add_status(player, &"skip_moving", 2, "养精蓄锐")
	add_status(player, &"skip_action", 2, "养精蓄锐")

func _event_cun_bu_nan_xing(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var target := await _choose_player(source, "寸步难行：选择跳过两个移动阶段的玩家", _alive_players())
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target != null:
		await _resolve_incoming_effect(source, target, &"event", "寸步难行：跳过接下来两个移动阶段", _apply_status.bind(&"skip_moving", 2, "寸步难行"))
		if _is_resolution_context_cancelled(resolution_context):
			return

func _event_juan_yi_xiu_zheng(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var accept = await _choose_option(player, "是否跳过本回合行动阶段并恢复3点精力？", [true], PackedStringArray(["接受休整"]), true)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if accept != true:
		return
	ResourceManager.modify_energy(player, 3, "事件：倦艺休整")
	if not player.食物牌手牌.is_empty():
		var food = await _choose_card(player, "可弃1张食物牌，额外恢复2点精力", player.食物牌手牌, true)
		if _is_resolution_context_cancelled(resolution_context):
			return
		if food is 食物牌:
			_discard_player_card(player, food)
			ResourceManager.modify_energy(player, 2, "事件：倦艺休整弃食物")
	_skip_current_action_after_event = true

func _event_chen_jin_ti_yan(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	if is_scenery_banned(player):
		return
	var nearest := _nearest_sections(player, MapSection.SectionType.风景)
	var target := await _choose_section(player, "选择一处等距最近的风景打卡点", nearest) if nearest.size() > 1 else (nearest[0] if not nearest.is_empty() else null)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	if not _teleport_player(player, target):
		return
	_record_scenery_check_in(player, target)
	ProfessionManager.record_scenery_arrival(player, target, &"chen_jin_ti_yan")
	ResourceManager.modify_energy(player, 6, "事件：沉浸体验双倍打卡")
	add_status(player, &"skip_moving", 2, "沉浸体验")

func _event_xin_huo_xiang_chuan(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var cards := _non_national_feiyi(source)
	if cards.is_empty():
		return
	var targets := _alive_players()
	targets.erase(source)
	var target := await _choose_player(source, "薪火相传：选择受赠玩家", targets)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var card = await _choose_card(source, "选择要赠出的非国家级非遗牌", cards)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if card == null:
		return
	var applied := await _resolve_incoming_effect(
		source, target, &"event", "薪火相传：接受非遗牌【%s】" % card.card_name,
		_apply_receive_feiyi.bind(source, card), true,
		func(candidate: PlayerClass) -> bool: return candidate != source
	)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if applied:
		ResourceManager.modify_energy(source, 3, "事件：薪火相传")

func _apply_receive_feiyi(target: PlayerClass, source: PlayerClass, card: 非遗牌) -> void:
	ResourceManager.transfer_feiyi_card(source, target, card)

func _event_you_shi_tong_xiang(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	for player: PlayerClass in _alive_players():
		if ResourceManager.食物牌库.is_empty():
			break
		await _resolve_incoming_effect(source, player, &"event", "有食同享：获得1张食物牌", _apply_draw_one_food)
		if _is_resolution_context_cancelled(resolution_context):
			return

func _apply_draw_one_food(target: PlayerClass) -> void:
	_draw_food_cards(target, 1)

func _event_chuan_yi_hu_jian(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var targets: Array[PlayerClass] = []
	for player: PlayerClass in _alive_players():
		if player != source and not _non_national_feiyi(player).is_empty():
			targets.append(player)
	var target := await _choose_player(source, "传艺互鉴：选择被抽牌的玩家", targets)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var final_target := await _resolve_effect_target(
		source,
		target,
		&"event",
		"传艺互鉴：随机失去1张非国家级非遗牌",
		true,
		func(candidate: PlayerClass) -> bool: return not _non_national_feiyi(candidate).is_empty()
	)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if final_target == null:
		return
	var card: 非遗牌 = GameManager.pick_from(_non_national_feiyi(final_target)) as 非遗牌
	_apply_steal_feiyi(final_target, source, card)

func _apply_steal_feiyi(target: PlayerClass, receiver: PlayerClass, card: 非遗牌) -> void:
	ResourceManager.transfer_feiyi_card(target, receiver, card)

func _event_yi_cang_hu_huan(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var targets: Array[PlayerClass] = []
	for player: PlayerClass in _alive_players():
		if player != source and not _non_national_feiyi(player).is_empty():
			targets.append(player)
	if _non_national_feiyi(source).is_empty():
		return
	var target := await _choose_player(source, "艺藏互换：选择交换对象", targets)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var accepted = await _choose_option(target, "%s 邀请交换非遗牌" % source.player_name, [true], PackedStringArray(["接受"]), true)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if accepted != true:
		return
	var source_card = await _choose_card(source, "选择要交换的非国家级非遗牌", _non_national_feiyi(source))
	if _is_resolution_context_cancelled(resolution_context):
		return
	var target_card = await _choose_card(target, "选择要交换的非国家级非遗牌", _non_national_feiyi(target))
	if _is_resolution_context_cancelled(resolution_context):
		return
	if source_card == null or target_card == null:
		return
	if not ResourceManager.swap_feiyi_cards(source, source_card, target, target_card):
		return
	ResourceManager.modify_energy(source, 1, "事件：艺藏互换")
	ResourceManager.modify_energy(target, 1, "事件：艺藏互换")

func _event_wen_hua_gong_xiang(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var targets: Array[PlayerClass] = []
	for player: PlayerClass in _alive_players():
		if not _all_hand_cards(player).is_empty():
			targets.append(player)
	var target := await _choose_player(source, "文化共享：选择弃牌玩家", targets)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var final_target := await _resolve_effect_target(
		source,
		target,
		&"event",
		"文化共享：弃掉最多两张手牌",
		true,
		func(candidate: PlayerClass) -> bool: return not _all_hand_cards(candidate).is_empty()
	)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if final_target != null:
		await _discard_cards_from_player(final_target, 2, "文化共享")
		if _is_resolution_context_cancelled(resolution_context):
			return

func _event_tong_tai_jing_ji(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var target := _next_alive(source)
	if target == null:
		return
	var source_cards := _non_national_feiyi(source)
	var target_cards := _non_national_feiyi(target)
	if source_cards.is_empty() or target_cards.is_empty():
		return
	var source_card: 非遗牌 = GameManager.pick_from(source_cards) as 非遗牌
	var target_card: 非遗牌 = GameManager.pick_from(target_cards) as 非遗牌
	var result_text := "%s：%d级　%s：%d级" % [
		source.player_name, source_card.rarity, target.player_name, target_card.rarity,
	]
	if source_card.rarity > target_card.rarity:
		result_text += "\n%s 获胜" % source.player_name
		await _show_tong_tai_result(source, source_card, target, target_card, result_text)
		if _is_resolution_context_cancelled(resolution_context):
			return
		_apply_money(source, 100, "事件：同台竞技")
		await _resolve_incoming_effect(source, target, &"event", "同台竞技：失去100积分点", _apply_money.bind(-100, "事件：同台竞技"))
		if _is_resolution_context_cancelled(resolution_context):
			return
	elif source_card.rarity < target_card.rarity:
		result_text += "\n%s 获胜" % target.player_name
		await _show_tong_tai_result(source, source_card, target, target_card, result_text)
		if _is_resolution_context_cancelled(resolution_context):
			return
		_apply_money(source, -100, "事件：同台竞技")
		await _resolve_incoming_effect(source, target, &"event", "同台竞技：获得100积分点", _apply_money.bind(100, "事件：同台竞技"))
		if _is_resolution_context_cancelled(resolution_context):
			return
	else:
		result_text += "\n同级，双方各得50积分点"
		await _show_tong_tai_result(source, source_card, target, target_card, result_text)
		if _is_resolution_context_cancelled(resolution_context):
			return
		_apply_money(source, 50, "事件：同台竞技平局")
		await _resolve_incoming_effect(source, target, &"event", "同台竞技：获得50积分点", _apply_money.bind(50, "事件：同台竞技平局"))
		if _is_resolution_context_cancelled(resolution_context):
			return

func _show_tong_tai_result(
	source: PlayerClass,
	source_card: 非遗牌,
	target: PlayerClass,
	target_card: 非遗牌,
	result_text: String
) -> void:
	if hud != null and hud.event_presentation_director != null:
		await hud.event_presentation_director.show_card_duel(source, source_card, target, target_card, result_text)
	else:
		await _choose_option(source, result_text, [true], PackedStringArray(["结算"]), false)

func _event_yi_shi_hui_you(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var target := _next_alive(source)
	if target == null:
		return
	await _resolve_incoming_effect(
		source, target, &"event", "以食会友：交换双方全部食物牌",
		_apply_swap_food.bind(source), true,
		func(candidate: PlayerClass) -> bool: return candidate != source
	)
	if _is_resolution_context_cancelled(resolution_context):
		return

func _apply_swap_food(target: PlayerClass, source: PlayerClass) -> void:
	ResourceManager.swap_food_hands(source, target)

func _event_gu_di_chong_you(player: PlayerClass) -> void:
	if player.last_successful_feiyi_section != null:
		_teleport_player(player, player.last_successful_feiyi_section)

func _event_dou_zhuan_xing_yi(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var target := _next_alive(source)
	if target != null:
		await _resolve_incoming_effect(
			source, target, &"event", "斗转星移：与事件触发者互换位置",
			_apply_swap_with_source.bind(source), true,
			func(candidate: PlayerClass) -> bool: return candidate != source
		)
		if _is_resolution_context_cancelled(resolution_context):
			return

func _event_ri_xing_qian_li(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var sections := _unique_sections()
	for occupied: MapSection in sections.duplicate():
		if occupied.is_occupied and occupied.location_index != player.now_pos:
			sections.erase(occupied)
	var target := await _choose_section(player, "日行千里：选择任意目标格", sections, true)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target != null:
		_teleport_player(player, target)

func _event_yi_jing_xun_zong(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var first := await _roll_2d6_presented(player)
	var second := await _roll_2d6_presented(player)
	var steps = await _choose_option(player, "艺径寻踪：选择移动点数", [first, second], PackedStringArray([str(first), str(second)]))
	if _is_resolution_context_cancelled(resolution_context):
		return
	if steps == null:
		return
	var sections := _sections_within_steps(player, mini(int(steps), player.current_energy))
	var target := await _choose_section(player, "艺径寻踪：选择移动终点", sections)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var distance := _shortest_step_distance(player.now_pos, target.location_index)
	ResourceManager.modify_energy(player, -distance, "事件：艺径寻踪移动")
	if not _teleport_player(player, target):
		return
	if target.type == MapSection.SectionType.非遗 and ResourceManager.has_feiyi_in_region(target.region):
		var card: 非遗牌 = await ResourceManager.get_feiyi_with_profession(player, target, 0)
		if card != null:
			ResourceManager.calculate_victory_score(player)

func _sections_within_steps(player: PlayerClass, max_steps: int) -> Array[MapSection]:
	var result: Array[MapSection] = []
	for section: MapSection in _unique_sections():
		if section.location_index == player.now_pos:
			continue
		if section.is_occupied:
			continue
		var distance := _shortest_step_distance(player.now_pos, section.location_index)
		if distance >= 0 and distance <= max_steps:
			result.append(section)
	return result

func _shortest_step_distance(start: Vector3i, target: Vector3i) -> int:
	if start == target:
		return 0
	var queue: Array[Vector3i] = [start]
	var distance: Dictionary[Vector3i, int] = {start: 0}
	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for direction: Vector3i in 常量.MOVE:
			var next: Vector3i = current + direction
			if not TurnManager.map.grid_map.has(next) or distance.has(next):
				continue
			distance[next] = distance[current] + 1
			if next == target:
				return distance[next]
			queue.append(next)
	return -1

func _event_tong_xing_feng_cai(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var targets := _alive_players()
	targets.erase(source)
	var target := await _choose_player(source, "同行风采：选择互换位置的玩家", targets)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target != null:
		await _resolve_incoming_effect(
			source, target, &"event", "同行风采：与事件触发者互换位置",
			_apply_swap_with_source.bind(source), true,
			func(candidate: PlayerClass) -> bool: return candidate != source
		)
		if _is_resolution_context_cancelled(resolution_context):
			return

func _event_guo_bao_hu_hang() -> void:
	for player: PlayerClass in _alive_players():
		for card: 非遗牌 in ResourceManager.get_effective_feiyi_cards(player):
			if card.category == 非遗牌.CardCategory.国家级非遗:
				add_status(player, &"free_move_phases", 2, "国宝护航")
				break

func _event_jin_ji_bi_xian(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var cards := _all_hand_cards(player)
	if cards.is_empty():
		return
	var selected = await _choose_card(player, "紧急避险：必须弃1张手牌以获得本回合损失免疫", cards)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if selected == null:
		return
	_discard_player_card(player, selected)
	_player_status(player)[&"loss_immunity"] = {"turn": TurnManager.now_turn}

func _event_jian_wang_zhi_lai(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var candidates: Array[非遗牌] = MarketManager.sample_cards(3)
	if candidates.is_empty():
		return
	var selected := await _choose_market_card(player, "免费选择1张", candidates)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if selected != null:
		MarketManager.take_card_free(player, selected)

func _event_shi_ji_tao_zhen(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var candidates: Array[非遗牌] = MarketManager.get_inventory()
	if candidates.is_empty():
		return
	var selected := await _choose_market_card(player, "免费选择1张", candidates)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if selected != null:
		MarketManager.take_card_free(player, selected)

func _event_zhan_yi_gong_yan(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var cards := _non_national_feiyi(player)
	if cards.is_empty():
		return
	var highest_score := -1
	for card: 非遗牌 in cards:
		highest_score = maxi(highest_score, card.base_score)
	var highest_cards: Array[非遗牌] = []
	for card: 非遗牌 in cards:
		if card.base_score == highest_score:
			highest_cards.append(card)
	var selected: 非遗牌 = highest_cards[0] if highest_cards.size() == 1 else await _choose_card(
		player,
		"展艺共研：选择一张基础分最高的非国家级非遗牌",
		highest_cards
	) as 非遗牌
	if _is_resolution_context_cancelled(resolution_context):
		return
	if selected != null:
		ResourceManager.desert_feiyi(player, selected)

func _event_fu_di_chou_xin(source: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	var candidates: Array[PlayerClass] = []
	for player: PlayerClass in _alive_players():
		if not _non_national_feiyi(player).is_empty():
			candidates.append(player)
	var target := await _choose_player(source, "釜底抽薪：选择一名玩家", candidates)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	var final_target := await _resolve_effect_target(
		source,
		target,
		&"event",
		"釜底抽薪：随机将最多2张非国家级非遗牌放入全局研究所",
		true,
		func(candidate: PlayerClass) -> bool: return not _non_national_feiyi(candidate).is_empty()
	)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if final_target == null:
		return
	var cards := _non_national_feiyi(final_target)
	GameManager.shuffle_array(cards)
	for index: int in mini(2, cards.size()):
		ResourceManager.desert_feiyi(final_target, cards[index])

func _play_you_mu_cheng_huai(player: PlayerClass) -> void:
	var resolution_context := _current_resolution_context
	if is_scenery_banned(player):
		if hud != null:
			hud._update_game_informs("闭门谢客生效中，不能使用【游目骋怀】。")
		return
	var sections := _unique_sections(MapSection.SectionType.风景)
	var target := await _choose_section(player, "游目骋怀：选择任意风景打卡点", sections)
	if _is_resolution_context_cancelled(resolution_context):
		return
	if target == null:
		return
	if not _teleport_player(player, target):
		return
	_record_scenery_check_in(player, target)
	ProfessionManager.record_scenery_arrival(player, target, &"you_mu_cheng_huai")
	ResourceManager.modify_energy(player, 5, "事件：游目骋怀打卡及额外奖励")

func _record_scenery_check_in(player: PlayerClass, section: MapSection) -> bool:
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager == null:
		return false
	return bool(achievement_manager.call("record_scenery_check_in", player, section))

func _roll_2d6() -> int:
	return GameManager.randi_between(1, 6) + GameManager.randi_between(1, 6)

func _roll_d6() -> int:
	return GameManager.randi_between(1, 6)

func _roll_2d6_presented(player: PlayerClass) -> int:
	var values: Array[int] = [_roll_d6(), _roll_d6()]
	if hud != null and hud.event_presentation_director != null:
		await hud.event_presentation_director.focus_player(player, "%s 准备投骰" % player.player_name)
		await hud.event_presentation_director.show_dice(player, values)
	return values[0] + values[1]

func try_revive_player(dying_player: PlayerClass) -> bool:
	if dying_player == null or dying_player.current_energy > 0:
		return false
	var player_count: int = TurnManager.players.size()
	if player_count == 0:
		return false
	var resolution_context := _begin_resolution_context()
	var start_index: int = TurnManager.now_player_index
	var interaction_was_shown := false
	for offset in player_count:
		var holder: PlayerClass = TurnManager.players[(start_index + offset) % player_count]
		if not holder.alive and holder != dying_player:
			continue
		var revive_cards: Array[事件牌] = []
		for card: 事件牌 in holder.事件牌手牌:
			if card.event_id == &"miao_shou_hui_chun":
				revive_cards.append(card)
		if revive_cards.is_empty():
			continue
		begin_modal_if_needed()
		interaction_was_shown = true
		var decision = await _choose_option(holder, "%s 即将被淘汰，是否使用【妙手回春】？" % dying_player.player_name, [true], PackedStringArray(["使用并恢复3点精力"]), true)
		if _is_resolution_context_cancelled(resolution_context):
			return false
		if decision == true:
			var revive_card := revive_cards[0]
			ResourceManager.remove_event_card(holder, revive_card)
			ResourceManager.discard_event(revive_card)
			retained_cards_changed.emit(holder)
			if _is_resolution_context_cancelled(resolution_context):
				return false
			dying_player.alive = true
			ResourceManager.modify_energy(dying_player, 3, "事件：妙手回春")
			dying_player.show()
			if dying_player.map != null and dying_player.map.grid_map.has(dying_player.now_pos):
				dying_player.map.occupy_player_section(dying_player, dying_player.map.grid_map[dying_player.now_pos])
			end_modal_if_owned()
			_finish_resolution_context(resolution_context)
			interaction_finished.emit(holder)
			return true
	end_modal_if_owned()
	_finish_resolution_context(resolution_context)
	if interaction_was_shown:
		interaction_finished.emit(dying_player)
	return false

var _revive_modal_owned: bool = false
var _revive_modal_lease: int = -1

func begin_modal_if_needed() -> void:
	if not TurnManager.is_modal_resolution_active():
		_revive_modal_lease = TurnManager.acquire_modal(
			&"event_revive",
			TurnManager.ModalResumePolicy.NO_RESUME
		)
		_revive_modal_owned = true

func end_modal_if_owned() -> void:
	_release_revive_modal()


func _release_revive_modal() -> void:
	if _revive_modal_lease >= 0:
		TurnManager.release_modal(_revive_modal_lease, TurnManager.ModalResumePolicy.NO_RESUME)
	_revive_modal_lease = -1
	_revive_modal_owned = false
