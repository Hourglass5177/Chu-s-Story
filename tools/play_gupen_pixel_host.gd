extends SceneTree

## Full, real-time three-round runs in the current pixel Host. The operator may
## read the displayed pattern and turn, but only sends normal InputEventAction.
## It never writes scores, task stages, progress, time, or completion results.
var host: Control
var task: Control
var result: Dictionary = {}
var reports: Array[Dictionary] = []
var sent_inputs: Array[Dictionary] = []
var completion_count: int = 0

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/gupen-pixel-play")
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame: int in 5: await process_frame
	for recover_first_round: bool in [false, true]:
		var label := "recover-one-round" if recover_first_round else "clean"
		result.clear()
		sent_inputs.clear()
		completion_count = 0
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
		root.add_child(host)
		var context = load("res://InheritanceTasks/Data/heritage_task_run_context.gd").new(&"gu_pen_ge",null,null,0,0,88,true)
		context.metadata["skip_tutorial"] = true
		context.avatar_id = &"travel_blogger"
		host.configure(load("res://InheritanceTasks/Definitions/gu_pen_ge.tres"),context)
		host.task_finished.connect(_on_finished)
		host.begin()
		for frame: int in 3: await process_frame
		_press_start()
		task = host.active_task
		var started := Time.get_ticks_msec()
		var deadline := started+45000
		var current_round := -1
		var next_hit := 0
		var playing_captured := false
		while result.is_empty() and Time.get_ticks_msec()<deadline:
			var round_index: int = task.get("_round_index")
			if round_index != current_round:
				current_round = round_index
				next_hit = 0
			var pattern: Array = task.get("_pattern")
			var round_time: float = task.get("_stage_time")
			var delay := .45 if recover_first_round and current_round == 0 else 0.0
			if int(task.get("_stage")) == 1 and next_hit<pattern.size() and round_time>=float(pattern[next_hit])+delay:
				_accept()
				sent_inputs.append({"round":current_round+1,"beat":next_hit+1,"time":round_time,"target":pattern[next_hit],"intentional_delay":delay})
				next_hit += 1
			if not playing_captured and current_round == 1 and int(task.get("_stage")) == 1:
				await _capture(label+"-playing")
				playing_captured = true
			await process_frame
		var expected_rounds := 2 if recover_first_round else 3
		var record := {"case":label,"result":result.duplicate(true),"inputs":sent_inputs.duplicate(true),
			"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"completion_count":completion_count,
			"practice_entry":true,"formal_timed_phase":true,"pixel_stage_active":is_instance_valid(task.pixel_stage)}
		record["passed"] = not result.is_empty() and int(result.get("status",-1)) == 0 and int(result.get("metrics",{}).get("rounds_passed",-1)) == expected_rounds and completion_count == 1
		reports.append(record)
		for frame: int in 3: await process_frame
		await _capture(label+"-result")
		print("GUPEN_PIXEL_HOST ",JSON.stringify(record))
		host.cancel(&"walkthrough_finished")
		host.queue_free()
		await process_frame
	var file := FileAccess.open("res://artifacts/gupen-pixel-play/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
	file.close()
	var all_passed := true
	for record: Dictionary in reports: all_passed = all_passed and bool(record.passed)
	quit(0 if all_passed else 1)

func _on_finished(value: RefCounted) -> void:
	completion_count += 1
	result = {"status":value.get("status"),"message":value.get("message"),"metrics":value.get("metrics").duplicate(true),"elapsed_seconds":value.get("elapsed_seconds")}

func _press_start() -> void:
	var button: Button = host.get("_start_button")
	var point := button.get_global_rect().get_center()
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)

func _accept() -> void:
	for down: bool in [true,false]:
		var event := InputEventAction.new()
		event.action = &"ui_accept"
		event.pressed = down
		root.push_input(event,true)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/gupen-pixel-play/%s.png" % label)
