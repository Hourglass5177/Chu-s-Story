extends GutTest

const DEFINITIONS_DIR := "res://InheritanceTasks/Definitions"
const HOST_SCENE := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")

const EXPECTED_TASK_IDS: Array[StringName] = [
	&"ezhou_diaohua_jianzhi",
	&"huangmei_xi",
	&"xisai_shenzhou_hui",
	&"xia_lian_dan_shu",
	&"gu_pen_ge",
	&"yandi_shennong_chuanshuo",
	&"tianmen_tang_su",
	&"han_ju",
	&"jingzhou_hua_gu_xi",
	&"ti_qin_xi",
	&"laohekou_si_xian",
	&"dong_yong_chuanshuo",
	&"tujia_saye_erhe",
	&"xiabaoping_minjian_gushi",
	&"xingshan_min_ge",
]
const STANDARD_TASK_IDS: Array[StringName] = [
	&"ezhou_diaohua_jianzhi",
	&"xisai_shenzhou_hui",
	&"xia_lian_dan_shu",
	&"gu_pen_ge",
	&"yandi_shennong_chuanshuo",
	&"tianmen_tang_su",
	&"han_ju",
	&"jingzhou_hua_gu_xi",
	&"ti_qin_xi",
	&"laohekou_si_xian",
	&"dong_yong_chuanshuo",
	&"tujia_saye_erhe",
	&"xiabaoping_minjian_gushi",
	&"xingshan_min_ge",
]
const RANDOMIZED_TASK_FIELDS: Dictionary[StringName, StringName] = {
	&"xiabaoping_minjian_gushi": &"candidates",
}


class FakeVocalScorer extends VocalScorer:
	var result_score: float = 72.0
	var capture_started: bool = false

	func is_available() -> bool:
		return true

	func begin_capture(_reference_id: StringName, _duration_seconds: float) -> Error:
		capture_started = true
		return OK

	func finish_capture_and_score() -> Error:
		if not capture_started:
			return ERR_UNCONFIGURED
		var payload := {
			"ok": true,
			"score": result_score,
			"feedback": "结尾音还可以再抬一点",
		}
		call_deferred("_emit_score", payload)
		return OK

	func cancel_capture() -> void:
		capture_started = false

	func _emit_score(payload: Dictionary) -> void:
		scoring_completed.emit(payload)


