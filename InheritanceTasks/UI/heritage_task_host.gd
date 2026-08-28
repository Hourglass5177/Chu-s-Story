class_name HeritageTaskHost
extends Control

signal task_entered(task_id: StringName)
signal task_finished(result: HeritageTaskResult)
signal return_requested

@onready var title_label: Label = %TitleLabel
@onready var heritage_label: Label = %HeritageLabel
@onready var hook_label: Label = %HookLabel
@onready var control_label: Label = %ControlLabel
@onready var time_label: Label = %TimeLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var task_container: Control = %TaskContainer
@onready var abort_button: Button = %AbortButton
@onready var pause_button: Button = %PauseButton
@onready var pause_panel: Control = %PausePanel
@onready var exit_confirm: Control = %ExitConfirm
@onready var result_panel: Control = %ResultPanel
@onready var result_title: Label = %ResultTitle
@onready var result_message: Label = %ResultMessage
@onready var return_button: Button = %ReturnButton
@onready var _interaction_coordinator: Node = get_node_or_null("/root/InteractionCoordinator")

var definition: HeritageTaskDefinition = null
var context: HeritageTaskRunContext = null
var active_task: HeritageTaskBase = null
var _begun: bool = false
var _terminal_emitted: bool = false
var _entry_emitted: bool = false
var _suspension_reasons: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	abort_button.pressed.connect(_on_abort_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%PauseExitButton.pressed.connect(_show_exit_confirm)
	%CancelExitButton.pressed.connect(_hide_exit_confirm)
	%ConfirmExitButton.pressed.connect(_confirm_abort)
	return_button.pressed.connect(func() -> void: return_requested.emit())
	pause_panel.hide()
	exit_confirm.hide()
	result_panel.hide()
	set_process(true)


func configure(
		p_definition: HeritageTaskDefinition,
		p_context: HeritageTaskRunContext
) -> void:
	_clear_task()
	definition = p_definition
	context = p_context.duplicate_snapshot() if p_context != null else null
	_begun = false
	_terminal_emitted = false
	_entry_emitted = false
	_suspension_reasons.clear()
	_render_definition()
	pause_panel.hide()
	exit_confirm.hide()
	result_panel.hide()


func begin() -> void:
	if _begun:
		return
	_begun = true
	if definition == null or not definition.is_valid_definition():
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id if definition != null else &"",
			&"invalid_definition",
			"任务资源未就绪"
		))
		return
	if context == null:
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id, &"missing_context", "任务数据未就绪"
		))
		return
	active_task = definition.instantiate_task()
	if active_task == null:
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id, &"invalid_task_scene", "任务场景无法载入"
		))
		return
	active_task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active_task.duration_seconds = definition.duration_seconds
	active_task.task_completed.connect(_on_task_completed, CONNECT_ONE_SHOT)
	active_task.manual_abort_requested.connect(_show_exit_confirm)
	active_task.time_changed.connect(_on_time_changed)
	active_task.progress_changed.connect(_on_progress_changed)
	task_container.add_child(active_task)
	# 任务开始前，焦点通常仍停在底层详情的“传承任务”按钮上。
	# 将焦点交给全屏小游戏，避免第一次确认/方向输入穿透到底层控件。
	active_task.focus_mode = Control.FOCUS_ALL
	active_task.grab_focus()
	context.metadata[&"reference_video_path"] = definition.reference_video_path
	context.metadata[&"reference_audio_path"] = definition.reference_audio_path
	context.metadata[&"reference_analysis_path"] = definition.reference_analysis_path
	active_task.configure(context)
	active_task.start_task()
	# on_task_started() 会同步完成设备、媒体等前置检查。只有任务仍然
	# 处于可玩的运行态，才算真正进入，避免加载/准备故障误解锁图鉴。
	if active_task.run_state == HeritageTaskBase.RunState.RUNNING \
			or active_task.run_state == HeritageTaskBase.RunState.SUSPENDED:
		_emit_task_entered_once()


func suspend() -> void:
	_set_suspension(&"external", true)


func resume() -> void:
	_set_suspension(&"external", false)


