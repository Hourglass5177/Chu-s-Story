extends GutTest

class DelayedScorer extends VocalScorer:
	func is_available() -> bool:
		return true

	func begin_capture(_id: StringName, _duration: float) -> Error:
		return OK

	func finish_capture_and_score() -> Error:
		return OK


func _scoring_task() -> HeritageTaskBase:
	var task := load("res://InheritanceTasks/Tasks/huangmei_xi.tscn").instantiate() as HeritageTaskBase
	add_child_autofree(task)
	var context := HeritageTaskRunContext.new(&"huangmei_xi")
	context.services[&"vocal_scorer"] = DelayedScorer.new()
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.call("_begin_recording")
	task.call("_finish_recording")
	return task


func test_scoring_does_not_spend_player_time() -> void:
	var task := _scoring_task()
	task.time_left = 0.2
	task.call("_process", 3.0)
	assert_eq(task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_almost_eq(task.time_left, 0.2, 0.001)
	assert_eq((task.get_node("%StageLabel") as Label).text, "正在本地评分")
	assert_eq(task.get_time_display(), "评分中")


func test_line_gate_is_not_overridden_by_an_acceptable_total() -> void:
	var task := _scoring_task()
	watch_signals(task)
	task.call("_on_scoring_completed", {"ok": true, "passed": false, "score": 72.5,
		"reason": &"line_threshold_not_met", "line_scores": [100.0, 45.0]})
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.FAILURE)
	assert_eq(result.reason, &"line_threshold_not_met")
	assert_eq(result.metrics.score, 72.5)


func test_scoring_result_received_while_paused_is_applied_on_resume() -> void:
	var task := _scoring_task()
	watch_signals(task)
	task.set_suspended(true)
	task.call("_on_scoring_completed", {"ok": true, "passed": true, "score": 80.0})
	assert_signal_not_emitted(task, "task_completed")
	task.set_suspended(false)
	assert_signal_emit_count(task, "task_completed", 1)
	assert_eq(task.run_state, HeritageTaskBase.RunState.FINISHED)
	task.call("_on_scoring_completed", {"ok": true, "score": 80.0})
	assert_signal_emit_count(task, "task_completed", 1)


func test_scoring_watchdog_is_technical_error_and_excludes_pause() -> void:
	var task := _scoring_task()
	watch_signals(task)
	task.set_suspended(true)
	task.call("_process", 100.0)
	assert_signal_not_emitted(task, "task_completed")
	task.set_suspended(false)
	task.call("_process", 61.0)
	assert_signal_emit_count(task, "task_completed", 1)
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.TECHNICAL_ERROR)
	assert_eq(result.reason, &"scoring_timeout")


func test_cancel_discards_result_buffered_during_pause() -> void:
	var task := _scoring_task()
	watch_signals(task)
	task.set_suspended(true)
	task.call("_on_scoring_completed", {"ok": true, "score": 80.0})
	task.cancel_external(&"session_reset")
	task.set_suspended(false)
	assert_signal_emit_count(task, "task_completed", 1)
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.CANCELLED)


func test_last_recording_frame_can_enter_scoring_at_zero() -> void:
	var task := _scoring_task()
	task.set("_stage", task.Stage.RECORDING)
	task.set("_stage_time", 13.64)
	task.time_left = 0.01
	task.call("_process", 0.02)
	assert_eq(task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_eq(task.get_time_display(), "评分中")
	task.call("_on_scoring_completed", {"ok": true, "score": 80.0})
	assert_eq(task.run_state, HeritageTaskBase.RunState.FINISHED)


func test_watchdog_does_not_depend_on_player_countdown() -> void:
	var task := _scoring_task()
	task.time_left = 1000.0
	watch_signals(task)
	task.call("_process", 59.0)
	assert_signal_not_emitted(task, "task_completed")
	task.call("_process", 1.1)
	assert_signal_emit_count(task, "task_completed", 1)
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.TECHNICAL_ERROR)
	assert_almost_eq(task.time_left, 1000.0, 0.001)


func test_host_exit_does_not_apply_a_buffered_success_first() -> void:
	var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	add_child_autofree(host)
	var context := HeritageTaskRunContext.new(&"huangmei_xi")
	context.practice_mode = true
	context.services[&"vocal_scorer"] = DelayedScorer.new()
	host.configure(load("res://InheritanceTasks/Definitions/huangmei_xi.tres"), context)
	host.begin()
	host.start_from_preparation()
	var task := host.active_task
	assert_eq(task.run_state, HeritageTaskBase.RunState.RUNNING)
	task.set_process(false)
	task.call("_begin_recording")
	task.call("_finish_recording")
	assert_eq(host.time_label.text, "评分中")
	host.call("_show_exit_confirm")
	watch_signals(host)
	task.call("_on_scoring_completed", {"ok": true, "score": 80.0})
	assert_signal_not_emitted(host, "task_finished", "评分结果在退出确认期间只缓存")
	host.call("_confirm_abort")
	var result: HeritageTaskResult = get_signal_parameters(host, "task_finished")[0]
	assert_eq(result.status, HeritageTaskResult.Status.MANUAL_ABORT)
	task.set_suspended(false)
	assert_signal_emit_count(host, "task_finished", 1, "退出后不能补发缓存成功")
	assert_signal_emit_count(host, "return_requested", 1)