func test_all_fifteen_definitions_are_complete_unique_and_loadable() -> void:
	var files := DirAccess.get_files_at(DEFINITIONS_DIR)
	var definitions: Array[HeritageTaskDefinition] = []
	var ids: Dictionary[StringName, bool] = {}
	var thumbnail_paths: Dictionary[String, bool] = {}
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var definition := load(DEFINITIONS_DIR + "/" + file_name) as HeritageTaskDefinition
		assert_not_null(definition, file_name + " 必须加载为 HeritageTaskDefinition")
		if definition == null:
			continue
		definitions.append(definition)
		assert_true(definition.is_valid_definition(), file_name + " 定义必须完整")
		assert_eq(definition.display_name,definition.heritage_name,"小游戏统一使用非遗原名")
		assert_false(ids.has(definition.task_id), "task_id 不得重复：" + str(definition.task_id))
		assert_has(EXPECTED_TASK_IDS, definition.task_id)
		assert_not_null(definition.gallery_thumbnail, file_name + " 必须提供图鉴缩略图")
		if definition.gallery_thumbnail != null:
			var thumbnail_path := definition.gallery_thumbnail.resource_path
			assert_true(thumbnail_path.begins_with("res://arts/非遗卡牌/"), file_name + " 原型缩略图应使用对应国家级非遗牌正面")
			assert_false(thumbnail_paths.has(thumbnail_path), "15 项任务的缩略图必须一一对应")
			thumbnail_paths[thumbnail_path] = true
			var card_path := "res://Cards/非遗牌/%s/%s.tres" % [definition.region, definition.heritage_name]
			var heritage_card := load(card_path) as 非遗牌
			assert_not_null(heritage_card, file_name + " 必须能定位对应国家级非遗牌")
			if heritage_card != null:
				assert_same(definition.gallery_thumbnail, heritage_card.image_of_front, file_name + " 缩略图必须引用对应牌面")
		assert_false(definition.prototype_asset_note.strip_edges().is_empty(), file_name + " 必须说明当前原型素材")
		assert_false(definition.future_asset_slot.strip_edges().is_empty(), file_name + " 必须保留未来替换槽说明")
		assert_gte(definition.duration_seconds, 20.0)
		if definition.task_id == &"huangmei_xi":
			assert_eq(definition.duration_seconds, 45.0, "黄梅戏录唱使用独立的音频采样时长")
		elif definition.task_id == &"xiabaoping_minjian_gushi":
			assert_eq(definition.duration_seconds, 120.0, "三幕拼图共享120秒有效操作时间")
		else:
			assert_lte(definition.duration_seconds, 45.0, file_name + " 任务不得超过45秒")
		var task := autofree(definition.instantiate_task()) as HeritageTaskBase
		assert_not_null(task, file_name + " 必须实例化独立任务场景")
		if task != null:
			assert_eq(task.task_id, definition.task_id)
		ids[definition.task_id] = true
	assert_eq(definitions.size(), 15)
	assert_eq(ids.size(), EXPECTED_TASK_IDS.size())
	assert_eq(thumbnail_paths.size(), EXPECTED_TASK_IDS.size())


func test_each_task_uses_a_distinct_scene_and_script() -> void:
	var scene_paths: Dictionary[String, bool] = {}
	var script_paths: Dictionary[String, bool] = {}
	for task_id: StringName in EXPECTED_TASK_IDS:
		var definition := _load_definition(task_id)
		assert_not_null(definition)
		if definition == null:
			continue
		var scene_path: String = definition.task_scene.resource_path
		assert_false(scene_paths.has(scene_path), "每项任务必须有独立场景")
		scene_paths[scene_path] = true
		var task := autofree(definition.instantiate_task()) as HeritageTaskBase
		var task_script := task.get_script() as Script
		assert_not_null(task_script)
		if task_script != null:
			assert_false(script_paths.has(task_script.resource_path), "每项任务必须有独立控制器")
			script_paths[task_script.resource_path] = true
	assert_eq(scene_paths.size(), 15)
	assert_eq(script_paths.size(), 15)


func test_result_and_attempt_contracts_are_exact_and_idempotent() -> void:
	var result := HeritageTaskResult.success(&"han_ju", {"hits": 17})
	assert_eq(result.status, HeritageTaskResult.Status.SUCCESS)
	assert_eq(result.reason, &"completed")
	assert_true(result.is_success())
	assert_eq(result.metrics.hits, 17)

	var attempt := HeritageTaskAttempt.new(7, &"han_ju")
	assert_eq(attempt.energy_cost, 1)
	assert_eq(attempt.state, HeritageTaskAttempt.State.PENDING)
	assert_true(attempt.mark_running())
	assert_false(attempt.mark_running(), "同一尝试不得重复进入 RUNNING")
	assert_true(attempt.mark_finished())
	assert_false(attempt.mark_rolled_back(), "完成后的尝试不得回滚")


func test_run_context_has_private_repeatable_rng_without_touching_world_rng() -> void:
	var first := HeritageTaskRunContext.new(&"gu_pen_ge", null, null, 2, 5, 123456)
	var second := first.duplicate_snapshot()
	var first_values: Array[int] = []
	var second_values: Array[int] = []
	for index: int in 12:
		first_values.append(first.rng.randi_range(0, 9999))
		second_values.append(second.rng.randi_range(0, 9999))
	assert_eq(first_values, second_values)
	assert_eq(first.session_generation, second.session_generation)
	assert_eq(first.turn_epoch, second.turn_epoch)


