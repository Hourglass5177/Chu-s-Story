extends SceneTree

## Real key edges through viewport GUI; controlled source time, not listening review.
const ClockFixture = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock
const AVATARS := ["travel", "life", "business", "food", "adventure", "magic"]
const OUTPUT := "res://artifacts/tiqin-continuous-bow"
var viewport: SubViewport
var captures: Array[Dictionary] = []

func _initialize() -> void:
	root.size = Vector2i(1000, 600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	call_deferred("_run")

func _run() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://tiqin-bow-review.cfg")
	HeritageMinigamePreferences.save_offset(0)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 600)
	viewport.gui_disable_input = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(1000, 600)
	root.add_child(preview)
	var definition := load("res://InheritanceTasks/Definitions/ti_qin_xi.tres") as HeritageTaskDefinition
	var sheet := Image.create(3000, 1800, false, Image.FORMAT_RGBA8)
	var results: Array[Dictionary] = []
	for row: int in AVATARS.size():
		var task := definition.instantiate_task() as HeritagePerformanceTask
		viewport.add_child(task)
		task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		task.clock = ClockFixture.new()
		task.add_child(task.clock)
		var context := HeritageTaskRunContext.new(&"ti_qin_xi")
		context.test_mode = true
		context.avatar_id = StringName(AVATARS[row] + "_blogger")
		context.metadata["force_tutorial"] = true
		context.metadata["skip_tutorial"] = false
		context.metadata["presentation"] = definition.presentation
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		task.focus_mode = Control.FOCUS_ALL
		task.grab_focus()
		await process_frame
		for tick: int in 1400:
			if task.phase == HeritageStageTask.Phase.PRACTICE: break
			_frame(task, 0.01)
		var column := 0
		for event: Dictionary in task.lesson_chart.events:
			if event.kind == "rest": continue
			_advance(task, float(event.time_ms) / 1000.0)
			_key(int(event.direction), true)
			if event.kind == "hold":
				for progress: float in [0.25, 0.5, 0.75]:
					_advance(task, (float(event.time_ms) + float(int(event.end_ms) - int(event.time_ms)) * progress) / 1000.0)
					var state := task.get_visual_state()
					assert(bool(state.get("active_hold", false)))
					task.pixel_stage.update_state(state)
					await process_frame
					await RenderingServer.frame_post_draw
					var frame := task.pixel_stage.get_texture().get_image()
					var path := "%s/%s-%s-%02d.png" % [OUTPUT, AVATARS[row], "left" if int(event.direction) < 0 else "right", int(progress * 100)]
					frame.save_png(path)
					sheet.blit_rect(frame, Rect2i(0, 0, 500, 300), Vector2i(column * 500, row * 300))
					var geometry: Dictionary = task.pixel_stage.canvas.call("get_bow_visual_geometry")
					captures.append({"avatar": context.avatar_id, "direction": event.direction, "progress": state.hold_progress,
						"wrist": [geometry.wrist.x, geometry.wrist.y], "shoulder": [geometry.shoulder.x, geometry.shoulder.y],
						"string_contact": [geometry.string_contact.x, geometry.string_contact.y], "path": path})
					column += 1
				_advance(task, float(event.end_ms) / 1000.0)
			_key(int(event.direction), false)
		_advance(task, float(task.lesson_chart.end_ms + 50) / 1000.0)
		results.append({"avatar": context.avatar_id, "score": task.lesson_judge.score(), "ghosts": task.lesson_judge.ghosts,
			"lesson_passed": task.phase == HeritageStageTask.Phase.COUNTDOWN})
		assert(task.phase == HeritageStageTask.Phase.COUNTDOWN and task.lesson_judge.score() > 0.999)
		task.queue_free()
		await process_frame
	sheet.save_png(OUTPUT + "/six-avatars-left-right-progress.png")
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"method": "SubViewport.push_input ordinary InputEventKey + controlled music clock; actual Godot render",
		"human_listening_review": false, "columns": ["left25", "left50", "left75", "right25", "right50", "right75"],
		"rows": AVATARS, "captures": captures, "results": results}, "\t"))
	HeritageMinigamePreferences.configure_storage_path()
	print("TIQIN_CONTINUOUS_BOW_REVIEW_COMPLETE 36 actual hold frames; six lessons passed")
	quit()

func _frame(task: HeritagePerformanceTask, delta: float) -> void:
	(task.clock as ClockFixture).elapse(delta)
	task._process(delta)

func _advance(task: HeritagePerformanceTask, target: float) -> void:
	var remaining := 2000
	while task.clock.seconds() < target - 0.000001 and task.phase != HeritageStageTask.Phase.COUNTDOWN and remaining > 0:
		remaining -= 1
		_frame(task, minf(1.0 / 120.0, target - task.clock.seconds()))
	assert(remaining > 0)

func _key(direction: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_LEFT if direction < 0 else KEY_RIGHT
	event.physical_keycode = event.keycode
	event.pressed = down
	viewport.push_input(event, true)
