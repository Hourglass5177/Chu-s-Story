extends GutTest

func _task(id: String, seed: int = 42, dimensions: Vector2 = Vector2(1000,600)) -> HeritageStageTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = dimensions
	var context := HeritageTaskRunContext.new(StringName(id),null,null,0,0,seed)
	context.test_mode = true
	context.metadata["skip_tutorial"] = true
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	for i: int in 361: task._process(1.0/120.0)
	return task

func _key(task: HeritageStageTask, code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	task.task_input(event)

func _tap(task: HeritageStageTask, code: Key) -> void:
	_key(task,code,true)
	_key(task,code,false)

func _tick(task: HeritageStageTask, seconds: float) -> void:
	for i: int in ceili(seconds*120.0): task._process(1.0/120.0)

func _mouse(task: HeritageStageTask, point: Vector2, down: bool) -> void:
	var factor := minf(task.size.x/1000.0,task.size.y/600.0)
	var event := InputEventMouseButton.new()
	event.position = point*factor+(task.size-Vector2(1000,600)*factor)*.5
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	if not down:
		var release := event.duplicate() as InputEventMouseButton
		release.position = task.get_global_transform_with_canvas()*event.position
		task._input(release)
	task.task_gui_input(event)

func _motion(task: HeritageStageTask, point: Vector2) -> void:
	var factor := minf(task.size.x/1000.0,task.size.y/600.0)
	var event := InputEventMouseMotion.new()
	event.position = point*factor+(task.size-Vector2(1000,600)*factor)*.5
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	task.task_gui_input(event)

func test_puzzle_exact_depth_boards_and_all_stories_complete_by_keyboard() -> void:
	var seen: Dictionary = {}
	for seed: int in range(20):
		var task := _task("xiabaoping_minjian_gushi",seed)
		if seen.has(task.story_index):
			task.queue_free()
			continue
		seen[task.story_index] = true
		var results: Array = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
		for scene: int in 3:
			assert_gte(task.puzzle_depth,10+scene*2)
			assert_lte(task.puzzle_depth,12+scene*2)
			var original_time: float = task.operation_seconds
			for action: Variant in task.candidates[scene].solution:
				_tap(task,{-1:KEY_A,1:KEY_D,-2:KEY_W,2:KEY_S}[int(action)])
				_tick(task,.15)
			assert_eq(task.completed_scenes,scene+1)
			assert_eq(task.board,task.GOAL)
			var stopped: float = task.operation_seconds
			_tick(task,2.0)
			assert_almost_eq(task.operation_seconds,stopped,.001,"Reveal does not consume the operation clock")
			_tick(task,task.reveal_left+.01)
			assert_gt(stopped,original_time)
		assert_eq(results.size(),1)
		if not results.is_empty(): assert_true(results[0].is_success())
		task.queue_free()
		if seen.size()==3: break
	assert_eq(seen.size(),3)

func test_puzzle_illegal_click_pause_resize_and_seed_stability() -> void:
	var task := _task("xiabaoping_minjian_gushi",83)
	var same := _task("xiabaoping_minjian_gushi",83,Vector2(2560,1600))
	assert_eq(task.board,same.board)
	assert_eq(task.story_index,same.story_index)
	var snapshot: Array = task.board.duplicate()
	_mouse(task,Vector2(900,580),true)
	_mouse(task,Vector2(900,580),false)
	assert_eq(task.board,snapshot)
	task.set_suspended(true)
	_tap(task,KEY_D)
	_tick(task,4.0)
	assert_eq(task.board,snapshot)
	assert_almost_eq(task.operation_seconds,0.0,.02)
	task.size = Vector2(1280,720)
	assert_eq(task.board,snapshot)
	task.set_suspended(false)
	_tick(task,1.6)
	assert_eq(task.board,snapshot)

func test_puzzle_no_input_expires_only_after_120_operation_seconds() -> void:
	var task := _task("xiabaoping_minjian_gushi")
	_tick(task,119.0)
	assert_eq(task.run_state,HeritageTaskBase.RunState.RUNNING)
	_tick(task,1.1)
	assert_eq(task.run_state,HeritageTaskBase.RunState.FINISHED)
	assert_almost_eq(task.operation_seconds,120.0,.02)

func test_paper_four_real_contours_finish_on_release_without_intermediate_frame() -> void:
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1600)]:
		var task := _task("ezhou_diaohua_jianzhi",42,dimensions)
		var results: Array = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
		for contour: int in 4:
			var path: PackedVector2Array = task.contours[contour]
			_mouse(task,path[0],true)
			for i: int in range(1,path.size()-1):
				_motion(task,path[i])
				task._process(.018)
			_mouse(task,path[-1],false)
			assert_eq(task.segment,contour+1)
			if contour==1: task.size = Vector2(1920,1080)
		assert_eq(results.size(),0,"Cut closure starts the reveal, not the result")
		var cut_clock: float = task.game_time
		task.set_suspended(true)
		_tick(task,2.0)
		assert_eq(results.size(),0,"Pause freezes the falling paper")
		assert_eq(task.game_time,cut_clock)
		task.set_suspended(false)
		_tick(task,1.51)
		_tick(task,1.1)
		assert_eq(results.size(),1)
		assert_eq(task.game_time,cut_clock,"Reveal consumes no operation time")
		assert_eq(task.detached_time,0.0)
		if not results.is_empty(): assert_true(results[0].is_success())
		_mouse(task,Vector2(0,0),false)
		_tick(task,.1)
		assert_eq(results.size(),1)
		assert_almost_eq(task.off_path_seconds,0.0,.01)

