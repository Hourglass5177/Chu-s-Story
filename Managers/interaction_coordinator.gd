extends Node

signal interaction_started(ticket: InteractionTicket)
signal interaction_finished(ticket: InteractionTicket, result: InteractionResult)
signal interaction_cancelled(ticket: InteractionTicket, reason: StringName)

var decision_provider: Callable = Callable()
var _sequence: int = 0
var _active_ticket: InteractionTicket = null
var _active_result: InteractionResult = null
var _results_by_id: Dictionary[int, InteractionResult] = {}
var _timer: Timer = null

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_timeout)

func begin_interaction(
	owner: StringName,
	timeout_seconds: float,
	timeout_resolver: Callable = Callable(),
	modal_policy: int = TurnManager.ModalResumePolicy.NO_RESUME,
	acquire_modal: bool = false,
	metadata: Dictionary = {}
) -> InteractionTicket:
	if _active_ticket != null and _active_ticket.is_waiting():
		push_error("InteractionCoordinator: %s 尝试在 %s 仍等待时开启新交互。" % [owner, _active_ticket.owner])
		return null
	_sequence += 1
	_active_result = null
	_active_ticket = InteractionTicket.new(_sequence, owner, TurnManager.get_session_generation(), TurnManager.get_turn_epoch(), timeout_seconds, timeout_resolver, modal_policy, metadata)
	if acquire_modal:
		_active_ticket.modal_lease_id = TurnManager.acquire_modal(owner, modal_policy)
	interaction_started.emit(_active_ticket)
	if decision_provider.is_valid():
		var provided = decision_provider.call(_active_ticket)
		if provided is InteractionResult:
			_finish(_active_ticket, provided)
		else:
			submit(_active_ticket.interaction_id, provided)
	elif timeout_seconds > 0.0:
		_timer.start(timeout_seconds)
	return _active_ticket

func await_result(ticket: InteractionTicket) -> InteractionResult:
	if ticket == null:
		return InteractionResult.new(0, InteractionTicket.State.CANCELLED, null, false, &"rejected")
	while ticket.is_waiting():
		await get_tree().process_frame
		if not is_instance_valid(self):
			return InteractionResult.new(ticket.interaction_id, InteractionTicket.State.CANCELLED, null, false, &"coordinator_freed")
		if ticket.is_waiting() and not _ticket_context_is_current(ticket):
			_cancel_ticket_internal(ticket, &"stale_context")
	if _results_by_id.has(ticket.interaction_id):
		var completed: InteractionResult = _results_by_id[ticket.interaction_id]
		_results_by_id.erase(ticket.interaction_id)
		_release_ticket_payload(ticket)
		return completed
	_release_ticket_payload(ticket)
	return InteractionResult.new(ticket.interaction_id, ticket.state, null, ticket.state == InteractionTicket.State.TIMED_OUT, &"result_released")

func submit(interaction_id: int, value) -> bool:
	if not _owns_waiting(interaction_id):
		return false
	return _finish(_active_ticket, InteractionResult.new(interaction_id, InteractionTicket.State.RESOLVED, value))

func update_preview(interaction_id: int, value) -> bool:
	if not _owns_waiting(interaction_id):
		return false
	_active_ticket.preview = value
	return true

func cancel(interaction_id: int, reason: StringName = &"cancelled") -> bool:
	if not _owns_waiting(interaction_id):
		return false
	var ticket := _active_ticket
	var result := InteractionResult.new(interaction_id, InteractionTicket.State.CANCELLED, null, false, reason)
	interaction_cancelled.emit(ticket, reason)
	return _finish(ticket, result)

func cancel_all(reason: StringName = &"session_reset") -> void:
	if _active_ticket != null and _active_ticket.is_waiting():
		_cancel_ticket_internal(_active_ticket, reason)

