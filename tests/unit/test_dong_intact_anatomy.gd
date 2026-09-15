extends GutTest

const Stage := preload("res://InheritanceTasks/Presentation/Stages/dong_yong_chuanshuo_pixel.gd")
const Driver := preload("res://tools/heritage_motion_input_driver.gd")

func test_intact_pose_keeps_original_proportions_and_ground_contact_for_six_identities() -> void:
	var definition := load("res://InheritanceTasks/Definitions/dong_yong_chuanshuo.tres") as HeritageTaskDefinition
	var baseline_time := -1.0
	for avatar: StringName in HeritageAvatarCatalog.IDS:
		var task := definition.instantiate_task() as HeritageStageTask
		add_child(task)
		var context := HeritageTaskRunContext.new(definition.task_id)
		context.test_mode = true
		context.metadata.skip_tutorial = true
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		# Clear the countdown before the first held movement input.
		for countdown_tick: int in 372: task._process(1.0/120.0)
		var stage := Stage.new()
		stage.avatar_id = avatar
		var start_ratio := -1.0
		for tick: int in 31*120:
			Driver.cart(task)
			task._process(1.0/120.0)
			if tick%30==0:
				var state: Dictionary = task.get_presentation_state()
				state.animation_time = task.game_time
				stage.receive_visual_state(state)
				var contact := stage.contact_pose()
				var body: Dictionary = contact.body
				var hip: Vector2 = body.hip
				assert_almost_eq(hip.y+contact.leg_height,task.height_at(hip.x),.02,str(avatar))
				assert_almost_eq(body.near_grip.distance_to(contact.handle),0.0,.001)
				# Whole upper-body transform preserves the generated hand/hip and
				# two-fist distances under pushing, braking and slope changes.
				var ratio: float = body.near_grip.distance_to(hip)/body.scale
				if start_ratio<0: start_ratio=ratio
				assert_almost_eq(ratio,start_ratio,.001,"No limb stretching: "+str(avatar))
				for foot: Vector2 in contact.feet:
					assert_between(task.height_at(foot.x)-foot.y,-.01,10.01)
			if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		if baseline_time<0: baseline_time=task.game_time
		assert_between(task.game_time,23.0,27.0)
		assert_almost_eq(task.game_time,baseline_time,.001,"Presentation cannot change travel time")
		assert_eq(task.mistakes,0)
		stage.free()
		task.free()