func test_every_task_supports_deterministic_direct_success_and_failure() -> void:
	for task_id: StringName in EXPECTED_TASK_IDS:
		var definition := _load_definition(task_id)
		var success := await _run_forced(definition, HeritageTaskResult.Status.SUCCESS)
		assert_not_null(success, str(task_id) + " 必须回传成功结果")
		if success != null:
			assert_eq(success.status, HeritageTaskResult.Status.SUCCESS)
			assert_eq(success.task_id, task_id)
		var failure := await _run_forced(definition, HeritageTaskResult.Status.FAILURE)
		assert_not_null(failure, str(task_id) + " 必须回传失败结果")
		if failure != null:
			assert_eq(failure.status, HeritageTaskResult.Status.FAILURE)
			assert_eq(failure.task_id, task_id)


func test_task_suspension_freezes_clock_and_manual_abort_is_one_shot() -> void:
	var definition := _load_definition(&"ezhou_diaohua_jianzhi")
	var task := add_child_autofree(definition.instantiate_task()) as HeritageTaskBase
	_prepare_task_rect(task)
	var run_context := HeritageTaskRunContext.new(definition.task_id)
	run_context.metadata["skip_tutorial"] = true
	task.configure(run_context)
	var captured: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: captured.append(result))
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	var driver := preload("res://tests/support/action_story_input.gd")
	driver.tick(task,3.1)
	var before_suspend: float = task.time_left
	task.set_suspended(true)
	task._process(4.0)
	assert_almost_eq(task.time_left, before_suspend, 0.001)
	task.set_suspended(false)
	driver.tick(task,1.5)
	var after_resume: float = task.time_left
	assert_almost_eq(after_resume,before_suspend,.02,"恢复倒数也冻结正式计时")
	driver.tick(task,1.0)
	assert_almost_eq(task.time_left, after_resume - 1.0, 0.02)
	task.abort_manual()
	task.abort_manual()
	assert_eq(captured.size(), 1)
	assert_eq(captured[0].status, HeritageTaskResult.Status.MANUAL_ABORT)


func test_every_standard_task_suspends_without_advancing_clock_or_progress() -> void:
	for task_id: StringName in STANDARD_TASK_IDS:
		var task := _create_started_task(task_id, 4100)
		task._process(0.25)
		var clock_before: float = task.time_left
		var elapsed_before: float = task.elapsed_seconds
		var progress_before: float = task.progress
		task.set_suspended(true)
		task._process(3.0)
		assert_almost_eq(task.time_left, clock_before, 0.001, str(task_id) + " 暂停时不得扣时")
		assert_almost_eq(task.elapsed_seconds, elapsed_before, 0.001, str(task_id) + " 暂停时不得推进玩法")
		assert_almost_eq(task.progress, progress_before, 0.001, str(task_id) + " 暂停时不得改变进度")


func test_mouse_hold_state_is_cleared_when_suspending() -> void:
	for task_id: StringName in STANDARD_TASK_IDS:
		var task := _create_started_task(task_id,4200)
		if task is HeritageStageTask:
			task.pressed[0] = true
			task.pressed[-1] = true
			task.set_suspended(true)
			assert_false(task.pressed[0])
			assert_false(task.pressed[-1])
		elif task_id in [&"ezhou_diaohua_jianzhi",&"xisai_shenzhou_hui"]:
			task.set("_dragging",true)
			task.set_suspended(true)
			assert_false(task.get("_dragging"))


