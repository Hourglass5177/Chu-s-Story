extends GutTest

func test_chart_validation_and_timestamp_judgment() -> void:
	for name: String in ["tujia_saye_erhe","laohekou_si_xian","jingzhou_hua_gu_xi","han_ju","ti_qin_xi","gu_pen_ge"]:
		var chart := load("res://InheritanceTasks/Charts/%s.tres" % name) as HeritageMusicChart
		assert_eq(chart.validate(), "", name)
		assert_eq(FileAccess.get_sha256(chart.audio_path), chart.audio_sha256)
		for fps: int in [30,60,144]:
			var judge := HeritageMusicJudge.new()
			judge.configure(chart)
			var next_frame: int = 0
			for e: Dictionary in chart.events:
				while next_frame < int(e.time_ms):
					judge.advance(next_frame)
					next_frame += roundi(1000.0/fps)
				if e.kind != "rest":
					assert_true(judge.press(int(e.time_ms), int(e.direction)))
					if e.kind == "switch": judge.select_position(int(e.time_ms), int(e.direction))
					judge.release(int(e.end_ms) if e.kind == "hold" else int(e.time_ms) + 50, int(e.direction))
			judge.advance(chart.end_ms)
			assert_almost_eq(judge.score(), 1.0, 0.0001, "%s at %d fps" % [name,fps])
		var idle := HeritageMusicJudge.new()
		idle.configure(chart)
		idle.advance(chart.end_ms)
		assert_lte(idle.score(), 0.2)
		var mash := HeritageMusicJudge.new()
		mash.configure(chart)
		for t: int in range(0,chart.end_ms,50): mash.press(t, -1 if t%100==0 else 1)
		mash.advance(chart.end_ms)
		assert_lt(mash.score(), 0.7)

func test_judgment_boundaries_and_one_edge_one_event() -> void:
	var chart := HeritageMusicChart.new()
	chart.events = [{"id":"a","time_ms":1000,"end_ms":1000,"direction":0,"kind":"tap"}, {"id":"b","time_ms":1200,"end_ms":2200,"direction":0,"kind":"hold"}]
	var judge := HeritageMusicJudge.new()
	judge.configure(chart)
	assert_true(judge.press(820,0))
	assert_false(judge.states[1].started)
	assert_true(judge.press(1200,0))
	assert_true(judge.release(2420,0))
	assert_almost_eq(judge.score(),.86,.00001,"Boundary hits are Good: tap .8 and hold .3 + .3 + .4*.8")
	judge.configure(chart)
	assert_false(judge.press(819,0))
	assert_true(judge.press(1200,0))
	assert_false(judge.release(1800,0))
	assert_lt(judge.score(),0.7)

func test_platform_normal_input_finishes_at_all_sizes() -> void:
	var driver := preload("res://tools/heritage_motion_input_driver.gd")
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1600)]:
		var task := _task("yandi_shennong_chuanshuo",dimensions)
		var result: Array[HeritageTaskResult] = []
		task.task_completed.connect(func(r: HeritageTaskResult) -> void: result.append(r))
		var controls: Dictionary = {}
		for frame: int in 45*120:
			if task.run_state == HeritageTaskBase.RunState.FINISHED: break
			driver.platform(task,1.0/120.0,controls)
			if frame==600: task.size=dimensions*0.8
			task._process(1.0/120.0)
		assert_eq(result.size(),1,str(dimensions))
		if not result.is_empty(): assert_eq(result[0].status,HeritageTaskResult.Status.SUCCESS, str(result[0].metrics))
		task.queue_free()

func test_action_games_normal_input_and_no_input() -> void:
	var driver := preload("res://tools/heritage_motion_input_driver.gd")
	for id: String in ["xia_lian_dan_shu","dong_yong_chuanshuo"]:
		for controlled: bool in [true,false]:
			var task := _task(id)
			var results: Array[HeritageTaskResult] = []
			task.task_completed.connect(func(r: HeritageTaskResult) -> void: results.append(r))
			for frame: int in 32*120:
				if task.run_state == HeritageTaskBase.RunState.FINISHED: break
				if controlled:
					if id == "xia_lian_dan_shu":
						_edge(task,&"ui_accept",float(task.get("heat"))+float(task.get("velocity"))*0.13<float(task.get("target")))
					else:
						driver.cart(task)
				task._process(1.0/120.0)
			assert_eq(results.size(),1,id)
			if not results.is_empty():
				assert_eq(results[0].is_success(),controlled,"%s %s" % [id,results[0].metrics])

