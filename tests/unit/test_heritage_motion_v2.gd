extends GutTest

const Driver = preload("res://tools/heritage_motion_input_driver.gd")

func _task(id: String, dimensions: Vector2 = Vector2(1000,600), skip: bool = true) -> HeritageStageTask:
	var task := load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = dimensions
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

func _run(id: String, dimensions: Vector2, mistake: bool = false, idle: bool = false, hold: bool = false) -> Dictionary:
	var task := _task(id,dimensions)
	var results: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	var controls: Dictionary = {}
	for frame: int in 46*120:
		if task.run_state == HeritageTaskBase.RunState.FINISHED: break
		if not idle:
			if hold:
				Driver.edge(task,&"ui_right",true)
				Driver.edge(task,&"ui_accept",true)
			elif id == "yandi_shennong_chuanshuo": Driver.platform(task,1.0/120.0,controls,mistake)
			else: Driver.cart(task,mistake)
		if frame == 720: task.size = dimensions * 0.8
		task._process(1.0/120.0)
	assert_eq(results.size(),1,id)
	if results.is_empty(): return {}
	return {"status":results[0].status,"metrics":results[0].metrics,"time":task.game_time,
		"position":task.get("_player_position") if id == "yandi_shennong_chuanshuo" else Vector2(task.get("distance"),0)}

func test_platform_route_normal_input_at_three_sizes_and_during_resize() -> void:
	for size: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1600)]:
		var result := _run("yandi_shennong_chuanshuo",size)
		assert_eq(result.get("status"),HeritageTaskResult.Status.SUCCESS,str(result))
		assert_gte(result.get("time",0.0),32.0,str(result))
		assert_lte(result.get("time",50.0),40.0,str(result))
		assert_eq(result.get("metrics",{}).get("falls"),0,str(result))

func test_platform_one_mistake_recovers_before_deadline() -> void:
	var result := _run("yandi_shennong_chuanshuo",Vector2(1280,720),true)
	assert_eq(result.get("status"),HeritageTaskResult.Status.SUCCESS,str(result))
	assert_eq(result.get("metrics",{}).get("falls"),1,str(result))
	assert_lte(result.get("time",50.0),45.0)

func test_platform_geometry_and_original_physics_contract() -> void:
	var task := _task("yandi_shennong_chuanshuo")
	assert_eq(task.GRAVITY,1150.0)
	assert_eq(task.JUMP_SPEED,470.0)
	assert_eq(task.MOVE_SPEED,245.0)
	var floors: Array = task.get("_platforms")
	for i: int in range(1,floors.size()):
		var rise: float = floors[i-1].position.y - floors[i].position.y
		assert_lte(rise,task.MAX_JUMP_HEIGHT*0.75)
		assert_gte(floors[i].size.x,250.0)
	assert_gt(task.get("_goal").position.x,7800.0)

func test_platform_idle_or_holding_without_new_jumps_cannot_win() -> void:
	for hold: bool in [false,true]:
		var result := _run("yandi_shennong_chuanshuo",Vector2(1000,600),false,not hold,hold)
		assert_eq(result.get("status"),HeritageTaskResult.Status.FAILURE,str(result))

func test_cart_normal_input_and_one_mistake_at_all_sizes() -> void:
	for size: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1600)]:
		for mistake: bool in [false,true]:
			var result := _run("dong_yong_chuanshuo",size,mistake)
			assert_eq(result.get("status"),HeritageTaskResult.Status.SUCCESS,str(result))
			assert_eq(result.get("metrics",{}).get("stops"),1 if mistake else 0,str(result))
			assert_lte(result.get("time",40.0),30.0,str(result))

func test_cart_idle_and_continuously_pushing_do_not_win() -> void:
	for hold: bool in [false,true]:
		var result := _run("dong_yong_chuanshuo",Vector2(1000,600),false,not hold,hold)
		assert_eq(result.get("status"),HeritageTaskResult.Status.FAILURE,str(result))

func test_cart_brake_has_priority_and_actually_stops_the_cart() -> void:
	var task := _task("dong_yong_chuanshuo")
	Driver.edge(task,&"ui_right",true)
	for i: int in 120: task._process(1.0/120.0)
	assert_gt(task.get("speed"),80.0)
	Driver.edge(task,&"ui_left",true)
	for i: int in 120: task._process(1.0/120.0)
	assert_eq(task.get("speed"),0.0)
	assert_eq(task.call("get_presentation_state").pose,&"stop")

func test_cart_tutorial_requires_push_then_real_deceleration() -> void:
	var task := _task("dong_yong_chuanshuo",Vector2(1000,600),false)
	for i: int in 301: task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	Driver.edge(task,&"ui_right",true)
	Driver.edge(task,&"ui_right",false)
	Driver.edge(task,&"ui_left",true)
	Driver.edge(task,&"ui_left",false)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	Driver.edge(task,&"ui_right",true)
	for i: int in 100: task._process(1.0/120.0)
	Driver.edge(task,&"ui_left",true)
	for i: int in 70: task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)

func test_platform_tutorial_requires_landing_both_short_and_full_jumps() -> void:
	var task := _task("yandi_shennong_chuanshuo",Vector2(1000,600),false)
	for i: int in 301: task._process(1.0/120.0)
	Driver.edge(task,&"ui_accept",true)
	for i: int in 9: task._process(1.0/120.0)
	Driver.edge(task,&"ui_accept",false)
	for i: int in 100: task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	Driver.edge(task,&"ui_accept",true)
	for i: int in 110: task._process(1.0/120.0)
	Driver.edge(task,&"ui_accept",false)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)

func test_platform_mouse_only_can_move_and_jump_at_the_same_time() -> void:
	var task := _task("yandi_shennong_chuanshuo",Vector2(1280,720))
	var results: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	var controls: Dictionary = {"pointer":true}
	for frame: int in 45*120:
		if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		Driver.platform(task,1.0/120.0,controls)
		if frame==720: task.size=Vector2(1920,1080)
		task._process(1.0/120.0)
	assert_eq(results.size(),1)
	if not results.is_empty(): assert_true(results[0].is_success(),str(results[0].metrics))
