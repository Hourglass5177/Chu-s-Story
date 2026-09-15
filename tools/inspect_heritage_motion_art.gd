extends SceneTree

## GPU art inspection only; sampled poses are not gameplay/pass evidence.
const IDS := [&"travel_blogger",&"life_blogger",&"business_blogger",&"food_blogger",&"adventure_blogger",&"magic_blogger"]
var host: HeritageTaskHost

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/motion-pixel-ui")
	call_deferred("_inspect")

func _inspect() -> void:
	root.mode = Window.MODE_WINDOWED
	for id: StringName in [&"yandi_shennong_chuanshuo",&"dong_yong_chuanshuo",&"xingshan_min_ge",&"xisai_shenzhou_hui"]:
		if not OS.get_cmdline_user_args().is_empty() and str(id) not in OS.get_cmdline_user_args(): continue
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/%s.tres"%id) as HeritageTaskDefinition
		var context := HeritageTaskRunContext.new(id)
		context.test_mode = true
		context.metadata["skip_tutorial"] = true
		context.avatar_id = IDS[0]
		host.configure(definition,context)
		host.begin()
		for frame: int in 3: await process_frame
		await _capture(str(id)+"-prepare")
		host.start_from_preparation()
		for frame: int in 6: await process_frame
		var task := host.active_task
		task.set_process(false)
		task.set_physics_process(false)
		if not is_instance_valid(task.pixel_stage):
			push_error("Motion pixel stage missing: "+str(id))
			quit(1)
			return
		var stage := task.pixel_stage
		var state: Dictionary = task.get_visual_state()
		state["animation_time"] = 1.1
		if id==&"yandi_shennong_chuanshuo":state["pose"]=&"run"
		if id==&"dong_yong_chuanshuo":state["pose"]=&"push"
		# Render explicit art snapshots. Controls, score, task position untouched.
		for avatar: StringName in IDS:
			stage.avatar_id = avatar
			stage.canvas.avatar_id = avatar
			stage.update_state(state)
			for frame: int in 3:await process_frame
			await _capture(str(id)+"-"+str(avatar))
		for pose: String in ["prepare","action","miss","recover"]:
			state["pose"] = pose
			state["bird_pose"] = pose
			stage.update_state(state)
			for frame: int in 3:await process_frame
			await _capture(str(id)+"-state-"+pose)
		if id==&"dong_yong_chuanshuo":
			state.merge({"distance":1650.0,"height":440.0,"slope":0.0,"pose":&"brake","bridge_warning":true,"speed":95.0},true)
		elif id==&"yandi_shennong_chuanshuo":
			state.merge({"camera_x":2500.0,"section":&"creek","position":Vector2(2800,351),"feet":Vector2(2815,395),"pose":&"run"},true)
		stage.update_state(state)
		for frame: int in 3:await process_frame
		await _capture(str(id)+"-detail")
		host.cancel(&"visual_preview_complete")
		host.queue_free()
		await process_frame
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/motion-pixel-ui/%s.png"%label)
	print("MOTION_ART_VISUAL ",label)