func test_story_three_exact_depth_puzzles_complete_with_keyboard() -> void:
	var task := _task("xiabaoping_minjian_gushi")
	var driver := preload("res://tests/support/action_story_input.gd")
	var results: Array = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	for scene: int in 3:
		driver.solve_scene(task)
		assert_eq(task.get("completed_scenes"),scene+1)
		driver.tick(task,task.get("reveal_left")+.01)
	assert_eq(results.size(),1)
	if not results.is_empty(): assert_true(results[0].is_success())

func _story_input_contract() -> StringName:
	return &"puzzle"

func test_pause_countdown_rejects_input_and_preserves_music_position() -> void:
	var task := _task("tujia_saye_erhe") as HeritagePerformanceTask
	task.set_suspended(true)
	var time: float=task.clock.seconds()
	_edge(task,&"ui_left",true)
	task._process(1)
	assert_eq(task.clock.seconds(),time)
	assert_eq(task.judge.ghosts,0)
	task.set_suspended(false)
	_edge(task,&"ui_right",true)
	task._process(0.5)
	assert_eq(task.clock.seconds(),time)
	assert_eq(task.judge.ghosts,0)

func test_pointer_release_outside_stage_clears_hold() -> void:
	var task := _task("xia_lian_dan_shu")
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.position=Vector2(500,400)
	event.pressed=true
	assert_true(task.task_gui_input(event))
	assert_true(task.pressed[0])
	event.position=Vector2(-100,-100)
	event.pressed=false
	assert_true(task.task_gui_input(event))
	assert_false(task.pressed[0])

func test_live_challenge_cannot_restart_to_evade_attempt_cost() -> void:
	var task := _task("xia_lian_dan_shu")
	var time: float=task.game_time
	task.restart_lesson()
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	assert_eq(task.game_time,time)

func test_interactive_lesson_freezes_challenge_time_and_ignores_echo() -> void:
	# Install the controlled source before start_task. The generic _task helper
	# advances 3.1 simulated seconds to leave action-game countdowns; doing that
	# against real audio can correctly trigger the playback-stall error before
	# this lesson fixture has a chance to replace the clock.
	var task := load("res://InheritanceTasks/Tasks/tujia_saye_erhe.tscn").instantiate() as HeritagePerformanceTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000,600)
	var manual_clock := preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock.new()
	task.clock = manual_clock
	task.add_child(manual_clock)
	var context := HeritageTaskRunContext.new(&"tujia_saye_erhe")
	context.test_mode = true
	context.metadata["skip_tutorial"] = false
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	assert_eq(task.run_state,HeritageTaskBase.RunState.RUNNING)
	assert_eq(task.phase,HeritageStageTask.Phase.DEMO)
	var challenge_time_left: float = task.time_left
	for frame: int in 1000:
		if task.phase == HeritageStageTask.Phase.PRACTICE: break
		manual_clock.elapse(0.01)
		task._process(0.01)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	assert_eq(task.run_state,HeritageTaskBase.RunState.RUNNING)
	assert_eq(task.game_time,0.0)
	assert_eq(task.time_left,challenge_time_left)
	var echo := InputEventKey.new()
	echo.keycode=KEY_LEFT
	echo.pressed=true
	echo.echo=true
	task.task_input(echo)
	assert_eq(task.lesson_judge.ghosts,0)
	assert_false(task.pressed[-1],"Keyboard repeat cannot start a practice step.")
	assert_false(task.lesson_judge.states[0].started)
	var sent: Dictionary = {}
	var practiced_steps: Dictionary = {}
	for frame: int in 5000:
		if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
		manual_clock.elapse(0.01)
		task._process(0.01)
		# Each concept now has its own demonstration and practice clock. Do not
		# inject inputs while a new concept is being demonstrated.
		if task.phase != HeritageStageTask.Phase.PRACTICE: continue
		practiced_steps[task.lesson_step] = true
		var ms: int = task._judgment_ms()
		for event: Dictionary in task.lesson_chart.events:
			if event.kind == "rest" or sent.has(event.id) or ms < int(event.time_ms): continue
			var direction: StringName = &"ui_left" if int(event.direction) < 0 else &"ui_right"
			sent[event.id] = true
			_edge(task,direction,true)
			_edge(task,direction,false)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	assert_eq(practiced_steps.size(),2,"Alternating feet and a repeated-side group each have their own excerpt.")
	assert_eq(sent.size(),5,"Two alternating steps, then a left-right-right group.")
	assert_almost_eq(task.lesson_judge.score(),1.0,0.00001,"The final group completes the lesson.")
	assert_eq(task.game_time,0.0)
	assert_eq(task.time_left,challenge_time_left)
	for frame: int in 310: task._process(0.01)
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	task.task_input(echo)
	assert_eq(task.judge.ghosts,0)

