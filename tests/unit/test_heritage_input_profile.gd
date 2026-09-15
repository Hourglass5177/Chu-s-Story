extends GutTest

const Profile := preload("res://InheritanceTasks/Common/heritage_input_profile.gd")

func _key(code: int, down: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	event.echo = echo
	return event

func _task(id: String, skip: bool = true) -> HeritageStageTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000,600)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = skip
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	if skip:
		for i: int in 361: task._process(1.0/120.0)
	return task

func test_overlapping_keys_and_mouse_have_one_aggregated_hold() -> void:
	var profile := Profile.new(&"heat")
	var edges: Array = []
	profile.action_edge.connect(func(direction: int,down: bool) -> void: edges.append([direction,down]))
	profile.route_event(_key(KEY_SPACE,true))
	profile.route_event(_key(KEY_ENTER,true))
	profile.pointer_edge(0,true)
	profile.route_event(_key(KEY_SPACE,false))
	profile.route_event(_key(KEY_ENTER,false))
	assert_true(profile.held(0),"Mouse still holds the same action after both keys release.")
	assert_eq(edges,[[0,true]])
	profile.pointer_edge(0,false)
	assert_eq(edges,[[0,true],[0,false]])
	assert_eq(profile.device,&"mouse")

func test_repeats_are_ignored_and_new_press_after_clear_is_accepted() -> void:
	var profile := Profile.new(&"platform")
	var edges: Array = []
	profile.action_edge.connect(func(direction: int,down: bool) -> void: edges.append([direction,down]))
	profile.route_event(_key(KEY_D,true))
	profile.route_event(_key(KEY_D,true,true))
	profile.route_event(_key(KEY_RIGHT,true))
	profile.route_event(_key(KEY_D,false))
	assert_eq(edges,[[1,true]])
	profile.clear()
	assert_false(profile.held(1))
	profile.route_event(_key(KEY_RIGHT,false))
	assert_eq(edges,[[1,true]],"Clearing ownership does not synthesize a gameplay release.")
	profile.route_event(_key(KEY_D,true))
	assert_eq(edges,[[1,true],[1,true]])

func test_gamepad_axis_hysteresis_and_device_prompts_ignore_drift() -> void:
	var profile := Profile.new(&"platform")
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 0.12
	profile.route_event(event)
	assert_eq(profile.device,&"keyboard")
	assert_false(profile.held(1))
	event.axis_value = 0.5
	profile.route_event(event)
	assert_eq(profile.device,&"gamepad")
	assert_true(profile.held(1))
	event.axis_value = 0.3
	profile.route_event(event)
	assert_true(profile.held(1))
	event.axis_value = 0.1
	profile.route_event(event)
	assert_false(profile.held(1))
	profile.route_event(_key(KEY_A,true))
	assert_eq(profile.device,&"keyboard")
	assert_has(profile.control_hints()[0].glyphs,"key_a")

func test_shennong_wasd_space_aliases_and_pause_clear() -> void:
	var task := _task("yandi_shennong_chuanshuo")
	assert_true(task.task_input(_key(KEY_D,true)))
	for i: int in 40: task._process(1.0/120.0)
	assert_gt(task.get("_player_position").x,100.0)
	task.task_input(_key(KEY_W,true))
	task.task_input(_key(KEY_SPACE,true))
	for i: int in 10: task._process(1.0/120.0)
	task.task_input(_key(KEY_W,false))
	assert_true(task.pressed[0],"Space keeps the jump held when W releases.")
	assert_false(task.get("_jump_cut"))
	task.task_input(_key(KEY_SPACE,false))
	assert_true(task.get("_jump_cut"))
	task.set_suspended(true)
	assert_false(task.pressed[1])
	assert_false(task.input_profile.has_pressed_sources())
	task.set_suspended(false)
	task.task_input(_key(KEY_A,true))
	assert_false(task.pressed[-1],"Resume countdown rejects gameplay input.")

func test_shennong_mouse_move_hold_and_independent_right_button_jump() -> void:
	var task := _task("yandi_shennong_chuanshuo")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(245,540)
	mouse.pressed = true
	assert_true(task.task_gui_input(mouse))
	for i: int in 35: task._process(1.0/120.0)
	mouse.button_index = MOUSE_BUTTON_RIGHT
	assert_true(task.task_gui_input(mouse))
	for i: int in 8: task._process(1.0/120.0)
	assert_true(task.pressed[1])
	assert_true(task.pressed[0])
	assert_lt(task.get("_velocity").y,0.0)
	mouse.pressed = false
	assert_true(task.task_gui_input(mouse))
	assert_true(task.pressed[1])
	assert_true(task.get("_jump_cut"))
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(-50,-50)
	assert_true(task.task_gui_input(mouse))
	assert_false(task.pressed[1],"Release outside the stage clears movement.")

