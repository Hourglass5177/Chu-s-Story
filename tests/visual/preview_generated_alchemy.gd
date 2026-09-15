extends SceneTree

## Real task input drives all state; screenshots never force heat or score.
var task: HeritageStageTask

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1000,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(1000,600)
	var definition := load("res://InheritanceTasks/Definitions/xia_lian_dan_shu.tres") as HeritageTaskDefinition
	var folder := "res://artifacts/pixel-v3/alchemy"
	DirAccess.make_dir_recursive_absolute(folder)
	for avatar: StringName in [&"travel_blogger", &"life_blogger", &"business_blogger", &"food_blogger", &"adventure_blogger", &"magic_blogger"]:
		task = definition.task_scene.instantiate()
		root.add_child(task)
		task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		task.size = Vector2(1000,600)
		var context := HeritageTaskRunContext.new(definition.task_id)
		context.test_mode = true
		context.avatar_id = avatar
		context.metadata["skip_tutorial"] = true
		context.metadata["host_controls"] = true
		context.metadata[&"presentation"] = definition.presentation
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		for i in 370: task._process(1.0/120.0)
		_edge(true)
		for i in 150:
			task._process(1.0/60.0)
			await process_frame
			if avatar in [&"travel_blogger", &"food_blogger"] and i < 72 and i % 2 == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/%s-motion-%03d.png"%[avatar,i/2])
			if i in [0,12,24,36,48,60,90,120,149]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/%s-%03d.png"%[avatar,i])
		_edge(false)
		for i in 90:
			task._process(1.0/60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/%s-released.png"%avatar)
		print("Generated alchemy real input: ",avatar," heat=",task.heat," brew=",task.brew)
		task.cancel_external()
		task.queue_free()
		await process_frame
	quit()

func _edge(down: bool) -> void:
	var input := InputEventKey.new()
	input.keycode = KEY_SPACE
	input.physical_keycode = KEY_SPACE
	input.pressed = down
	task.task_input(input)