func test_standard_task_timeout_returns_a_specific_failure_reason() -> void:
	for task_id: StringName in STANDARD_TASK_IDS:
		var task := _create_started_task(task_id, 4300)
		var captured: Array[HeritageTaskResult] = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: captured.append(result))
		task.on_time_expired()
		assert_eq(captured.size(), 1, str(task_id) + " 超时必须产生一次结果")
		if captured.is_empty():
			continue
		assert_eq(captured[0].status, HeritageTaskResult.Status.FAILURE)
		assert_ne(captured[0].reason, &"timeout", str(task_id) + " 不得只返回笼统 timeout")
		assert_false(captured[0].message.is_empty(), str(task_id) + " 必须说明失败原因")
		assert_ne(captured[0].message, "时间到了", str(task_id) + " 必须给出具体反馈")


func test_randomized_tasks_repeat_exactly_with_the_same_private_seed() -> void:
	for task_id: StringName in RANDOMIZED_TASK_FIELDS:
		var first := _create_started_task(task_id, 4401)
		var second := _create_started_task(task_id, 4401)
		var different := _create_started_task(task_id, 4402)
		var field: StringName = RANDOMIZED_TASK_FIELDS[task_id]
		assert_eq(first.get(field), second.get(field), str(task_id) + " 相同种子必须生成相同内容")
		assert_ne(first.get(field), different.get(field), str(task_id) + " 随机内容必须真正受任务种子控制")
	# Music is authored against one final audio timeline, so changing the run
	# seed must not regenerate the teacher's demonstration or response events.
	var fixed_first := _create_started_task(&"gu_pen_ge", 4401)
	var fixed_other := _create_started_task(&"gu_pen_ge", 4402)
	assert_eq(fixed_first.get("chart").sections.size(), 3)
	assert_eq(fixed_first.get("chart").sections, fixed_other.get("chart").sections)
	assert_eq(fixed_first.get("chart").events, fixed_other.get("chart").events)
	assert_eq(fixed_first.get("chart").audio_sha256, fixed_other.get("chart").audio_sha256)


func test_all_standard_tasks_expose_mouse_and_ui_action_control_paths() -> void:
	for task_id: StringName in STANDARD_TASK_IDS:
		var task := _create_started_task(task_id,4301)
		assert_true(task.has_method("task_gui_input"))
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.position=Vector2(500,400)
		if task_id==&"yandi_shennong_chuanshuo": event.position=Vector2(112,560)
		event.pressed=true
		if task_id != &"gu_pen_ge": assert_true(task.task_gui_input(event),str(task_id))
	for action: StringName in [&"ui_left",&"ui_right",&"ui_up",&"ui_down",&"ui_accept"]:
		var has_keyboard: bool=false
		var has_gamepad: bool=false
		for event: InputEvent in InputMap.action_get_events(action):
			has_keyboard=has_keyboard or event is InputEventKey
			has_gamepad=has_gamepad or event is InputEventJoypadButton or event is InputEventJoypadMotion
		assert_true(has_keyboard)
		if action!=&"ui_accept": assert_true(has_gamepad)


func test_raw_gamepad_accept_is_handled_by_every_accept_driven_task() -> void:
	for task_id: StringName in [&"ezhou_diaohua_jianzhi",&"gu_pen_ge",&"jingzhou_hua_gu_xi",&"tianmen_tang_su",&"xia_lian_dan_shu",&"xingshan_min_ge",&"yandi_shennong_chuanshuo"]:
		var task := _create_started_task(task_id,4450)
		for down: bool in [true,false]:
			var event := InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_A
			event.pressed = down
			assert_true(task.task_input(event),str(task_id))

func test_paper_cut_cannot_teleport_from_start_to_finish() -> void:
	var task := _create_started_task(&"ezhou_diaohua_jianzhi",4500)
	var driver := preload("res://tests/support/action_story_input.gd")
	var path: PackedVector2Array = task.get("contours")[0]
	driver.mouse(task,path[0],true)
	driver.motion(task,path[path.size()/2])
	driver.mouse(task,path[-1],false)
	assert_eq(task.get("segment"),0)
	assert_lt(task.get("cut_distance"),task.get("cut_length")*.7)

