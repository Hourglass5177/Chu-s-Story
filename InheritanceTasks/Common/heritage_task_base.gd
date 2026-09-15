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
var _feedback_tween: Tween
var pixel_stage: HeritagePixelStage
var pixel_screen: TextureRect
enum OptionalLesson { NONE, DEMO, PRACTICE, COUNTDOWN }
var optional_lesson_phase: OptionalLesson = OptionalLesson.NONE
var optional_lesson_time: float = 0.0
var optional_lesson_elapsed: float = 0.0
var _lesson_caption: Label
var _menu_input_profile: HeritageInputProfile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_unhandled_input(true)
	resized.connect(func() -> void:
		if is_instance_valid(_lesson_caption): _update_lesson_caption())


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
	optional_lesson_phase = OptionalLesson.NONE
	optional_lesson_time = 0.0
	optional_lesson_elapsed = 0.0
	if is_instance_valid(_lesson_caption): _lesson_caption.hide()
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
	if run_state != RunState.FINISHED:
		_setup_pixel_stage()
		if supports_interactive_tutorial():
			var skip := bool(context.metadata.get("skip_tutorial", HeritageMinigamePreferences.tutorial_done(task_id, maxi(4,tutorial_version()))))
			if bool(context.metadata.get("force_tutorial", false)): skip = false
			if not skip:
				optional_lesson_phase = OptionalLesson.DEMO if optional_demo_duration() > 0 else OptionalLesson.PRACTICE
				on_optional_lesson_started()
				_update_lesson_caption()


func set_suspended(suspended: bool) -> void:
	if _completion_emitted:
		return
	if suspended and run_state == RunState.RUNNING:
		run_state = RunState.SUSPENDED
		if _feedback_tween != null and _feedback_tween.is_valid(): _feedback_tween.pause()
		on_suspension_changed(true)
	elif not suspended and run_state == RunState.SUSPENDED:
		run_state = RunState.RUNNING
		if _feedback_tween != null and _feedback_tween.is_valid(): _feedback_tween.play()
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
	if _feedback_tween != null and _feedback_tween.is_valid(): _feedback_tween.kill()
	var tween := create_tween()
	_feedback_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "feedback_strength", 0.0, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func is_input_active() -> bool:
	return run_state == RunState.RUNNING and not _completion_emitted \
		and optional_lesson_phase not in [OptionalLesson.DEMO, OptionalLesson.COUNTDOWN]


func is_task_clock_running() -> bool:
	return true


func get_time_display() -> String:
	if optional_lesson_phase == OptionalLesson.COUNTDOWN: return "准备 %d" % maxi(1, ceili(1.5 - optional_lesson_time))
	if optional_lesson_phase != OptionalLesson.NONE: return "练习"
	return "%d秒" % ceili(time_left)


func get_rng() -> RandomNumberGenerator:
	if context == null:
		var fallback := RandomNumberGenerator.new()
		fallback.seed = 1
		return fallback
	return context.rng


func _process(delta: float) -> void:
	if run_state != RunState.RUNNING or _completion_emitted:
		return
	if optional_lesson_phase != OptionalLesson.NONE:
		_tick_optional_lesson(delta)
		return
	if is_task_clock_running():
		time_left = maxf(0.0, time_left - delta)
	elapsed_seconds += delta
	time_changed.emit(time_left)
	task_tick(delta)
	queue_redraw()
	if time_left <= 0.0 and not _completion_emitted and is_task_clock_running():
		on_time_expired()


func _unhandled_input(event: InputEvent) -> void:
	# Pointer tracking belongs to GUI input. A high-polling-rate mouse must
	# not repeatedly traverse keyboard/action bindings after GUI dispatch.
	if event is InputEventMouseMotion: return
	if run_state != RunState.RUNNING or _completion_emitted:
		return
	if event.is_action_pressed(&"ui_cancel"):
		manual_abort_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not is_input_active(): return
	if task_input(event):
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not is_input_active():
		return
	if task_gui_input(event):
		accept_event()
		return
	if event is InputEventMouseMotion: return
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
	if _feedback_tween != null and _feedback_tween.is_valid(): _feedback_tween.kill()
	run_state = RunState.FINISHED
	if is_instance_valid(_lesson_caption): _lesson_caption.hide()
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


