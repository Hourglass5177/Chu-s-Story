extends GutTest

const IDS := ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]
const ClockFixture = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock

func before_all() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://rhythm-v2-contract-tests.cfg")
	HeritageMinigamePreferences.save_offset(0)

func after_all() -> void:
	HeritageMinigamePreferences.configure_storage_path()

func _event(id: String, at: int, kind: String = "tap", direction: int = 0, end: int = -1) -> Dictionary:
	return {"id":id, "time_ms":at, "kind":kind, "direction":direction, "end_ms":at if end < 0 else end, "cue_ms":1000}

func _judge(events: Array[Dictionary]) -> HeritageMusicJudge:
	var chart := HeritageMusicChart.new()
	chart.events = events
	var judge := HeritageMusicJudge.new()
	judge.configure(chart)
	return judge

func _task(id: String, skip: bool = true) -> HeritagePerformanceTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritagePerformanceTask
	task.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child_autofree(task)
	task.size = Vector2(1000, 600)
	task.clock = ClockFixture.new()
	task.add_child(task.clock)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = skip
	context.metadata["host_controls"] = true
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	return task

func _frame(task: HeritagePerformanceTask, dt: float = 1.0 / 120.0) -> void:
	(task.clock as ClockFixture).elapse(dt)
	task._process(dt)

