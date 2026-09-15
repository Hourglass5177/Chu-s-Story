extends GutTest

const FLIGHT := preload("res://InheritanceTasks/Tasks/xingshan_min_ge.tscn")
const PAINTER := preload("res://InheritanceTasks/Presentation/Stages/xingshan_min_ge_pixel.gd")

func _flight() -> HeritageStageTask:
	var task := FLIGHT.instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_process(false)
	task.set_physics_process(false)
	var context := HeritageTaskRunContext.new(&"xingshan_min_ge")
	context.test_mode = true
	task.configure(context)
	task.setup_game()
	return task

func _linear_history(task: HeritageStageTask, fps: int) -> void:
	task.set("bird_y",200.0)
	task.set("vertical_speed",120.0)
	task.call("_reset_flock_history")
	for i: int in range(1,fps+1):
		task.set("bird_y",200.0+120.0*float(i)/fps)
		task.call("_advance_flock",1.0/fps)

func test_three_delays_interpolate_independently_at_different_sample_rates() -> void:
	var baseline: Array[Vector2] = []
	for fps: int in [30,60,144]:
		var task := _flight()
		_linear_history(task,fps)
		var followers: Array[Dictionary] = task.call("get_follower_states")
		assert_eq(followers.size(),3)
		var positions: Array[Vector2] = []
		var wing_times: Array[float] = []
		for i: int in 3:
			var follower: Dictionary = followers[i]
			var offset: Vector2 = task.FOLLOWER_OFFSETS[i]
			var expected_y: float = 320.0-120.0*task.FOLLOWER_DELAYS[i]
			assert_almost_eq(float(follower.sample.y),expected_y,0.0001)
			assert_almost_eq((follower.position as Vector2).y,expected_y+offset.y,0.0001)
			assert_eq((follower.position as Vector2).x,280.0+offset.x)
			positions.append(follower.position)
			wing_times.append(follower.wing_time)
		assert_ne(wing_times[0],wing_times[1])
		assert_ne(wing_times[1],wing_times[2])
		if baseline.is_empty(): baseline = positions
		else:
			for i: int in 3: assert_lt(positions[i].distance_to(baseline[i]),0.0001)

func test_collision_and_recovery_reach_each_follower_at_its_own_delay() -> void:
	var task := _flight()
	for frame: int in range(1,121):
		var at := frame/120.0
		if frame>=60:
			task.set("bird_y",200.0)
			task.set("recovery",maxf(0.0,0.65-(at-0.5)))
		task.call("_advance_flock",1.0/120.0)
		if frame==96:
			var followers: Array[Dictionary] = task.call("get_follower_states")
			assert_eq(followers[0].pose,"miss")
			assert_eq(followers[1].pose,"descend")
			assert_eq(followers[2].pose,"descend")
	var after: Array[Dictionary] = task.call("get_follower_states")
	assert_eq(after[0].pose,"recover")
	assert_eq(after[1].pose,"miss")
	assert_eq(after[2].pose,"miss")
	assert_gt(float(after[2].recovery),float(after[1].recovery))
	assert_gt(float(after[1].recovery),float(after[0].recovery))
	assert_lte((task.get("_flock_history") as Array).size(),75)

func test_pause_clears_history_freezes_each_visible_bird_and_resumes_continuously() -> void:
	var task := _flight()
	_linear_history(task,120)
	var frozen: Array[Dictionary] = task.call("get_follower_states")
	var clock_before: float = task.get("_flock_time")
	task.on_suspension_changed(true)
	assert_eq((task.get("_flock_history") as Array).size(),0)
	assert_eq(task.call("get_follower_states"),frozen)
	assert_eq(task.get("_flock_time"),clock_before)
	task.on_suspension_changed(false)
	assert_eq(task.call("get_follower_states"),frozen,"Resume countdown keeps the frozen poses")
	task.set("bird_y",321.0)
	task.call("_advance_flock",1.0/120.0)
	var resumed: Array[Dictionary] = task.call("get_follower_states")
	for i: int in 3:
		assert_lt((resumed[i].position as Vector2).distance_to(frozen[i].position),1.1,"No group snap after clearing old history")
	assert_false(bool(task.get("_flock_frozen_active")))
	assert_gt((task.get("_flock_history") as Array).size(),0)

func test_new_lesson_clears_frozen_history_and_old_recovery() -> void:
	var task := _flight()
	_linear_history(task,120)
	task.set("recovery",0.65)
	task.call("_record_flock_sample")
	task.on_suspension_changed(true)
	task.setup_game()
	assert_false(bool(task.get("_flock_frozen_active")))
	assert_eq((task.get("_flock_history") as Array).size(),1)
	assert_eq(float(task.get("_flock_time")),0.0)
	for follower: Dictionary in task.call("get_follower_states"):
		assert_eq(float(follower.sample.y),300.0)
		assert_eq(float(follower.recovery),0.0)

func test_sampling_and_frame_selection_do_not_write_gameplay_state() -> void:
	var task := _flight()
	_linear_history(task,120)
	task.game_time = 9.75
	var before := [task.get("bird_y"),task.get("vertical_speed"),task.get("recovery"),task.get("hits"),task.game_time,(task.get("gates") as Array).duplicate(true)]
	for repeat: int in 100: task.get_presentation_state()
	var after := [task.get("bird_y"),task.get("vertical_speed"),task.get("recovery"),task.get("hits"),task.game_time,(task.get("gates") as Array).duplicate(true)]
	assert_eq(after,before)
	var painter := PAINTER.new()
	assert_eq(painter.follower_frame({"pose":"flap","wing_time":0.0}),0)
	assert_eq(painter.follower_frame({"pose":"flap","wing_time":0.12}),1)
	assert_eq(painter.follower_frame({"pose":"flap","wing_time":0.12},true),2)
	assert_eq(painter.follower_frame({"pose":"miss"},true),4)
	assert_eq(painter.follower_frame({"pose":"recover"},true),5)
	painter.free()