func test_two_misses_are_recoverable_in_each_music_chart() -> void:
	for name: String in ["tujia_saye_erhe","laohekou_si_xian","jingzhou_hua_gu_xi","han_ju","ti_qin_xi"]:
		var chart := load("res://InheritanceTasks/Charts/%s.tres" % name) as HeritageMusicChart
		var judge := HeritageMusicJudge.new()
		judge.configure(chart)
		var missed: int=0
		for e: Dictionary in chart.events:
			if e.kind=="rest": continue
			if missed<2:
				missed+=1
				continue
			judge.press(int(e.time_ms),int(e.direction))
			if e.kind=="hold": judge.release(int(e.end_ms),int(e.direction))
		judge.advance(chart.end_ms)
		assert_gte(judge.score(),0.7,name)

func test_exit_settlement_precedes_return_for_all_fifteen_tasks() -> void:
	for file: String in DirAccess.get_files_at("res://InheritanceTasks/Definitions"):
		if not file.ends_with(".tres"): continue
		var definition := load("res://InheritanceTasks/Definitions/"+file) as HeritageTaskDefinition
		var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		add_child_autofree(host)
		var order: Array[String]=[]
		host.task_finished.connect(func(_r: HeritageTaskResult) -> void: order.append("settled"))
		host.return_requested.connect(func() -> void: order.append("returned"))
		var context := HeritageTaskRunContext.new(definition.task_id)
		context.test_mode=true
		context.forced_outcome=HeritageTaskResult.Status.MANUAL_ABORT
		host.configure(definition,context)
		host.begin()
		host.start_from_preparation()
		await wait_process_frames(2)
		assert_eq(order,["settled","returned"],file)
		assert_false(host.result_panel.visible)

func test_host_focus_loss_and_real_tutorial_exit() -> void:
	var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	add_child_autofree(host)
	var definition := load("res://InheritanceTasks/Definitions/tujia_saye_erhe.tres") as HeritageTaskDefinition
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode=true
	host.configure(definition,context)
	host.begin()
	host.start_from_preparation(true)
	var task := host.active_task as HeritagePerformanceTask
	assert_eq(task.phase,HeritageStageTask.Phase.DEMO)
	host._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(task.run_state,HeritageTaskBase.RunState.SUSPENDED)
	var before: float=task.phase_time
	task._process(1.0)
	assert_eq(task.phase_time,before)
	host._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_gt(task.resume_countdown,0.0)
	watch_signals(host)
	host._show_exit_confirm()
	host._confirm_abort()
	assert_signal_emit_count(host,"task_finished",1)
	assert_signal_emit_count(host,"return_requested",1)
	assert_false(host.result_panel.visible)
	assert_false(task.clock.playing)

func test_missing_music_is_technical_error_before_discovery() -> void:
	var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	add_child_autofree(host)
	var definition := (load("res://InheritanceTasks/Definitions/tujia_saye_erhe.tres") as HeritageTaskDefinition).duplicate(true) as HeritageTaskDefinition
	definition.music_chart.audio_path="res://InheritanceTasks/Audio/absent-source.ogg"
	watch_signals(host)
	host.configure(definition,HeritageTaskRunContext.new(definition.task_id))
	host.begin()
	host.start_from_preparation()
	assert_signal_not_emitted(host,"task_entered")
	assert_signal_emit_count(host,"task_finished",1)
	var params: Array=get_signal_parameters(host,"task_finished",0)
	assert_eq((params[0] as HeritageTaskResult).status,HeritageTaskResult.Status.TECHNICAL_ERROR)

func _task(id: String, dimensions: Vector2 = Vector2(1000,600), skip_tutorial: bool = true) -> HeritageStageTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = dimensions
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = skip_tutorial
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	for i: int in 310: task._process(0.01)
	return task

func _edge(task: HeritageTaskBase, action: StringName, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	task.task_input(event)
