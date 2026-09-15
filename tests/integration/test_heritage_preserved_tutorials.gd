extends GutTest

const PREF_PATH := "user://test_preserved_tutorials.cfg"
const IDS: Array[StringName] = [&"gu_pen_ge", &"ezhou_diaohua_jianzhi", &"xisai_shenzhou_hui"]
var viewport: SubViewport

class NoCaptureScorer extends VocalScorer:
	func is_available() -> bool: return true
	func begin_capture(_id: StringName, _seconds: float) -> Error: return ERR_UNAVAILABLE

func before_each() -> void:
	HeritageMinigamePreferences.configure_storage_path(PREF_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 600)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)

func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH))
	HeritageMinigamePreferences.configure_storage_path()
	for action: StringName in [&"ui_left", &"ui_right", &"ui_accept"]: Input.action_release(action)

func test_first_lessons_freeze_formal_clock_and_cannot_complete_without_input() -> void:
	for id: StringName in IDS:
		var task := _start(id)
		for tick: int in 1500: task._process(.01)
		assert_true(task.is_tutorial_active(),str(id))
		assert_eq(task.game_time,0.0)
		assert_eq(task.time_left,task.duration_seconds)
		assert_false(HeritageMinigamePreferences.tutorial_done(id,task.tutorial_version()))
		task.cancel_external()
		task.queue_free()
		await wait_process_frames(1)

func test_gupen_fixed_lesson_uses_audio_clock_resets_rounds_and_remembers_completion() -> void:
	var task := _start(&"gu_pen_ge") as HeritagePerformanceTask
	var clock_class = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock
	task.stop_media()
	task.clock = clock_class.new()
	task.add_child(task.clock)
	task.restart_current_step()
	var sent: Dictionary = {}
	for tick: int in 6500:
		if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
		(task.clock as HeritageMusicClock).call("elapse", .01)
		task._process(.01)
		if task.phase != HeritageStageTask.Phase.PRACTICE: continue
		for event: Dictionary in task.lesson_chart.events:
			if event.kind == "rest": continue
			if task.clock.seconds() * 1000 >= int(event.time_ms) and not sent.has(event.id):
				sent[event.id] = true
				_click(Vector2(500,350),true)
				_click(Vector2(500,350),false)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	assert_eq(task.get("_round_index"),0)
	assert_eq(task.get("_rounds_passed"),0)
	assert_eq(task.game_time,0.0)
	assert_true(HeritageMinigamePreferences.tutorial_done(task.task_id,task.tutorial_version()))
	task.cancel_external()
	task.queue_free()
	await wait_process_frames(1)
	var next := _start(&"gu_pen_ge") as HeritagePerformanceTask
	assert_eq(next.phase,HeritageStageTask.Phase.COUNTDOWN)
	next.cancel_external()
	next.queue_free()
	await wait_process_frames(1)
	var relearn := _start(&"gu_pen_ge", {"force_tutorial":true,"skip_tutorial":true}) as HeritagePerformanceTask
	assert_eq(relearn.phase,HeritageStageTask.Phase.DEMO)

func test_paper_real_first_segment_requires_release_and_resets_cut_errors() -> void:
	var task := _start(&"ezhou_diaohua_jianzhi")
	var driver := preload("res://tests/support/action_story_input.gd")
	driver.tick(task,2.6)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	var path: PackedVector2Array = task.contours[0]
	driver.mouse(task,path[0],true)
	for point: Vector2 in path: driver.motion(task,point)
	driver.tick(task,.1)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE,"必须松开停刀")
	driver.mouse(task,path[-1],false)
	driver.tick(task,.02)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	driver.tick(task,3.1)
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	assert_eq(task.cut_distance,0.0)
	assert_eq(task.off_path_seconds,0.0)
	assert_eq(task.pointer,path[0])
	assert_false(task.dragging)

func test_boat_two_lane_changes_and_real_slowdown_reset_formal_state() -> void:
	var task := _start(&"xisai_shenzhou_hui")
	var driver := preload("res://tests/support/action_story_input.gd")
	driver.tick(task,2.6)
	driver.mouse(task,Vector2(220,350),true)
	driver.mouse(task,Vector2(220,350),false)
	driver.tick(task,.5)
	driver.mouse(task,Vector2(500,350),true)
	driver.mouse(task,Vector2(500,350),false)
	driver.tap(task,KEY_S)
	driver.tick(task,.6)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	driver.tick(task,3.1)
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	assert_eq(task.collisions,0)
	assert_eq(task.target_lane,1)
	assert_eq(task.target_speed,200.0)
	assert_lt(task.game_time,.5)

func test_lesson_pause_and_exit_freeze_and_settle_once_without_saving() -> void:
	var task := _start(&"ezhou_diaohua_jianzhi")
	watch_signals(task)
	task._process(.4)
	var before: float = task.phase_time
	task.set_suspended(true)
	task._process(5)
	assert_eq(task.phase_time,before)
	task.set_suspended(false)
	task.abort_manual()
	task.abort_manual()
	assert_signal_emit_count(task,"task_completed",1)
	assert_false(HeritageMinigamePreferences.tutorial_done(task.task_id,task.tutorial_version()))

func test_huangmei_keeps_required_listening_even_when_skip_or_relearn_requested() -> void:
	for metadata: Dictionary in [{"skip_tutorial":true},{"force_tutorial":true}]:
		var task := _start(&"huangmei_xi",metadata)
		assert_false(task.supports_interactive_tutorial())
		assert_eq(task.optional_lesson_phase,HeritageTaskBase.OptionalLesson.NONE)
		assert_eq(int(task.get("_stage")),0,"必要的LISTENING示范每次保留")
		task.cancel_external()
		task.queue_free()
		await wait_process_frames(1)

func _start(id: StringName, metadata: Dictionary = {}) -> HeritageTaskBase:
	var task := HeritageTaskManager.get_definition(id).instantiate_task()
	viewport.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(id,null,null,0,0,88,true)
	context.metadata = metadata.duplicate()
	if id == &"huangmei_xi": context.services[&"vocal_scorer"] = NoCaptureScorer.new()
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	task.focus_mode = Control.FOCUS_ALL
	task.grab_focus()
	return task

func _click(point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	viewport.push_input(event,true)

func _move(point: Vector2,relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event,true)
