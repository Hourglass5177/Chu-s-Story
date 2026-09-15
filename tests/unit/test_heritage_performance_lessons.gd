extends GutTest

## 音乐时间由测试时钟提供，输入仍走控制器的普通 InputEvent 入口。
## 这些用例验证教学与判定契约，不作为真实音频听审记录。
const TASKS: Array[String] = ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]

class ManualMusicClock extends HeritageMusicClock:
	var source_time: float = 0.0
	var frozen: bool = false
	func begin(audio: AudioStream) -> void:
		source_time = 0.0
		frozen = false
		super.begin(audio)
	func seconds() -> float:
		return source_time
	func freeze(value: bool) -> void:
		frozen = value
		stream_paused = value
	func elapse(delta: float) -> void:
		if frozen or not playing: return
		source_time += delta
		if stream != null and source_time >= stream.get_length():
			source_time = stream.get_length()
			stop()

func before_all() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://performance-lesson-test.cfg")

func after_all() -> void:
	HeritageMinigamePreferences.configure_storage_path()

func test_each_game_demonstrates_with_audio_then_requires_timed_inputs() -> void:
	for id: String in TASKS:
		var task := _task(id)
		assert_eq(task.phase, HeritageStageTask.Phase.DEMO, id)
		assert_true(task.clock.playing, "The demonstration has its source audio: " + id)
		_drive(task, float(task.lesson_chart.end_ms) / 1000.0 + 0.1)
		assert_eq(task.phase, HeritageStageTask.Phase.PRACTICE, id)
		assert_eq(task.game_time, 0.0, "The official clock has not started: " + id)
		for tap: int in 3: _press(task, &"ui_accept")
		assert_eq(task.phase, HeritageStageTask.Phase.PRACTICE, "Three arbitrary presses do not complete teaching: " + id)

func test_all_six_lessons_complete_with_normal_timed_input() -> void:
	for id: String in TASKS:
		var task := _task(id)
		var sent: Dictionary = {}
		for frame: int in 65 * 120:
			if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
			_frame(task)
			if task.phase == HeritageStageTask.Phase.PRACTICE: _play_due(task, task.lesson_judge, sent)
		assert_eq(task.phase, HeritageStageTask.Phase.COUNTDOWN, id + " " + str(task.lesson_judge.score()))
		assert_eq(task.game_time, 0.0, id)
		assert_eq(task.lesson_judge.ghosts, 0, id)

func test_mashing_does_not_complete_any_lesson() -> void:
	for id: String in TASKS:
		var task := _task(id)
		for frame: int in 24 * 120:
			_frame(task)
			if task.phase == HeritageStageTask.Phase.PRACTICE and frame % 6 == 0:
				for action: StringName in [&"ui_left", &"ui_right", &"ui_accept"]: _press(task, action)
		assert_ne(task.phase, HeritageStageTask.Phase.COUNTDOWN, id)
		assert_gte(task.lesson_round, 1, id)

func test_early_or_missing_hold_release_repeats_only_the_current_step() -> void:
	for id: String in ["jingzhou_hua_gu_xi", "ti_qin_xi"]:
		for mode: String in ["early", "never"]:
			var task := _task(id)
			var sent: Dictionary = {}
			for frame: int in 50 * 120:
				if task.lesson_step == 1 and task.lesson_round > 0: break
				_frame(task)
				if task.phase == HeritageStageTask.Phase.PRACTICE: _play_due(task, task.lesson_judge, sent, mode)
			assert_eq(task.lesson_step, 1, id + " " + mode)
			assert_eq(task.phase, HeritageStageTask.Phase.PRACTICE, id + " " + mode)
			assert_gte(task.lesson_round, 1, id + " " + mode)

func test_hold_pause_freezes_music_and_reconnects_after_resume_countdown() -> void:
	var task := _task("jingzhou_hua_gu_xi", true)
	_drive(task, 3.1)
	var hold: Dictionary = task.chart.events[0]
	while task.clock.seconds() < float(hold.time_ms) / 1000.0: _frame(task)
	_edge(task, &"ui_accept", true)
	_drive(task, 0.35)
	assert_true(task.judge.states[0].down)
	task.set_suspended(true)
	var before: float = task.clock.seconds()
	var points: float = task.judge.score()
	_press(task, &"ui_accept")
	_drive(task, 4.0)
	assert_eq(task.clock.seconds(), before)
	assert_eq(task.judge.score(), points)
	assert_true(task.judge.paused)
	task.set_suspended(false)
	_drive(task, 1.5)
	assert_eq(task.clock.seconds(), before)
	_frame(task)
	_edge(task, &"ui_accept", true)
	assert_true(task.judge.states[0].down)
	assert_eq(task.judge.score(), points)
	while task.clock.seconds() < float(hold.end_ms) / 1000.0: _frame(task)
	_edge(task, &"ui_accept", false)
	assert_eq(task.judge.states[0].score, 1.0)