func test_tiqin_uses_discrete_bow_phrases_instead_of_reskinning_sixian_tracking() -> void:
	var bow := _load_definition(&"ti_qin_xi").music_chart
	var pluck := _load_definition(&"laohekou_si_xian").music_chart
	var hold_count: int=0
	for e: Dictionary in bow.events:
		if e.kind=="hold": hold_count+=1
	assert_gt(hold_count,0)
	for e: Dictionary in pluck.events: assert_ne(e.kind,"hold")


func test_shenzhou_requires_steering_but_remains_controllable() -> void:
	var driver := preload("res://tests/support/action_story_input.gd")
	for control: bool in [false,true]:
		var task := _create_started_task(&"xisai_shenzhou_hui",4600)
		var outcomes: Array = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: outcomes.append(result))
		for frame: int in 36*120:
			if task.run_state==HeritageTaskBase.RunState.FINISHED: break
			if control: driver.escort(task)
			task._process(1.0/120.0)
		assert_eq(outcomes.size(),1)
		if not outcomes.is_empty(): assert_eq(outcomes[0].is_success(),control)

func test_tang_su_three_breaths_take_most_of_the_task_window() -> void:
	var task := _create_started_task(&"tianmen_tang_su",4700) as HeritageStageTask
	var captured: Array[HeritageTaskResult]=[]
	task.task_completed.connect(func(r: HeritageTaskResult) -> void: captured.append(r))
	var residual_seen: bool=false
	var release_radius: float=0
	for frame: int in 3500:
		if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		var state: int=task.get("blow_phase")
		var event:=InputEventAction.new()
		event.action=&"ui_accept"
		if state==0:
			event.pressed=true
			task.task_input(event)
		elif state==1 and float(task.get("radius"))> ([0.59,0.69,0.62][int(task.get("trial"))]):
			release_radius=task.get("radius")
			event.pressed=false
			task.task_input(event)
		elif state==2 and float(task.get("radius"))>release_radius+0.005:
			residual_seen=true
		task._process(1.0/120)
	assert_true(residual_seen,"松开后必须实际继续膨胀")
	assert_eq(captured.size(),1)
	if not captured.is_empty():
		assert_eq(captured[0].status,HeritageTaskResult.Status.SUCCESS)
		assert_gte(captured[0].elapsed_seconds,18.0)
		assert_lte(captured[0].elapsed_seconds,28.0)


func test_shennong_platformer_has_high_ground_hazards_and_goal() -> void:
	var task:=_create_started_task(&"yandi_shennong_chuanshuo",4800)
	var platforms: Array=task.get("_platforms")
	var hazards: Array=task.get("_hazards")
	assert_gte(platforms.size(),6)
	assert_gte(hazards.size(),1)
	for i: int in range(1,platforms.size()):
		var rise: float=platforms[i-1].position.y-platforms[i].position.y
		assert_lte(rise,470.0*470.0/(2*1150.0)*0.75)
	assert_true((task.get("_goal") as Rect2).has_area())
	# Reachability is exercised through normal input in test_heritage_rework.


func test_host_configures_begins_and_forwards_exactly_one_result() -> void:
	var host := add_child_autofree(HOST_SCENE.instantiate()) as HeritageTaskHost
	await wait_process_frames(1)
	var definition := _load_definition(&"tianmen_tang_su")
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode = true
	context.forced_outcome = HeritageTaskResult.Status.SUCCESS
	watch_signals(host)
	host.configure(definition, context)
	host.begin()
	host.begin()
	host.start_from_preparation()
	await wait_process_frames(2)
	host.cancel(&"late_cancel")
	assert_signal_emit_count(host, "task_entered", 1)
	assert_signal_emit_count(host, "task_finished", 1)
	assert_not_null(host.get_active_task())


