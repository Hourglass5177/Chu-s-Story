extends SceneTree

## Ordinary pointer events exercise the same four contours for all six sleeves.
const Driver := preload("res://tests/support/action_story_input.gd")
const OUTPUT := "res://artifacts/input-revision/paper/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1000,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(1000,600)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var definition := load("res://InheritanceTasks/Definitions/ezhou_diaohua_jianzhi.tres") as HeritageTaskDefinition
	for avatar: StringName in HeritageAvatarCatalog.IDS:
		var task := definition.instantiate_task() as HeritageStageTask
		root.add_child(task)
		task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		task.size = Vector2(1000,600)
		var context := HeritageTaskRunContext.new(definition.task_id)
		context.test_mode = true
		context.avatar_id = avatar
		context.metadata = {"skip_tutorial":true,"host_controls":true,"host_instruction_overlay":true,&"presentation":definition.presentation}
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		Driver.tick(task,3.1)
		await _shot(str(avatar)+"-ready")
		for index: int in 4:
			var path: PackedVector2Array = task.contours[index]
			Driver.mouse(task,path[0],true)
			for point: Vector2 in path:
				Driver.motion(task,point)
				task._process(.02)
			Driver.mouse(task,path[-1],false)
			await _shot(str(avatar)+"-cut-%d"%(index+1))
		Driver.tick(task,1.1)
		await _shot(str(avatar)+"-result")
		assert(task.segment==4 and task.run_state==HeritageTaskBase.RunState.FINISHED)
		print("PAPER_DETAIL_INPUT ",avatar," time=",task.game_time," contours=",task.segment)
		task.queue_free()
		await process_frame
	quit()

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
