extends SceneTree
const Driver := preload("res://tests/support/action_story_input.gd")
const Motion := preload("res://tools/heritage_motion_input_driver.gd")
const DT := 1.0/120.0
var folder := "res://artifacts/action-story-v3"

func _initialize() -> void: _run.call_deferred()

func _create(id: String,avatar: StringName = &"travel_blogger",seed: int = 42) -> HeritageStageTask:
	var definition := load("res://InheritanceTasks/Definitions/%s.tres"%id) as HeritageTaskDefinition
	var task := definition.instantiate_task() as HeritageStageTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000,600)
	var context := HeritageTaskRunContext.new(StringName(id),null,null,0,0,seed)
	context.avatar_id = avatar
	context.test_mode = true
	context.metadata = {"skip_tutorial":true,"host_controls":true,"host_instruction_overlay":true,&"presentation":definition.presentation}
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	Driver.tick(task,3.1)
	return task

func _shot(name: String, task: HeritageStageTask = null) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(folder+"/"+name+".png")
	if task != null and "dong-hand-connection" in folder:
		var shoulder: Vector2 = task.contact.shoulder
		var top := clampi(roundi(380+(shoulder.y-380)*1.2-20),0,475)
		var detail := frame.get_region(Rect2i(80,top,210,125))
		detail.resize(840,500,Image.INTERPOLATE_NEAREST)
		detail.save_png(folder+"/"+name+"-hands.png")

func _run() -> void:
	var hand_review := "--dong-hands" in OS.get_cmdline_user_args()
	var dong_only := "--dong-only" in OS.get_cmdline_user_args() or hand_review
	if dong_only: folder="res://artifacts/dong-original-detail-v4"
	if hand_review: folder="res://artifacts/dong-hand-connection-v8-final"
	root.content_scale_size = Vector2i(1000,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(1000,600)
	DirAccess.make_dir_recursive_absolute(folder)
	for avatar: StringName in HeritageAvatarCatalog.IDS:
		var task := _create("dong_yong_chuanshuo",avatar)
		Driver.key(task,KEY_D,true)
		Driver.tick(task,3)
		await _shot("dong-"+str(avatar),task)
		if avatar==&"travel_blogger":
			for frame: int in 16:
				Driver.tick(task,.05)
				await _shot("dong-motion-%02d"%frame,task)
		if avatar==&"travel_blogger" or hand_review:
			var prefix := "dong" if avatar==&"travel_blogger" else "dong-"+str(avatar)
			var poses := {}
			for tick: int in 2500:
				Motion.cart(task)
				task._process(DT)
				if task.distance>750 and not poses.has("uphill"):
					poses.uphill=true
					await _shot(prefix+"-uphill",task)
				if task.distance>1050 and task.distance<1052: await _shot(prefix+"-crest",task)
				if task.distance>1340 and not poses.has("downhill"):
					poses.downhill=true
					await _shot(prefix+"-downhill",task)
				if task.pose==&"brake" and not poses.has("brake"):
					poses.brake=true
					await _shot(prefix+"-brake",task)
				if task.distance>1740 and task.distance<1742: await _shot(prefix+"-bridge",task)
				if task.run_state==HeritageTaskBase.RunState.FINISHED: break
			print("DONG actual input: ",avatar," ",task.game_time," stops=",task.mistakes)
		task.queue_free()
		await process_frame
	if dong_only:
		quit()
		return
	var paper := _create("ezhou_diaohua_jianzhi")
	await _shot("paper-ready")
	for index: int in 3:
		var path: PackedVector2Array = paper.contours[index]
		Driver.mouse(paper,path[0],true)
		for point: Vector2 in path:
			Driver.motion(paper,point)
			paper._process(.02)
		Driver.mouse(paper,path[-1],false)
		await _shot("paper-cut-%d"%(index+1))
	print("PAPER actual input: ",paper.game_time," contours=",paper.segment)
	paper.queue_free()
	await process_frame
	var seen := {}
	for seed: int in range(30):
		var story := _create("xiabaoping_minjian_gushi",&"travel_blogger",seed)
		if not seen.has(story.story_index):
			seen[story.story_index]=true
			for scene: int in 3:
				await _shot("story-%d-%d-play"%[story.story_index,scene])
				Driver.solve_scene(story)
				await _shot("story-%d-%d-complete"%[story.story_index,scene])
				Driver.tick(story,story.reveal_left+.01)
		story.queue_free()
		await process_frame
		if seen.size()==3:break
	var boat := _create("xisai_shenzhou_hui")
	await _shot("boat-ready")
	for tick: int in 36*120:
		Driver.escort(boat)
		boat._process(DT)
		if boat.distance>1700 and boat.distance<1702:await _shot("boat-slow-approach")
		if boat.distance>2130 and boat.distance<2131:await _shot("boat-changing-lanes")
		if boat.run_state==HeritageTaskBase.RunState.FINISHED:break
	print("BOAT actual input: ",boat.game_time," collisions=",boat.collisions," distance=",boat.distance)
	await _shot("boat-finish")
	boat.queue_free()
	await process_frame
	quit()
