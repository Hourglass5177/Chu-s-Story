extends GutTest

var _saved_game_on: bool
var _saved_phase: TurnManager.TurnPhase
var _saved_turn_epoch: int

func before_each() -> void:
	_saved_game_on = TurnManager.GameOn
	_saved_phase = TurnManager.now_phase
	_saved_turn_epoch = TurnManager.get_turn_epoch()
	InteractionCoordinator.reset_session()
	TurnManager.invalidate_all_modals(&"interaction_test_setup")
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION

func after_each() -> void:
	InteractionCoordinator.reset_session()
	TurnManager.invalidate_all_modals(&"interaction_test_cleanup")
	TurnManager.GameOn = _saved_game_on
	TurnManager.now_phase = _saved_phase
	TurnManager._turn_epoch = _saved_turn_epoch

func test_submit_finishes_exactly_once_and_rejects_stale_id() -> void:
	watch_signals(InteractionCoordinator)
	var ticket := InteractionCoordinator.begin_interaction(
		&"test", 15.0, func(_active: InteractionTicket): return null,
		TurnManager.ModalResumePolicy.NO_RESUME, false, {"held": "请求载荷"}
	)
	assert_not_null(ticket)
	assert_true(InteractionCoordinator.submit(ticket.interaction_id, "甲"))
	assert_false(InteractionCoordinator.submit(ticket.interaction_id, "乙"))
	assert_false(InteractionCoordinator.submit(ticket.interaction_id - 1, "旧请求"))
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.state, InteractionTicket.State.RESOLVED)
	assert_eq(result.value, "甲")
	assert_true(ticket.metadata.is_empty(), "唯一等待者消费结果后必须释放请求载荷")
	assert_false(ticket.timeout_resolver.is_valid(), "已完成票据不得继续持有超时闭包")
	assert_signal_emit_count(InteractionCoordinator, "interaction_finished", 1)
	assert_true(InteractionCoordinator.assert_quiescent("single submit"))

func test_concurrent_request_is_rejected_without_overwriting_active_ticket() -> void:
	var first := InteractionCoordinator.begin_interaction(&"first", 15.0)
	var rejected := InteractionCoordinator.begin_interaction(&"second", 15.0)
	assert_null(rejected)
	assert_push_error("尝试在")
	assert_eq(InteractionCoordinator.get_active_snapshot().interaction_id, first.interaction_id)
	assert_true(InteractionCoordinator.submit(first.interaction_id, true))

func test_optional_timeout_returns_null_and_forced_timeout_uses_stable_first() -> void:
	var optional_ticket := InteractionCoordinator.begin_interaction(
		&"optional", 15.0, func(_ticket: InteractionTicket): return null
	)
	assert_true(InteractionCoordinator.resolve_timeout(optional_ticket.interaction_id))
	var optional_result := await InteractionCoordinator.await_result(optional_ticket)
	assert_true(optional_result.timed_out)
	assert_null(optional_result.value)

	var ordered := ["第一项", "第二项"]
	var forced_ticket := InteractionCoordinator.begin_interaction(
		&"forced", 15.0, func(_ticket: InteractionTicket): return ordered[0]
	)
	assert_true(InteractionCoordinator.resolve_timeout(forced_ticket.interaction_id))
	var forced_result := await InteractionCoordinator.await_result(forced_ticket)
	assert_eq(forced_result.value, "第一项")

func test_forced_multi_timeout_keeps_preview_and_fills_minimum_in_order() -> void:
	var ordered := ["甲", "乙", "丙"]
	var resolver := func(ticket: InteractionTicket):
		var chosen: Array = ticket.preview.duplicate() if ticket.preview is Array else []
		for option in ordered:
			if chosen.size() >= 2:
				break
			if not chosen.has(option):
				chosen.append(option)
		return chosen
	var ticket := InteractionCoordinator.begin_interaction(&"forced_multi", 15.0, resolver)
	assert_true(InteractionCoordinator.update_preview(ticket.interaction_id, ["丙"]))
	InteractionCoordinator.resolve_timeout(ticket.interaction_id)
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.value, ["丙", "甲"])

func test_turn_epoch_change_cancels_old_request_without_touching_new_one() -> void:
	var ticket := InteractionCoordinator.begin_interaction(&"old_turn", 15.0)
	TurnManager._turn_epoch += 1
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.state, InteractionTicket.State.CANCELLED)
	assert_eq(result.cancel_reason, &"stale_context")
	assert_false(InteractionCoordinator.submit(ticket.interaction_id, true))
	var current := InteractionCoordinator.begin_interaction(&"new_turn", 15.0)
	assert_true(InteractionCoordinator.submit(current.interaction_id, true))
	assert_true((await InteractionCoordinator.await_result(current)).value)

func test_modal_leases_resume_only_after_last_valid_release() -> void:
	TurnManager.turn_timer.start(9.0)
	var root := TurnManager.acquire_modal(&"root", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	var nested := TurnManager.acquire_modal(&"nested", TurnManager.ModalResumePolicy.RESET_ACTION)
	assert_eq(TurnManager.get_modal_snapshot().depth, 2)
	assert_true(TurnManager.release_modal(root))
	assert_eq(TurnManager.get_modal_snapshot().depth, 1)
	assert_false(TurnManager.release_modal(root))
	assert_true(TurnManager.release_modal(nested))
	assert_eq(TurnManager.get_modal_snapshot().depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_lt(TurnManager.turn_timer.time_left, 10.0)

func test_session_reset_wakes_waiter_with_reason_and_clears_modal() -> void:
	var ticket := InteractionCoordinator.begin_interaction(
		&"session", 15.0, Callable(), TurnManager.ModalResumePolicy.NO_RESUME, true
	)
	InteractionCoordinator.reset_session()
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.state, InteractionTicket.State.CANCELLED)
	assert_eq(result.cancel_reason, &"session_reset")
	assert_eq(TurnManager.get_modal_snapshot().depth, 0)

func test_fifty_mixed_interactions_leave_no_ticket_or_modal_state() -> void:
	for index: int in 50:
		var policy := TurnManager.ModalResumePolicy.RESUME_REMAINING \
				if index % 2 == 0 else TurnManager.ModalResumePolicy.NO_RESUME
		var ticket := InteractionCoordinator.begin_interaction(
			&"mixed", 15.0, func(active: InteractionTicket): return active.preview,
			policy, true, {"index": index}
		)
		assert_not_null(ticket)
		if index % 3 == 0:
			assert_true(InteractionCoordinator.update_preview(ticket.interaction_id, [index]))
			assert_true(InteractionCoordinator.resolve_timeout(ticket.interaction_id))
		else:
			assert_true(InteractionCoordinator.submit(ticket.interaction_id, index))
		var result := await InteractionCoordinator.await_result(ticket)
		assert_eq(result.value, [index] if index % 3 == 0 else index)
		assert_true(InteractionCoordinator.assert_quiescent("mixed %d" % index))
		assert_eq(TurnManager.get_modal_snapshot().depth, 0)
