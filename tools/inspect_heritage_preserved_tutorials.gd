extends SceneTree

## Runs the three first lessons through normal pointer events in a real rendered
## Host. It never writes score, progress, stage, or lesson completion state.
var host: Control
var task: Control
var failures: Array[String] = []

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/preserved-tutorial-ui")
	call_deferred("_inspect")

func _inspect() -> void:
	var prefs = load("res://InheritanceTasks/Common/heritage_minigame_preferences.gd")
	prefs.configure_storage_path("user://preserved-tutorial-preview.cfg")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame: int in 5: await process_frame
	for id: StringName in [&"gu_pen_ge", &"ezhou_diaohua_jianzhi", &"xisai_shenzhou_hui"]:
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
		root.add_child(host)
		var definition = load("res://InheritanceTasks/Definitions/%s.tres" % id)
		var context = load("res://InheritanceTasks/Data/heritage_task_run_context.gd").new(id,null,null,0,0,88,true)
		context.metadata["force_tutorial"] = true
		host.configure(definition,context)
		host.begin()
		for frame: int in 3: await process_frame
		host.start_from_preparation(true)
		task = host.active_task
		await _capture(str(id)+"-demonstration")
		while int(task.optional_lesson_phase) == 1: await process_frame
		await _capture(str(id)+"-practice")
		if id == &"ezhou_diaohua_jianzhi":
			var path: PackedVector2Array = task.get("_path")
			_click(path[0],true)
			for sample: int in 50:
				_move(path[0].lerp(path[1],float(sample+1)/50.0))
				await process_frame
			_click(path[1],false)
		else:
			var next_hit := 0
			if id == &"xisai_shenzhou_hui": _click(Vector2(500,350),true)
			var deadline := Time.get_ticks_msec()+16000
			while int(task.optional_lesson_phase) == 2 and Time.get_ticks_msec()<deadline:
				if id == &"gu_pen_ge":
					var pattern: Array = task.get("_pattern")
					if int(task.get("_stage")) == 1 and next_hit<pattern.size() and float(task.get("_stage_time"))>=float(pattern[next_hit]):
						_click(Vector2(500,350),true)
						_click(Vector2(500,350),false)
						next_hit += 1
				else:
					var x: float = task.get("_boat_x")
					var velocity: float = task.get("_boat_velocity")
					var t: float = task.optional_lesson_elapsed
					var current := sin(t*1.8)*.55+sin(t*.63+1.2)*.35
					var steer := clampf((.5-x)*7.0-velocity*4.0-current*.8/1.1,-1,1)
					_move(Vector2(500,350),Vector2(steer*24,0))
				await process_frame
			if id == &"xisai_shenzhou_hui": _click(Vector2(500,350),false)
		await process_frame
		if int(task.optional_lesson_phase) != 3: failures.append(str(id)+" practice did not complete")
		await _capture(str(id)+"-countdown")
		print("PRESERVED_LESSON ",id," phase=",task.optional_lesson_phase," formal_time=",task.elapsed_seconds," time_left=",task.time_left)
		host.cancel(&"preview_finished")
		host.queue_free()
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://preserved-tutorial-preview.cfg"))
	prefs.configure_storage_path()
	print("PRESERVED_LESSON_FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)

func _click(point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = task.get_global_transform()*point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event,true)

func _move(point: Vector2,relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = task.get_global_transform()*point
	event.relative = task.get_global_transform().basis_xform(relative)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/preserved-tutorial-ui/%s.png" % label)