func _process(_delta: float) -> void:
	var coordinator_suspended := false
	if _interaction_coordinator != null \
			and _interaction_coordinator.has_method("is_active_suspended"):
		coordinator_suspended = bool(_interaction_coordinator.call("is_active_suspended"))
	_set_suspension(&"guide", coordinator_suspended)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_suspension(&"window_focus", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_suspension(&"window_focus", false)


func cancel(reason: StringName = &"host_cancelled") -> void:
	if _terminal_emitted:
		return
	if is_instance_valid(active_task):
		active_task.cancel_external(reason)
	elif _begun:
		_finish_without_task(HeritageTaskResult.cancelled(
			definition.task_id if definition != null else &"", reason
		))


func get_active_task() -> HeritageTaskBase:
	return active_task


func _render_definition() -> void:
	if definition == null:
		title_label.text = "传承任务"
		heritage_label.text = ""
		hook_label.text = ""
		control_label.text = ""
		time_label.text = "--"
		progress_bar.value = 0.0
		return
	title_label.text = definition.display_name
	heritage_label.text = definition.heritage_name
	hook_label.text = definition.hook
	control_label.text = definition.control_hint
	time_label.text = "%d秒" % ceili(definition.duration_seconds)
	progress_bar.value = 0.0


func _on_time_changed(seconds_left: float) -> void:
	time_label.text = "%d秒" % ceili(seconds_left)


func _on_progress_changed(value: float) -> void:
	progress_bar.value = value * 100.0


func _on_abort_pressed() -> void:
	_show_exit_confirm()


func _on_pause_pressed() -> void:
	if _terminal_emitted:
		return
	pause_panel.show()
	_set_suspension(&"local_pause", true)
	%ResumeButton.grab_focus()


func _on_resume_pressed() -> void:
	pause_panel.hide()
	_set_suspension(&"local_pause", false)
	_restore_task_focus()


func _show_exit_confirm() -> void:
	if _terminal_emitted:
		return
	exit_confirm.show()
	_set_suspension(&"exit_confirm", true)
	%CancelExitButton.grab_focus()


func _hide_exit_confirm() -> void:
	exit_confirm.hide()
	_set_suspension(&"exit_confirm", false)
	_restore_task_focus()


func _confirm_abort() -> void:
	exit_confirm.hide()
	_set_suspension(&"exit_confirm", false)
	if is_instance_valid(active_task):
		active_task.abort_manual()


func _on_task_completed(result: HeritageTaskResult) -> void:
	if _terminal_emitted:
		return
	# 兼容未来可能在 start_task() 内同步完成的轻量任务；技术故障和
	# 外部取消不代表真正进入过玩法。
	if result.status == HeritageTaskResult.Status.SUCCESS \
			or result.status == HeritageTaskResult.Status.FAILURE \
			or result.status == HeritageTaskResult.Status.MANUAL_ABORT:
		_emit_task_entered_once()
	_terminal_emitted = true
	abort_button.disabled = true
	pause_button.disabled = true
	_suspension_reasons.clear()
	_show_result(result)
	task_finished.emit(result)


func _emit_task_entered_once() -> void:
	if _entry_emitted or definition == null:
		return
	_entry_emitted = true
	task_entered.emit(definition.task_id)


func _finish_without_task(result: HeritageTaskResult) -> void:
	if _terminal_emitted:
		return
	_terminal_emitted = true
	abort_button.disabled = true
	pause_button.disabled = true
	_suspension_reasons.clear()
	_show_result(result)
	task_finished.emit(result)


func _set_suspension(reason: StringName, enabled: bool) -> void:
	if enabled:
		_suspension_reasons[reason] = true
	else:
		_suspension_reasons.erase(reason)
	if is_instance_valid(active_task):
		active_task.set_suspended(not _suspension_reasons.is_empty())


func _show_result(result: HeritageTaskResult) -> void:
	pause_panel.hide()
	exit_confirm.hide()
	result_panel.show()
	match result.status:
		HeritageTaskResult.Status.SUCCESS:
			result_title.text = "传承完成"
		HeritageTaskResult.Status.FAILURE:
			result_title.text = "未能完成"
		HeritageTaskResult.Status.MANUAL_ABORT:
			result_title.text = "已退出"
		HeritageTaskResult.Status.TECHNICAL_ERROR:
			result_title.text = "任务中断"
		_:
			result_title.text = "任务已取消"
	var suffix := ""
	if result.status == HeritageTaskResult.Status.FAILURE or result.status == HeritageTaskResult.Status.MANUAL_ABORT:
		suffix = "\n下个行动阶段可再次挑战。"
	elif result.status == HeritageTaskResult.Status.TECHNICAL_ERROR:
		suffix = "\n已返还精力与本次机会。"
	result_message.text = (result.message if not result.message.is_empty() else "本次任务已经结束。") + suffix
	return_button.grab_focus()


func _restore_task_focus() -> void:
	if is_instance_valid(active_task) and not _terminal_emitted:
		active_task.grab_focus()


func _clear_task() -> void:
	if is_instance_valid(active_task):
		if active_task.task_completed.is_connected(_on_task_completed):
			active_task.task_completed.disconnect(_on_task_completed)
		active_task.cancel_external(&"host_reconfigured")
		active_task.queue_free()
	active_task = null
	if is_instance_valid(task_container):
		for child: Node in task_container.get_children():
			child.queue_free()
	if is_instance_valid(abort_button):
		abort_button.disabled = false
	if is_instance_valid(pause_button):
		pause_button.disabled = false