func test_mouse_controls_appear_for_deliberate_motion_and_hide_for_keyboard() -> void:
	var task := _task("yandi_shennong_chuanshuo")
	for button: Button in task.get("_mouse_controls"): assert_false(button.visible)
	var motion := InputEventMouseMotion.new()
	for i: int in 10:
		motion.relative = Vector2(0.5 if i % 2 == 0 else -0.5,0)
		task.task_gui_input(motion)
	assert_eq(task.get_input_device(),&"keyboard","Small back-and-forth cursor noise does not change the prompt family.")
	motion.relative = Vector2(20,0)
	task.task_gui_input(motion)
	assert_eq(task.get_input_device(),&"mouse")
	for button: Button in task.get("_mouse_controls"):
		assert_true(button.visible)
		assert_gte(button.size.y,48.0)
		assert_gte(button.get_theme_font_size("font_size"),24)
	task.task_input(_key(KEY_D,true))
	for button: Button in task.get("_mouse_controls"): assert_false(button.visible)

func test_heat_lesson_requires_tracking_then_real_release() -> void:
	var task := _task("xia_lian_dan_shu",false)
	for i: int in 301: task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	for i: int in 3:
		task.task_input(_key(KEY_SPACE,true))
		task.task_input(_key(KEY_SPACE,false))
	assert_false(task.lesson_caught)
	task.task_input(_key(KEY_SPACE,true))
	for i: int in 300:
		task._process(1.0/120.0)
		if task.lesson_caught: break
	assert_true(task.lesson_caught)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	task.task_input(_key(KEY_SPACE,false))
	for i: int in 100:
		task._process(1.0/120.0)
		if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	assert_eq(task.game_time,0.0)
	assert_eq(task.tutorial_version(),4)

func _play_heat(mode: String) -> Dictionary:
	var task := _task("xia_lian_dan_shu")
	var results: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	var operator_down := false
	var input_edges := 0
	var mistakes: Array[float] = [4.0,9.5,18.5]
	var miss_peak_errors: Array[float] = [0.0,0.0,0.0]
	for frame: int in 3100:
		if task.run_state == HeritageTaskBase.RunState.FINISHED: break
		var down := false
		if mode in ["normal","three_mistakes"]:
			if frame % 14 == 0:
				var predicted := float(task.heat)+float(task.velocity)*0.13
				if operator_down and predicted > float(task.target)+0.025: operator_down = false
				elif not operator_down and predicted < float(task.target)-0.025: operator_down = true
			down = operator_down
			if mode == "three_mistakes":
				for start: float in mistakes:
					if task.game_time >= start and task.game_time < start+0.55: down = false
		elif mode == "hold": down = true
		elif mode == "mash": down = frame % 24 < 12
		if bool(task.pressed[0]) != down: input_edges += 1
		task.task_input(_key(KEY_SPACE,down))
		task._process(1.0/120.0)
		if mode == "three_mistakes":
			for i: int in mistakes.size():
				if task.game_time >= mistakes[i] and task.game_time < mistakes[i]+0.85:
					miss_peak_errors[i] = maxf(miss_peak_errors[i],absf(task.heat-task.target))
	assert_eq(results.size(),1)
	return {"success":results[0].is_success(),"brew":task.brew,"seconds":task.game_time,"input_edges":input_edges,"miss_peak_errors":miss_peak_errors} if not results.is_empty() else {}

func test_heat_normal_and_three_small_mistakes_can_finish_but_mashing_cannot() -> void:
	for mode: String in ["normal","three_mistakes","idle","hold","mash"]:
		var result := _play_heat(mode)
		assert_eq(result.get("success"),mode in ["normal","three_mistakes"],"%s: %s" % [mode,result])
		if mode in ["normal","three_mistakes"]: assert_lte(int(result.get("input_edges",1000)),200)
		if mode == "three_mistakes":
			for peak: float in result.miss_peak_errors: assert_gt(peak,0.075,"Each injected mistake must actually leave the target band.")
		print("HEAT_V3_STRATEGY ",mode," ",JSON.stringify(result))
