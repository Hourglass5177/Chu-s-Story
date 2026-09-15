extends SceneTree

## Visual staging only. These captures do not prove normal-input completion.
var host: Control
var records: Array[Dictionary] = []
var task_ids: Array[String] = ["xia_lian_dan_shu"]
const AVATARS := ["travel", "life", "business", "food", "adventure", "magic"]

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		task_ids.clear()
		for id: String in args: task_ids.append(id)
	DirAccess.make_dir_recursive_absolute("res://artifacts/pixel-art-review")
	call_deferred("_run")

func _run() -> void:
	for f in 5: await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for f in 5: await process_frame
	var host_scene = load("res://InheritanceTasks/UI/heritage_task_host.tscn")
	var context_class = load("res://InheritanceTasks/Data/heritage_task_run_context.gd")
	for id: String in task_ids:
		for avatar: String in AVATARS:
			host = host_scene.instantiate()
			root.add_child(host)
			var definition = load("res://InheritanceTasks/Definitions/%s.tres" % id)
			var context = context_class.new(definition.task_id, null, null, 0, 0, 77, true)
			context.avatar_id = StringName(avatar + "_blogger")
			context.test_mode = true
			context.metadata[&"skip_tutorial"] = true
			host.configure(definition,context)
			host.begin()
			for f in 5: await process_frame
			await _capture(id,avatar,"prepare")
			host.start_from_preparation()
			var task = host.active_task
			if task.has_method("finish_lesson"):
				task.finish_lesson()
				await create_timer(2.2).timeout
			elif task.supports_interactive_tutorial():
				while task.optional_lesson_phase == HeritageTaskBase.OptionalLesson.DEMO:
					await process_frame
				task.finish_optional_lesson()
				await create_timer(1.7).timeout
			else: await create_timer(.2).timeout
			for f in 5: await process_frame
			await _capture(id,avatar,"scene")
			# Only the presentation state is staged. Scores/physics are not used as evidence.
			if is_instance_valid(task.pixel_stage):
				task.set_process(false)
				for pose: String in ["miss", "recover"]:
					var state: Dictionary = task.get_visual_state().duplicate(true)
					state["action"] = pose
					state["motion_phase"] = pose
					state["pose"] = pose
					task.pixel_stage.update_state(state)
					await process_frame
					await _capture(id,avatar,pose)
			# This forced result exists solely to inspect the result UI, never as a pass test.
			task.complete_success({"art_staging": true}, "成果画面检查")
			for f in 8: await process_frame
			await _capture(id,avatar,"result")
			host.cancel(&"art_inspection_finished")
			host.queue_free()
			await process_frame
	var file := FileAccess.open("res://artifacts/pixel-art-review/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"art staging; tutorial bypassed; no gameplay pass claim","captures":records},"\t"))
	quit()

func _capture(id: String, avatar: String, state: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/pixel-art-review/%s-%s-%s.png" % [id,avatar,state]
	root.get_texture().get_image().save_png(path)
	if state == "scene" and is_instance_valid(host.active_task.pixel_stage):
		host.active_task.pixel_stage.get_texture().get_image().save_png("res://artifacts/pixel-art-review/%s-%s-pixel.png" % [id,avatar])
	records.append({"task_id":id,"avatar":avatar,"state":state,"path":path})
	print("PIXEL_ART_CAPTURE ",id," ",avatar," ",state)