func _edge(task: HeritagePerformanceTask, direction: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_A if direction < 0 else KEY_D if direction > 0 else KEY_SPACE
	event.keycode = event.physical_keycode
	event.pressed = down
	task.task_input(event)

func _play_due(task: HeritagePerformanceTask, sent: Dictionary, omit_first: int = 0, bad_release: bool = false) -> void:
	var active: HeritageMusicJudge = task.lesson_judge if task.phase == HeritageStageTask.Phase.PRACTICE else task.judge
	var ms := roundi(task.clock.seconds() * 1000.0)
	var count := 0
	for event: Dictionary in active.events:
		if event.kind == "rest": continue
		count += 1
		if count <= omit_first: continue
		var id := str(event.id) + ":" + str(task.lesson_round)
		if ms >= int(event.time_ms) and not sent.has(id):
			sent[id] = true
			_edge(task, int(event.direction), true)
		var up := int(event.end_ms) if event.kind == "hold" else int(event.time_ms) + 70
		if bad_release and event.kind == "hold": up -= 450
		if ms >= up and not sent.has(id + "-up"):
			sent[id + "-up"] = true
			_edge(task, int(event.direction), false)

func test_all_six_authored_charts_validate_have_distinct_feedback_and_preserved_review_status() -> void:
	var hashes: Dictionary = {}
	for id: String in IDS:
		var chart := load("res://InheritanceTasks/Charts/%s.tres" % id) as HeritageMusicChart
		assert_eq(chart.version, 3 if id=="gu_pen_ge" else 4, id)
		assert_eq(chart.validate(), "", id)
		assert_eq(chart.production_status, "game_arrangement_pending_listening" if id=="gu_pen_ge" else "continuous_source_integrated_timing_listening_pending", id)
		assert_true(ResourceLoader.exists(chart.tutorial_audio_path), id)
		assert_eq(FileAccess.get_sha256(chart.audio_path), chart.audio_sha256, id)
		var path := "res://InheritanceTasks/Audio/rhythm-v2/%s.wav" % chart.feedback_key
		if chart.feedback_key in ["sing","bow"]: path="res://InheritanceTasks/Audio/rhythm-v4/%s-recorded.wav"%chart.feedback_key
		assert_true(ResourceLoader.exists(path), id)
		var hash_value := FileAccess.get_sha256(path)
		assert_false(hashes.has(hash_value), "Six input sounds must not be the same beep")
		hashes[hash_value] = true

func test_held_input_into_rest_is_detected_independently_of_frame_delivery() -> void:
	var rest := _event("rest", 2000, "rest", 0, 2600)
	rest.rest_policy = "release_required"
	for delayed: bool in [false, true]:
		var held := _judge([_event("tap", 1000), rest])
		if delayed: held.advance(3000)
		held.press(1000, 0)
		held.release(2300, 0)
		held.advance(3000)
		assert_eq(held.states[1].score, 0.0)
		var clean := _judge([_event("tap", 1000), rest])
		if delayed: clean.advance(3000)
		clean.press(1000, 0)
		clean.release(1500, 0)
		clean.advance(3000)
		assert_eq(clean.states[1].score, 1.0, "Early release before rest is still valid with delayed frame delivery")

func test_spotlight_rest_requires_correct_lane_and_wrong_then_correct_does_not_erase_mistake() -> void:
	var rest := _event("keep", 2000, "rest", 1, 3200)
	rest.rest_policy = "keep_position"
	for wrong: bool in [false, true]:
		var judge := _judge([_event("light", 1000, "switch", 1), rest])
		judge.select_position(1000, 1)
		judge.press(1000, 1)
		if wrong:
			judge.select_position(2500, -1)
			judge.select_position(2700, 1)
		judge.advance(3500)
		assert_eq(judge.states[1].score, 0.0 if wrong else 1.0)

func test_two_previews_overlap_and_hold_release_stays_visible_through_late_window() -> void:
	var task := _task("laohekou_si_xian")
	task.phase = HeritageStageTask.Phase.LIVE
	task.game_time = float(task.chart.events[4].time_ms-400)/1000.0
	var state := task.get_performance_visual_state()
	assert_gte(state.cues.size(), 2, "Both plucks are visible before the first contact")
	for id: String in ["jingzhou_hua_gu_xi", "ti_qin_xi"]:
		var hold_task := _task(id)
		hold_task.phase = HeritageStageTask.Phase.LIVE
		var ending := 0
		for e: Dictionary in hold_task.chart.events:
			if e.kind=="hold": ending=int(e.end_ms); break
		for offset: int in [-180, 0, 220]:
			hold_task.game_time = float(ending + offset) / 1000
			var hold_state := hold_task.get_performance_visual_state()
			assert_true(hold_state.release_cue, id + " " + str(offset))
			assert_gt(hold_state.cue, 0.0)

func test_hanju_direct_left_right_does_not_toggle_on_current_side_or_neutral_key() -> void:
	var task := _task("han_ju")
	for i: int in 380: _frame(task)
	_edge(task, 1, true)
	_edge(task, 1, false)
	assert_eq(task.lane, 1)
	var ghosts := task.judge.ghosts
	_edge(task, 1, true)
	_edge(task, 1, false)
	assert_eq(task.lane, 1)
	assert_eq(task.judge.ghosts, ghosts)
	_edge(task, 0, true)
	assert_eq(task.lane, 1)
	_edge(task, -1, true)
	assert_eq(task.lane, -1)

func test_new_lessons_complete_step_by_step_with_normal_keyboard_and_skip_does_not_write_completion() -> void:
	for id: String in IDS:
		var task := _task(id, false)
		var sent: Dictionary = {}
		for frame: int in 65 * 120:
			if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
			_frame(task)
			if task.phase == HeritageStageTask.Phase.PRACTICE: _play_due(task, sent)
		assert_eq(task.phase, HeritageStageTask.Phase.COUNTDOWN, id)
		assert_eq(task.game_time, 0.0, id)
		assert_false(HeritageMinigamePreferences.tutorial_done(StringName(id), 5), "Test mode never writes current completion")
	var skip := _task("ti_qin_xi", false)
	skip.skip_tutorial()
	assert_eq(skip.phase, HeritageStageTask.Phase.COUNTDOWN)
	assert_false(skip.clock.playing)
	assert_false(HeritageMinigamePreferences.tutorial_done(&"ti_qin_xi", 5))

func test_full_six_games_allow_two_misses_but_idle_hold_and_mash_do_not_pass() -> void:
	for id: String in IDS:
		for mode: String in ["normal", "two_misses", "idle", "hold", "mash"]:
			var task := _task(id)
			var results: Array[HeritageTaskResult] = []
			task.task_completed.connect(func(value: HeritageTaskResult) -> void: results.append(value))
			var sent: Dictionary = {}
			for frame: int in ceili((task.chart.end_ms/1000.0+4.0)*120):
				if task.run_state == HeritageTaskBase.RunState.FINISHED: break
				_frame(task)
				if task.phase != HeritageStageTask.Phase.LIVE: continue
				if mode in ["normal", "two_misses"]: _play_due(task, sent, 2 if mode == "two_misses" else 0)
				elif mode == "hold" and sent.is_empty():
					sent["held"] = true
					_edge(task, 0 if task.instrument in ["sing", "pluck", "drum"] else -1, true)
				elif mode == "mash" and frame % 7 == 0:
					for direction: int in [-1, 0, 1]:
						_edge(task, direction, true)
						_edge(task, direction, false)
			assert_eq(results.size(), 1, id + " " + mode)
			if not results.is_empty(): assert_eq(results[0].is_success(), mode in ["normal", "two_misses"], id + " " + mode)

func test_calibration_median_and_jitter_reject_unstable_tapping() -> void:
	var stable: Array[int] = []
	var unstable: Array[int] = []
	for i: int in 16:
		stable.append(38 + i % 3)
		unstable.append(-180 if i % 2 == 0 else 180)
	var result := HeritageBeatCalibration.summarize(stable)
	assert_true(result.stable)
	assert_eq(result.offset_ms, 39)
	assert_lte(result.spread_ms, 1)
	assert_false(HeritageBeatCalibration.summarize(unstable).stable)

func test_chart_rejects_overlap_before_it_reaches_the_player() -> void:
	var chart := load("res://InheritanceTasks/Charts/ti_qin_xi.tres").duplicate(true) as HeritageMusicChart
	chart.events.assign([_event("a", 1000, "hold", -1, 2400), _event("b", 2300, "tap", -1)])
	chart.presentation = chart.events.duplicate(true)
	assert_string_contains(chart.validate(), "重叠")