func test_paper_start_equals_end_does_not_skip_loop_or_teleport() -> void:
	var task := _task("ezhou_diaohua_jianzhi")
	var path: PackedVector2Array = task.contours[0]
	_mouse(task,path[0],true)
	_mouse(task,path[-1],false)
	assert_eq(task.segment,0)
	assert_lt(task.cut_distance,1.0)
	_mouse(task,path[0],true)
	_motion(task,path[path.size()/2])
	_mouse(task,path[-1],false)
	assert_eq(task.segment,0)
	assert_lt(task.cut_distance,task.cut_length*.7)

func test_paper_bad_geometry_is_rejected_instead_of_using_a_different_pattern() -> void:
	var pattern := preload("res://InheritanceTasks/Data/paper_cut_pattern.gd")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pattern.SOURCE))
	assert_eq(pattern.decode_contours(source).size(),4)
	var broken: Dictionary = source.duplicate(true)
	broken.contours[0][-1] = [900,900]
	assert_true(pattern.decode_contours(broken).is_empty())
	broken = source.duplicate(true)
	broken.contours[1][2] = ["wrong",3]
	assert_true(pattern.decode_contours(broken).is_empty())
	assert_true(pattern.contours("res://absent-paper-geometry.json").is_empty())

func _steer_knife(task: HeritageStageTask, goal: Vector2, joypad: bool) -> void:
	var delta: Vector2 = goal-task.pointer
	for item: Array in [[KEY_A,JOY_BUTTON_DPAD_LEFT,delta.x < -.8],[KEY_D,JOY_BUTTON_DPAD_RIGHT,delta.x > .8],[KEY_W,JOY_BUTTON_DPAD_UP,delta.y < -.8],[KEY_S,JOY_BUTTON_DPAD_DOWN,delta.y > .8]]:
		if joypad:
			var event := InputEventJoypadButton.new()
			event.button_index = item[1]
			event.pressed = item[2]
			task.task_input(event)
		else: _key(task,item[0],item[2])

func _knife_down(task: HeritageStageTask, down: bool, joypad: bool) -> void:
	if joypad:
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_A
		event.pressed = down
		task.task_input(event)
	else: _key(task,KEY_SPACE,down)

func test_paper_keyboard_and_gamepad_trace_the_actual_four_contours() -> void:
	for joypad: bool in [false,true]:
		var task := _task("ezhou_diaohua_jianzhi")
		var results: Array = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
		for index: int in 4:
			var path: PackedVector2Array = task.contours[index]
			_knife_down(task,false,joypad)
			for frame: int in 600:
				if task.pointer.distance_to(path[0])<2.2: break
				_steer_knife(task,path[0],joypad)
				task._process(1.0/120.0)
			_knife_down(task,true,joypad)
			for point: Vector2 in path:
				for frame: int in 160:
					if task.segment!=index or task.pointer.distance_to(point)<2.2: break
					_steer_knife(task,point,joypad)
					task._process(1.0/120.0)
			for frame: int in 20:
				if task.segment!=index: break
				_steer_knife(task,path[-1],joypad)
				task._process(1.0/120.0)
			_knife_down(task,false,joypad)
			assert_eq(task.segment,index+1,"Joypad=%s, distance=%s/%s"%[joypad,task.cut_distance,task.cut_length])
		_tick(task,1.1)
		assert_eq(results.size(),1)
		if not results.is_empty(): assert_true(results[0].is_success())

func _cart_drive(task: HeritageStageTask, controls: Dictionary, deliberate_miss: bool = false) -> void:
	var state: Dictionary = task.get_presentation_state()
	var brake := false
	var push := true
	if (not deliberate_miss or task.mistakes>0) and state.bridge_warning and state.bridge_distance <= state.braking_distance+70:
		brake = state.speed > 94.0
		push = state.speed < 87.0
	for row: Array in [[KEY_A,brake],[KEY_D,push]]:
		if bool(controls.get(row[0],false)) != row[1]:
			_key(task,row[0],row[1])
			controls[row[0]] = row[1]