# The three preserved craft/steering controllers opt in; Stage tasks retain
# their own music/physics lesson lifecycle and Huangmei always plays its example.
func supports_interactive_tutorial() -> bool:
	return false


func tutorial_version() -> int:
	return 4


func get_input_profile() -> HeritageInputProfile:
	if _menu_input_profile == null: _menu_input_profile = HeritageInputProfile.new(HeritageInputProfile.for_task(task_id),task_id)
	return _menu_input_profile


func get_input_device() -> StringName:
	return get_input_profile().device


func get_control_hints() -> Array[Dictionary]:
	return [] if task_id == &"huangmei_xi" else get_input_profile().control_hints()


func is_tutorial_active() -> bool:
	return optional_lesson_phase in [OptionalLesson.DEMO,OptionalLesson.PRACTICE]


func get_instruction_state() -> Dictionary:
	var phase_name := "live"
	if optional_lesson_phase == OptionalLesson.DEMO: phase_name = "demo"
	elif optional_lesson_phase == OptionalLesson.PRACTICE: phase_name = "practice"
	elif optional_lesson_phase == OptionalLesson.COUNTDOWN: phase_name = "countdown"
	return {"phase":phase_name,"teaching":is_tutorial_active(),"text":optional_lesson_instruction(),"countdown":maxi(1,ceili(1.5-optional_lesson_time))}


func restart_current_step() -> void:
	if not is_tutorial_active() or run_state != RunState.RUNNING: return
	context.reset_rng()
	on_task_started()
	optional_lesson_phase = OptionalLesson.DEMO if optional_demo_duration() > 0 else OptionalLesson.PRACTICE
	optional_lesson_time = 0.0
	on_optional_lesson_started()
	_update_lesson_caption()


func skip_tutorial() -> void:
	if not is_tutorial_active() or run_state != RunState.RUNNING: return
	optional_lesson_phase = OptionalLesson.COUNTDOWN
	optional_lesson_time = 0.0
	on_suspension_changed(true)
	set_progress(0.0)
	_update_lesson_caption()


func optional_demo_duration() -> float:
	return 1.8


func on_optional_lesson_started() -> void:
	pass


func optional_demo_tick(_delta: float) -> void:
	pass


func optional_practice_tick(_delta: float) -> void:
	pass


func optional_lesson_instruction() -> String:
	return "跟着做一次"


func finish_optional_lesson() -> void:
	if optional_lesson_phase != OptionalLesson.PRACTICE: return
	if not context.test_mode: HeritageMinigamePreferences.complete_tutorial(task_id, maxi(4,tutorial_version()))
	optional_lesson_phase = OptionalLesson.COUNTDOWN
	optional_lesson_time = 0.0
	on_suspension_changed(true)
	set_progress(0.0)
	_update_lesson_caption()


func _tick_optional_lesson(delta: float) -> void:
	optional_lesson_time += delta
	optional_lesson_elapsed += delta
	match optional_lesson_phase:
		OptionalLesson.DEMO:
			optional_demo_tick(delta)
			if optional_lesson_time >= optional_demo_duration():
				context.reset_rng()
				on_task_started()
				set_progress(0.0)
				optional_lesson_phase = OptionalLesson.PRACTICE
				optional_lesson_time = 0.0
				on_optional_lesson_started()
		OptionalLesson.PRACTICE:
			optional_practice_tick(delta)
		OptionalLesson.COUNTDOWN:
			if optional_lesson_time >= 1.5 and not _lesson_input_held():
				context.reset_rng()
				on_task_started()
				on_suspension_changed(false)
				optional_lesson_phase = OptionalLesson.NONE
				elapsed_seconds = 0.0
				time_left = duration_seconds
				feedback_strength = 0.0
				set_progress(0.0)
	_update_lesson_caption()
	time_changed.emit(time_left)
	queue_redraw()


