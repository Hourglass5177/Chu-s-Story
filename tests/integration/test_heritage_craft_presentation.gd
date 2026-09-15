extends GutTest

const IDS: Array[StringName] = [&"tianmen_tang_su", &"gu_pen_ge", &"ezhou_diaohua_jianzhi", &"huangmei_xi"]
var viewport: SubViewport

func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000,600)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)

func test_four_stages_keep_six_identity_specific_action_sets() -> void:
	for id: StringName in IDS:
		var definition := HeritageTaskManager.get_definition(id)
		assert_not_null(definition.presentation)
		assert_not_null(definition.presentation.stage_scene)
		for avatar: StringName in HeritageAvatarCatalog.IDS:
			var appearance := definition.presentation.get_appearance(avatar)
			assert_not_null(appearance, str(id)+" "+str(avatar))
			assert_eq(appearance.avatar_id,avatar)
			if id==&"ezhou_diaohua_jianzhi":
				var hand := load("res://InheritanceTasks/Art/Pixel/v3/runtime/paper/%s-hand.png"%avatar) as Texture2D
				assert_not_null(hand,"Each blogger has a separately generated sleeve/knife hand")
				assert_gt(hand.get_width(),0)
				assert_gt(hand.get_height(),300,"Retain the generated wrist/blade detail in the source crop")
				var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://InheritanceTasks/Art/Pixel/v3/runtime/paper/detail-anchors.json"))
				assert_eq(float(metadata.hand_display_sizes[str(avatar)][1]),108.0,"Export quality must not enlarge the hand over the cutting path")
				continue
			for action: StringName in [&"ready",&"prepare",&"hold",&"release",&"miss",&"recover"]:
				assert_true(appearance.sprite_frames.has_animation(action))

func test_paper_input_and_render_tip_share_coordinates_across_sizes() -> void:
	var driver := preload("res://tests/support/action_story_input.gd")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		viewport.size = dimensions
		var task := _start(&"ezhou_diaohua_jianzhi",&"travel_blogger",true)
		await wait_process_frames(2)
		driver.tick(task,3.1)
		var point := Vector2(410,306)
		driver.mouse(task,point,true)
		var state: Dictionary = task.get_presentation_state()
		assert_almost_eq(state.pointer,point,Vector2.ONE*.001)
		assert_eq(state.contours,task.contours,"Draw and scoring use the exact same contour data")
		driver.mouse(task,point,false)
		task.cancel_external()
		task.queue_free()
		await wait_process_frames(1)

func test_paper_same_normal_pointer_route_passes_with_every_blogger() -> void:
	for avatar: StringName in HeritageAvatarCatalog.IDS:
		var task := _start(&"ezhou_diaohua_jianzhi",avatar,true)
		var driver := preload("res://tests/support/action_story_input.gd")
		var outcome: Array = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: outcome.append(result))
		await wait_process_frames(1)
		driver.tick(task,3.1)
		for path: PackedVector2Array in task.contours:
			_click(driver.local_point(task,path[0]),true)
			for i: int in range(1,path.size()-1):
				var motion := InputEventMouseMotion.new()
				motion.position = driver.local_point(task,path[i])
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				viewport.push_input(motion,true)
				task._process(.016)
			_click(driver.local_point(task,path[-1]),false)
		assert_eq(outcome.size(),0,"The final cut drops before the result is emitted")
		driver.tick(task,1.1)
		assert_eq(outcome.size(),1,str(avatar))
		if not outcome.is_empty(): assert_true(outcome[0].is_success())
		assert_lte(task.off_path_seconds,.1)
		task.queue_free()
		await wait_process_frames(1)

func test_gupen_audio_and_avatar_do_not_change_fixed_chart_or_three_round_scores() -> void:
	var clock_class = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock
	for use_art: bool in [false,true]:
		var task := _start(&"gu_pen_ge",&"business_blogger",use_art) as HeritagePerformanceTask
		task.clock = clock_class.new()
		task.add_child(task.clock)
		var outcomes: Array[HeritageTaskResult] = []
		task.task_completed.connect(func(result: HeritageTaskResult) -> void: outcomes.append(result))
		var sent: Dictionary = {}
		for tick: int in 3700:
			if task.run_state == HeritageTaskBase.RunState.FINISHED: break
			task.clock.call("elapse", .01)
			task._process(.01)
			if task.phase != HeritageStageTask.Phase.LIVE: continue
			for event: Dictionary in task.chart.events:
				if task.clock.seconds()*1000 >= int(event.time_ms) and not sent.has(event.id):
					sent[event.id]=true
					_click(Vector2(500,360),true)
					_click(Vector2(500,360),false)
		assert_eq(outcomes.size(),1)
		if not outcomes.is_empty():
			assert_eq(outcomes[0].status,HeritageTaskResult.Status.SUCCESS)
			assert_eq(outcomes[0].metrics.rounds_passed,3)
		task.queue_free()
		await wait_process_frames(1)

func _start(id: StringName, avatar: StringName, use_art: bool) -> HeritageTaskBase:
	var definition := HeritageTaskManager.get_definition(id)
	var task := definition.task_scene.instantiate() as HeritageTaskBase
	viewport.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(id,null,null,0,0,88,true)
	context.avatar_id = avatar
	context.metadata["skip_tutorial"] = true
	if use_art: context.metadata[&"presentation"] = definition.presentation
	task.configure(context)
	task.start_task()
	task.focus_mode = Control.FOCUS_ALL
	task.grab_focus()
	task.set_process(false)
	task.set_physics_process(false)
	return task

func _click(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	viewport.push_input(event,true)