func test_spotlight_changes_only_on_direct_input_and_actor_motion_is_independent() -> void:
	var task := _task("han_ju", true)
	_drive(task, 3.1)
	while task.clock.seconds() < float(task.chart.events[0].time_ms)/1000.0: _frame(task)
	var state := task.get_performance_visual_state()
	assert_eq(state.lane, -1)
	assert_eq(state.actor_lane, 1)
	assert_false(state.light_on_actor)
	_press(task, &"ui_right")
	assert_eq(task.lane, 1)
	state = task.get_performance_visual_state()
	assert_true(state.light_on_actor)
	assert_eq(state.stage_theme, &"auditorium_followspot")

func test_current_full_charts_can_finish_with_normal_input_and_visual_aid_does_not_change_score() -> void:
	for id: String in TASKS:
		var scores: Array[float] = []
		for visual_aid: bool in [false, true]:
			var task := _task(id, true)
			task.visual_assistance = visual_aid
			var sent: Dictionary = {}
			var results: Array[HeritageTaskResult] = []
			task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
			for frame: int in 50 * 120:
				if task.run_state == HeritageTaskBase.RunState.FINISHED: break
				_frame(task)
				if task.phase == HeritageStageTask.Phase.LIVE: _play_due(task, task.judge, sent)
			assert_eq(results.size(), 1, id)
			if not results.is_empty(): assert_true(results[0].is_success(), id)
			scores.append(task.judge.score())
		assert_almost_eq(scores[0], scores[1], 0.00001, id)

func test_short_lesson_eof_finishes_only_after_scoring_tail() -> void:
	var task := _task("jingzhou_hua_gu_xi")
	task.clock.stop()
	var end := task.lesson_chart.end_ms
	assert_true(task._lesson_audio_finished(end - 100), "Output buffer latency must not stall a completed excerpt")
	assert_false(task._lesson_audio_finished(end - 400), "Early playback loss is not successful completion")
	var last: Dictionary = task.lesson_chart.events.back().duplicate(true)
	last.kind = "hold"
	last.end_ms = end - 150
	task.lesson_chart.events.append(last)
	assert_false(task._lesson_audio_finished(end - 100), "Do not skip an open hold-release judgment window")

func _task(id: String, skip_tutorial: bool = false) -> HeritagePerformanceTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritagePerformanceTask
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child_autofree(task)
	task.size = Vector2(1000, 600)
	task.clock = ManualMusicClock.new()
	task.add_child(task.clock)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = skip_tutorial
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	return task

func _frame(task: HeritagePerformanceTask) -> void:
	(task.clock as ManualMusicClock).elapse(1.0 / 120.0)
	task._process(1.0 / 120.0)

func _drive(task: HeritagePerformanceTask, seconds: float) -> void:
	for frame: int in roundi(seconds * 120.0): _frame(task)

func _play_due(task: HeritagePerformanceTask, active_judge: HeritageMusicJudge, sent: Dictionary, hold_mode: String = "normal") -> void:
	var ms: int = roundi(task.clock.seconds() * 1000.0)
	for source_event: Dictionary in active_judge.events:
		var event: Dictionary = source_event.duplicate()
		event.id = str(event.id) + ":" + str(task.lesson_round)
		if event.kind == "rest": continue
		var direction: int = int(event.direction)
		if task.instrument in ["pluck", "sing", "drum"]: direction = 0
		var action: StringName = &"ui_left" if direction < 0 else (&"ui_right" if direction > 0 else &"ui_accept")
		if ms >= int(event.time_ms) and not sent.has(event.id):
			sent[event.id] = true
			_edge(task, action, true)
		var release_ms: int = int(event.end_ms) if event.kind == "hold" else int(event.time_ms) + 50
		if event.kind == "hold" and hold_mode == "early": release_ms -= 400
		if event.kind == "hold" and hold_mode == "never": continue
		if ms >= release_ms and not sent.has(str(event.id) + "-up"):
			sent[str(event.id) + "-up"] = true
			_edge(task, action, false)

func _press(task: HeritagePerformanceTask, action: StringName) -> void:
	_edge(task, action, true)
	_edge(task, action, false)

func _edge(task: HeritagePerformanceTask, action: StringName, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	task.task_input(event)