func test_cart_contact_and_normal_input_across_crests_bridge_and_recovery() -> void:
	for deliberate_miss: bool in [false,true]:
		var task := _task("dong_yong_chuanshuo")
		var results: Array = []
		var controls: Dictionary = {}
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
		for tick: int in 31*120:
			if task.run_state==HeritageTaskBase.RunState.FINISHED: break
			_cart_drive(task,controls,deliberate_miss)
			task._process(1.0/120.0)
			if tick%30==0:
				var contacts: Dictionary = task.contact
				assert_almost_eq(contacts.axle.y+task.WHEEL_RADIUS,task.height_at(contacts.axle.x),.001)
				assert_lte(absf(contacts.handle.y-(task.height_at(task.distance-task.PUSHER_OFFSET)-70.0)),.2)
				for foot: Vector2 in contacts.feet:
					assert_lte(foot.y,task.height_at(foot.x)+.01)
					assert_gte(foot.y,task.height_at(foot.x)-10.01)
		assert_eq(results.size(),1)
		if not results.is_empty(): assert_true(results[0].is_success(),str(results[0].metrics))
		assert_eq(task.mistakes,1 if deliberate_miss else 0)
		if not deliberate_miss: assert_between(task.game_time,23.0,27.0)

func _escort_drive(task: HeritageStageTask, maximum_only: bool = false) -> void:
	preload("res://tests/support/action_story_input.gd").escort(task,maximum_only)

func test_cart_analog_trigger_has_proportional_push_and_brake_priority() -> void:
	var half := _task("dong_yong_chuanshuo")
	var full := _task("dong_yong_chuanshuo")
	for task: HeritageStageTask in [half,full]:
		var trigger := InputEventJoypadMotion.new()
		trigger.axis = JOY_AXIS_TRIGGER_RIGHT
		trigger.axis_value = .5 if task==half else 1.0
		task.task_input(trigger)
		_tick(task,.6)
	assert_gt(half.speed,0.0)
	assert_lt(half.speed,full.speed*.65)
	var old: float = full.speed
	var brake := InputEventJoypadMotion.new()
	brake.axis = JOY_AXIS_TRIGGER_LEFT
	brake.axis_value = .5
	full.task_input(brake)
	_tick(full,.2)
	assert_lt(full.speed,old,"A half brake wins over a held full push")

func test_escort_visible_route_with_delayed_normal_input() -> void:
	var task := _task("xisai_shenzhou_hui")
	var results: Array = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	for tick: int in 36*120:
		if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		_escort_drive(task)
		task._process(1.0/120.0)
	assert_eq(results.size(),1)
	if not results.is_empty(): assert_true(results[0].is_success(),str(results[0].metrics))
	assert_eq(task.collisions,0)
	assert_between(task.game_time,26.0,29.5)

func test_escort_full_speed_has_reaction_margin_but_no_steering_fails() -> void:
	var task := _task("xisai_shenzhou_hui")
	for tick: int in 36*120:
		if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		_escort_drive(task,true)
		task._process(1.0/120.0)
	assert_eq(task.collisions,0,"Even at full speed, 450ms delayed decisions must have a clear route")
	assert_gte(task.distance,task.Route.LENGTH)
	var straight := _task("xisai_shenzhou_hui")
	_tap(straight,KEY_W)
	_tick(straight,35.2)
	assert_lt(straight.distance,straight.Route.LENGTH,"Speed alone cannot replace steering")
	var idle := _task("xisai_shenzhou_hui")
	_tick(idle,35.2)
	assert_lt(idle.distance,idle.Route.LENGTH)

func test_escort_recovers_from_two_mistakes_using_normal_input() -> void:
	var task := _task("xisai_shenzhou_hui")
	var results: Array = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	for tick: int in 36*120:
		if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		if task.collisions==0 and task.distance<790:
			# Deliberately remain in the first boat's lane.
			if task.target_lane!=1: _tap(task,KEY_D if task.target_lane<1 else KEY_A)
			if task.target_speed<180: _tap(task,KEY_W)
		elif task.collisions==1 and task.distance<1240:
			# The next row blocks the outer lanes; ignore the safe middle once.
			if task.target_lane!=0: _tap(task,KEY_A)
			if task.target_speed<180: _tap(task,KEY_W)
		else: _escort_drive(task)
		task._process(1.0/120.0)
	assert_eq(task.collisions,2)
	assert_eq(results.size(),1)
	if not results.is_empty(): assert_true(results[0].is_success(),str(results[0].metrics))

func test_escort_either_initial_outer_lane_can_rejoin_with_reaction_delay() -> void:
	for initial_key: Key in [KEY_A,KEY_D]:
		var task := _task("xisai_shenzhou_hui")
		_tap(task,initial_key)
		for frame: int in 36*120:
			if task.run_state == HeritageTaskBase.RunState.FINISHED: break
			_escort_drive(task,true)
			task._process(1.0/120.0)
		assert_eq(task.collisions,0)
		assert_gte(task.distance,task.Route.LENGTH)

func test_escort_swept_collision_checks_between_samples() -> void:
	var route := preload("res://InheritanceTasks/Data/shenzhou_escort_route.gd")
	assert_true(route.swept_hit(Vector2(0,600),Vector2(2,700),{"lane":1,"distance":650.0}))
	assert_false(route.swept_hit(Vector2(0,600),Vector2(0,700),{"lane":1,"distance":650.0}))