func _lesson_input_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return true
	for action: StringName in [&"ui_accept", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		if Input.is_action_pressed(action): return true
	return false


func _update_lesson_caption() -> void:
	if context != null and bool(context.metadata.get("host_instruction_overlay",false)):
		if is_instance_valid(_lesson_caption): _lesson_caption.hide()
		return
	if not is_instance_valid(_lesson_caption):
		_lesson_caption = Label.new()
		_lesson_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lesson_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lesson_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lesson_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lesson_caption.z_index = 20
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(.10, .13, .12, .96)
		panel.content_margin_left = 12
		panel.content_margin_right = 12
		_lesson_caption.add_theme_stylebox_override("normal", panel)
		_lesson_caption.add_theme_color_override("font_color", Color("fff0ce"))
		add_child(_lesson_caption)
	_lesson_caption.visible = optional_lesson_phase != OptionalLesson.NONE and run_state != RunState.FINISHED
	var physical_scale := maxf(.1, (get_viewport().get_stretch_transform() * get_global_transform_with_canvas()).get_scale().y)
	var margin := 12.0 / physical_scale
	_lesson_caption.add_theme_font_size_override("font_size", ceili(18.0 / physical_scale))
	_lesson_caption.size = Vector2(maxf(1, size.x - margin * 2), 64.0 / physical_scale)
	_lesson_caption.position = Vector2(margin, size.y - _lesson_caption.size.y - margin)
	if optional_lesson_phase == OptionalLesson.COUNTDOWN:
		_lesson_caption.text = "练会了 · 松开按键，准备开始" if _lesson_input_held() else "练会了 · %d 秒后正式开始" % maxi(1, ceili(1.5 - optional_lesson_time))
	else:
		_lesson_caption.text = ("示范 · " if optional_lesson_phase == OptionalLesson.DEMO else "练习 · ") + optional_lesson_instruction()


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


func _setup_pixel_stage() -> void:
	if is_instance_valid(pixel_stage) or context == null: return
	var artwork := context.metadata.get(&"presentation") as HeritageTaskPresentation
	if artwork == null or artwork.background == null: return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if str(artwork.properties.get("painter", "")) == "story": return
	pixel_stage = HeritagePixelStage.new()
	pixel_stage.configure(artwork, context.avatar_id)
	add_child(pixel_stage)
	pixel_screen = TextureRect.new()
	pixel_screen.texture = pixel_stage.get_texture()
	pixel_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pixel_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel_screen.show_behind_parent = true
	add_child(pixel_screen)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func layout_pixel_stage() -> void:
	if not is_instance_valid(pixel_screen): return
	var stage := Vector2(1000,600)
	var factor := minf(size.x / stage.x,size.y / stage.y)
	pixel_screen.size = stage * factor
	pixel_screen.position = (size - pixel_screen.size) * .5


func get_visual_state() -> Dictionary:
	var state := {"task_id": task_id, "animation_time": optional_lesson_elapsed if optional_lesson_phase != OptionalLesson.NONE else elapsed_seconds, "progress": progress, "action": &"ready", "reduced_motion": bool(context.metadata.get("reduce_motion", false)) if context != null else false}
	if has_method("get_presentation_state"): state.merge(call("get_presentation_state"), true)
	return state


func draw_pixel_presentation() -> bool:
	if not is_instance_valid(pixel_stage): return false
	var stage := Vector2(1000, 600)
	var factor := minf(size.x / stage.x, size.y / stage.y)
	draw_set_transform((size - stage * factor) * .5, 0.0, Vector2.ONE * factor)
	layout_pixel_stage()
	pixel_stage.update_state(get_visual_state())
	draw_pixel_overlay()
	draw_set_transform(Vector2.ZERO)
	return true


func draw_pixel_overlay() -> void:
	pass