func get_active_snapshot() -> Dictionary:
	if _active_ticket == null or not _active_ticket.is_waiting():
		return {}
	return {"interaction_id": _active_ticket.interaction_id, "owner": _active_ticket.owner, "session_generation": _active_ticket.session_generation, "turn_epoch": _active_ticket.turn_epoch, "time_left": get_time_left(_active_ticket.interaction_id), "modal_lease_id": _active_ticket.modal_lease_id}

func get_time_left(interaction_id: int = -1) -> float:
	if _active_ticket == null or not _active_ticket.is_waiting() or _timer == null:
		return 0.0
	if interaction_id >= 0 and interaction_id != _active_ticket.interaction_id:
		return 0.0
	return _timer.time_left

func resolve_timeout(interaction_id: int) -> bool:
	if not _owns_waiting(interaction_id):
		return false
	_on_timeout()
	return true

func assert_quiescent(context: String = "") -> bool:
	var quiet := _active_ticket == null or not _active_ticket.is_waiting()
	if not quiet and OS.is_debug_build():
		push_error("交互未清理%s：%s" % [("（%s）" % context) if not context.is_empty() else "", str(get_active_snapshot())])
	return quiet

func reset_session(clear_decision_provider: bool = true) -> void:
	var cancelled_id := -1
	var cancelled_result: InteractionResult = null
	if _active_ticket != null and _active_ticket.is_waiting():
		cancelled_id = _active_ticket.interaction_id
	cancel_all(&"session_reset")
	if cancelled_id >= 0:
		cancelled_result = _results_by_id.get(cancelled_id) as InteractionResult
	_results_by_id.clear()
	# 正在 await 的旧协程仍需收到本次取消原因；正常完成结果已由唯一等待者消费。
	if cancelled_result != null:
		_results_by_id[cancelled_id] = cancelled_result
	_release_ticket_payload(_active_ticket)
	if clear_decision_provider:
		decision_provider = Callable()
	_sequence += 1
	if _timer != null:
		_timer.stop()

func _owns_waiting(interaction_id: int) -> bool:
	return _active_ticket != null and _active_ticket.is_waiting() and _active_ticket.interaction_id == interaction_id and _ticket_context_is_current(_active_ticket)

func _ticket_context_is_current(ticket: InteractionTicket) -> bool:
	return ticket != null and ticket.session_generation == TurnManager.get_session_generation() and ticket.turn_epoch == TurnManager.get_turn_epoch()

func _cancel_ticket_internal(ticket: InteractionTicket, reason: StringName) -> bool:
	if ticket == null or ticket != _active_ticket or not ticket.is_waiting():
		return false
	var result := InteractionResult.new(ticket.interaction_id, InteractionTicket.State.CANCELLED, null, false, reason)
	interaction_cancelled.emit(ticket, reason)
	return _finish(ticket, result)

func _on_timeout() -> void:
	if _active_ticket == null or not _active_ticket.is_waiting():
		return
	var value = _active_ticket.preview
	if _active_ticket.timeout_resolver.is_valid():
		value = _active_ticket.timeout_resolver.call(_active_ticket)
	_finish(_active_ticket, InteractionResult.new(_active_ticket.interaction_id, InteractionTicket.State.TIMED_OUT, value, true))

func _finish(ticket: InteractionTicket, result: InteractionResult) -> bool:
	if ticket == null or result == null or ticket != _active_ticket or not ticket.is_waiting():
		return false
	if _timer != null:
		_timer.stop()
	ticket.state = result.state
	_active_result = result
	_results_by_id[ticket.interaction_id] = result
	if _results_by_id.size() > 32:
		var oldest_id: int = _results_by_id.keys().min()
		_results_by_id.erase(oldest_id)
	if ticket.modal_lease_id >= 0:
		TurnManager.release_modal(ticket.modal_lease_id)
	interaction_finished.emit(ticket, result)
	return true

func _release_ticket_payload(ticket: InteractionTicket) -> void:
	if ticket == null:
		return
	ticket.timeout_resolver = Callable()
	ticket.metadata.clear()
	ticket.preview = null
	if _active_ticket == ticket:
		_active_ticket = null
		_active_result = null
