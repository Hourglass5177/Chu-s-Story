class_name HeritageTaskBase
extends Control

signal task_completed(result: HeritageTaskResult)
signal time_changed(time_left: float)
signal progress_changed(value: float)
signal feedback_requested(kind: StringName, position: Vector2)
signal manual_abort_requested

enum RunState {
	IDLE,
	RUNNING,
	SUSPENDED,
	FINISHED,
}

@export var task_id: StringName = &""
@export_range(10.0, 60.0, 0.5) var duration_seconds: float = 25.0

var context: HeritageTaskRunContext = null
var run_state: RunState = RunState.IDLE
var time_left: float = 0.0
var elapsed_seconds: float = 0.0
var progress: float = 0.0
var feedback_strength: float = 0.0

var _completion_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_unhandled_input(true)


func configure(p_context: HeritageTaskRunContext) -> void:
	context = p_context.duplicate_snapshot() if p_context != null else HeritageTaskRunContext.new(task_id)
	if task_id.is_empty():
		task_id = context.task_id
	elif context.task_id.is_empty():
		context.task_id = task_id
	context.reset_rng()
	reset_task_state()


func reset_task_state() -> void:
	run_state = RunState.IDLE
	time_left = duration_seconds
	elapsed_seconds = 0.0
	progress = 0.0
	feedback_strength = 0.0
	_completion_emitted = false
	queue_redraw()


func start_task() -> void:
	if run_state != RunState.IDLE or _completion_emitted:
		return
	if context == null:
		_complete(HeritageTaskResult.technical_error(task_id, &"missing_context", "任务数据未就绪"))
		return
	run_state = RunState.RUNNING
	time_left = duration_seconds
	time_changed.emit(time_left)
	if context.test_mode and context.forced_outcome != HeritageTaskRunContext.NO_FORCED_OUTCOME:
		call_deferred("_resolve_forced_outcome")
		return
	on_task_started()


func set_suspended(suspended: bool) -> void:
	if _completion_emitted:
		return
	if suspended and run_state == RunState.RUNNING:
		run_state = RunState.SUSPENDED
		on_suspension_changed(true)
	elif not suspended and run_state == RunState.SUSPENDED:
		run_state = RunState.RUNNING
		on_suspension_changed(false)


func abort_manual() -> void:
	if run_state == RunState.IDLE or run_state == RunState.FINISHED:
		return
	_complete(HeritageTaskResult.manual_abort(task_id))


func cancel_external(
		reason: StringName = &"cancelled",
		message: String = "任务已取消"
) -> void:
	if run_state == RunState.FINISHED or _completion_emitted:
		return
	_complete(HeritageTaskResult.cancelled(task_id, reason, message))


func complete_success(metrics: Dictionary = {}, message: String = "传承完成") -> void:
	_complete(HeritageTaskResult.success(task_id, metrics, message))


func complete_failure(
		reason: StringName = &"goal_not_met",
		message: String = "本次未能完成",
		metrics: Dictionary = {}
) -> void:
	var result := HeritageTaskResult.failure(task_id, reason, message)
	result.metrics = metrics.duplicate(true)
	_complete(result)


func complete_technical_error(reason: StringName, message: String) -> void:
	_complete(HeritageTaskResult.technical_error(task_id, reason, message))


func set_progress(value: float) -> void:
	var next_value: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next_value, progress):
		return
	progress = next_value
	progress_changed.emit(progress)
	queue_redraw()


func pulse_feedback(kind: StringName = &"hit", at_position: Vector2 = Vector2.ZERO) -> void:
	feedback_strength = 1.0
	feedback_requested.emit(kind, at_position)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "feedback_strength", 0.0, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func is_input_active() -> bool:
	return run_state == RunState.RUNNING and not _completion_emitted


func get_rng() -> RandomNumberGenerator:
	if context == null:
		var fallback := RandomNumberGenerator.new()
		fallback.seed = 1
		return fallback
	return context.rng


func _process(delta: float) -> void:
	if run_state != RunState.RUNNING or _completion_emitted:
		return
	time_left = maxf(0.0, time_left - delta)
	elapsed_seconds += delta
	time_changed.emit(time_left)
	task_tick(delta)
	queue_redraw()
	if time_left <= 0.0 and not _completion_emitted:
		on_time_expired()


func _unhandled_input(event: InputEvent) -> void:
	if not is_input_active():
		return
	if event.is_action_pressed(&"ui_cancel"):
		manual_abort_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if task_input(event):
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not is_input_active():
		return
	if task_gui_input(event):
		accept_event()
		return
	# 任务宿主会把键盘/手柄焦点交给小游戏本身。方向键与确认键既要
	# 更新 Input 的按住状态，也不能继续触发底层详情按钮或焦点导航。
	if _is_gameplay_ui_event(event):
		task_input(event)
		accept_event()


func _is_gameplay_ui_event(event: InputEvent) -> bool:
	return event.is_action(&"ui_accept") \
			or event.is_action(&"ui_left") \
			or event.is_action(&"ui_right") \
			or event.is_action(&"ui_up") \
			or event.is_action(&"ui_down")


func _complete(result: HeritageTaskResult) -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	run_state = RunState.FINISHED
	result.task_id = task_id
	result.elapsed_seconds = elapsed_seconds
	result.metrics["elapsed_seconds"] = elapsed_seconds
	result.metrics["progress"] = progress
	on_task_finished(result)
	task_completed.emit(result)


func _resolve_forced_outcome() -> void:
	if not is_input_active() or context == null:
		return
	match context.forced_outcome:
		HeritageTaskResult.Status.SUCCESS:
			complete_success({"forced": true}, "测试直达成功")
		HeritageTaskResult.Status.FAILURE:
			complete_failure(&"forced_failure", "测试直达失败", {"forced": true})
		HeritageTaskResult.Status.MANUAL_ABORT:
			abort_manual()
		HeritageTaskResult.Status.TECHNICAL_ERROR:
			complete_technical_error(&"forced_technical_error", "测试技术错误")
		HeritageTaskResult.Status.CANCELLED:
			cancel_external(&"forced_cancelled", "测试取消")
		_:
			complete_technical_error(&"invalid_forced_outcome", "测试结果无效")


func on_task_started() -> void:
	pass


func on_suspension_changed(_suspended: bool) -> void:
	pass


func on_task_finished(_result: HeritageTaskResult) -> void:
	pass


func task_tick(_delta: float) -> void:
	pass


func task_input(_event: InputEvent) -> bool:
	return false


func task_gui_input(_event: InputEvent) -> bool:
	return false


func on_time_expired() -> void:
	complete_failure(&"timeout", "时间到了")
