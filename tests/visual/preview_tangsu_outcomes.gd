extends SceneTree

const DT := 1.0 / 120.0
var task: HeritageStageTask

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1000, 600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(1000, 600)
	var definition := load("res://InheritanceTasks/Definitions/tianmen_tang_su.tres") as HeritageTaskDefinition
	task = definition.task_scene.instantiate() as HeritageStageTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000, 600)
	var context := HeritageTaskRunContext.new(&"tianmen_tang_su")
	context.test_mode = true
	context.metadata["skip_tutorial"] = true
	context.metadata["host_controls"] = true
	context.metadata[&"presentation"] = definition.presentation
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	for frame: int in 370: task._process(DT)
	for release_radius: float in [0.35, 0.70, 0.88]:
		_edge(true)
		for frame: int in 1200:
			if task.radius >= release_radius: break
			task._process(DT)
		_edge(false)
		for frame: int in 100:
			if task.blow_phase == 3: break
			task._process(DT)
		if task.outcomes.size() < 3:
			for frame: int in 160:
				if task.blow_phase == 0: break
				task._process(DT)
	assert(task.outcomes == ["偏小", "合适", "过大"])
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/tangsu-outcomes"
	DirAccess.make_dir_recursive_absolute(folder)
	var output := folder + "/mixed-results.png"
	var code := root.get_texture().get_image().save_png(output)
	print("Tangsu real-input outcomes: ", task.outcomes, " radii=", task.outcome_radii)
	print("Saved actual rendered stage: ", ProjectSettings.globalize_path(output), " code=", code)
	task.cancel_external()
	task.queue_free()
	await process_frame
	quit(code)

func _edge(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	task.task_input(event)