func test_host_reconfigure_cancels_old_task_without_leaking_a_public_result() -> void:
	var host := add_child_autofree(HOST_SCENE.instantiate()) as HeritageTaskHost
	await wait_process_frames(1)
	var first := _load_definition(&"xia_lian_dan_shu")
	var second := _load_definition(&"gu_pen_ge")
	watch_signals(host)
	host.configure(first, HeritageTaskRunContext.new(first.task_id))
	host.begin()
	host.start_from_preparation()
	host.configure(second, HeritageTaskRunContext.new(second.task_id))
	assert_signal_emit_count(host, "task_finished", 0)
	assert_null(host.get_active_task())
	host.begin()
	host.start_from_preparation()
	assert_signal_emit_count(host, "task_entered", 2)


func test_huangmei_missing_scorer_reports_technical_error() -> void:
	var definition := _load_definition(&"huangmei_xi")
	var task := add_child_autofree(definition.instantiate_task()) as HeritageTaskBase
	_prepare_task_rect(task)
	task.configure(HeritageTaskRunContext.new(definition.task_id))
	var captured: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: captured.append(result))
	task.start_task()
	assert_eq(captured.size(), 1)
	assert_eq(captured[0].status, HeritageTaskResult.Status.TECHNICAL_ERROR)
	assert_eq(captured[0].reason, &"vocal_scorer_missing")


func test_huangmei_injected_scorer_can_complete_successfully() -> void:
	var definition := _load_definition(&"huangmei_xi")
	var scorer := FakeVocalScorer.new()
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.services[&"vocal_scorer"] = scorer
	var task := add_child_autofree(definition.instantiate_task()) as HeritageTaskBase
	_prepare_task_rect(task)
	task.configure(context)
	var captured: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: captured.append(result))
	task.start_task()
	task.call("_begin_recording")
	task.call("_finish_recording")
	await wait_process_frames(2)
	assert_eq(captured.size(), 1)
	assert_eq(captured[0].status, HeritageTaskResult.Status.SUCCESS)
	assert_eq(float(captured[0].metrics.score), 72.0)


func _load_definition(task_id: StringName) -> HeritageTaskDefinition:
	return load(DEFINITIONS_DIR + "/" + str(task_id) + ".tres") as HeritageTaskDefinition


func _create_started_task(task_id: StringName, seed: int) -> HeritageTaskBase:
	var definition := _load_definition(task_id)
	var task := add_child_autofree(definition.instantiate_task()) as HeritageTaskBase
	_prepare_task_rect(task)
	var run_context := HeritageTaskRunContext.new(task_id, null, null, 1, 1, seed)
	run_context.test_mode = true
	run_context.metadata["skip_tutorial"] = true
	task.configure(run_context)
	task.start_task()
	if task is HeritageStageTask: task._process(3.1)
	return task


func _run_until_finished(task: HeritageTaskBase, max_frames: int = 2000) -> void:
	var frame_count: int = 0
	while task.run_state == HeritageTaskBase.RunState.RUNNING and frame_count < max_frames:
		task._process(1.0 / 60.0)
		frame_count += 1


func _run_forced(
		definition: HeritageTaskDefinition,
		status: HeritageTaskResult.Status
) -> HeritageTaskResult:
	var task := add_child_autofree(definition.instantiate_task()) as HeritageTaskBase
	_prepare_task_rect(task)
	var context := HeritageTaskRunContext.new(definition.task_id, null, null, 1, 1, 99)
	if definition.task_id == &"huangmei_xi":
		context.services[&"vocal_scorer"] = FakeVocalScorer.new()
	context.test_mode = true
	context.forced_outcome = status
	var captured: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: captured.append(result))
	task.configure(context)
	task.start_task()
	await wait_process_frames(2)
	return captured[0] if not captured.is_empty() else null


func _prepare_task_rect(task: HeritageTaskBase) -> void:
	# The production host stretches task scenes to its container. Unit tests have
	# no parent layout, so use fixed anchors before assigning a deterministic size.
	task.set_anchors_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000, 640)
