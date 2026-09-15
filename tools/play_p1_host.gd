extends SceneTree

## Real Host walkthrough: prepare by pointer, then complete the actual lessons
## and challenges with Viewport key events. No score, position, phase or result
## is injected. test_mode only isolates tutorial persistence and OS key state.
const Driver := preload("res://tools/heritage_motion_input_driver.gd")
const OUTPUT := "res://artifacts/p1-host-play"
var host: HeritageTaskHost
var task: HeritageStageTask
var keys: Dictionary = {}
var controls: Dictionary = {}
var inputs: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var result: HeritageTaskResult
var completion_count := 0
var current_id: StringName

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.title = "楚物志 · P1 实际宿主普通输入验证"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame: int in 5: await process_frame
	for id: StringName in [&"xia_lian_dan_shu",&"yandi_shennong_chuanshuo"]:
		await _run_one(id)
		if result == null or not result.is_success(): break
	var output := {"method":"Current graphical HeritageTaskHost practice. Pointer starts preparation; ordinary Viewport InputEvents complete teaching and challenge. No internal success injection. Not human experience acceptance.","runs":reports,"captures":captures}
	var file := FileAccess.open(OUTPUT+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	var passed := reports.size() == 2
	for report: Dictionary in reports: passed = passed and bool(report.get("success",false))
	quit(0 if passed else 1)

func _run_one(id: StringName) -> void:
	current_id = id
	keys.clear()
	controls = {"edge_callback":_platform_edge}
	inputs.clear()
	result = null
	completion_count = 0
	host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	root.add_child(host)
	var context := HeritageTaskRunContext.new(id,null,null,0,0,909,true)
	context.test_mode = true
	context.avatar_id = &"travel_blogger"
	context.metadata[&"skip_tutorial"] = false
	host.configure(load("res://InheritanceTasks/Definitions/%s.tres" % id),context)
	host.task_finished.connect(func(value: HeritageTaskResult) -> void:
		result = value
		completion_count += 1)
	host.begin()
	task = host.active_task as HeritageStageTask
	for frame: int in 5: await process_frame
	await _capture("prepare")
	var start := host.get("_relearn_button") as Button
	if not start.visible: start = host.get("_start_button") as Button
	await _click(start)
	print("P1_HOST_START ",id)
	var deadline := Time.get_ticks_msec()+90000
	var seen: Dictionary = {}
	var previous_phase := -1
	var next_heat_decision := 0.0
	while result == null and Time.get_ticks_msec()<deadline:
		await process_frame
		if task.run_state == HeritageTaskBase.RunState.SUSPENDED: continue
		if int(task.phase) != previous_phase:
			previous_phase = int(task.phase)
			print("P1_HOST_PHASE ",id," ",task.get_instruction_state())
			if task.phase == HeritageStageTask.Phase.COUNTDOWN:
				_send_key(KEY_SPACE,false)
				_send_key(KEY_D,false)
		if task.phase == HeritageStageTask.Phase.DEMO:
			if task.phase_time>0.6 and not seen.has("demo"):
				seen.demo = true
				await _capture("demo")
		elif task.phase == HeritageStageTask.Phase.PRACTICE:
			if id == &"xia_lian_dan_shu":
				_send_key(KEY_SPACE,not bool(task.get("lesson_caught")))
			else:
				var short_done: bool = bool(task.get("_practiced_short"))
				var hold_until: float = float(controls.get("lesson_hold_until",0.0))
				if bool(task.get("grounded")) and task.phase_time>=float(controls.get("next_lesson_jump",0.2)):
					hold_until = task.phase_time + (0.45 if short_done else 0.09)
					controls.lesson_hold_until = hold_until
					controls.next_lesson_jump = task.phase_time + 1.2
				_send_key(KEY_SPACE,task.phase_time<hold_until)
			if task.phase_time>0.4 and not seen.has("practice"):
				seen.practice = true
				await _capture("practice")
		elif task.phase == HeritageStageTask.Phase.LIVE:
			if id == &"xia_lian_dan_shu":
				if task.game_time>=next_heat_decision:
					next_heat_decision = task.game_time+0.12
					var predicted: float = float(task.get("heat"))+float(task.get("velocity"))*0.13
					var down: bool = bool(keys.get(KEY_SPACE,false))
					if down and predicted>float(task.get("target"))+0.025: down = false
					elif not down and predicted<float(task.get("target"))-0.025: down = true
					_send_key(KEY_SPACE,down)
			else:
				Driver.platform(task,root.get_process_delta_time(),controls)
			if task.game_time>3.5 and not seen.has("challenge"):
				seen.challenge = true
				await _capture("challenge")
			if task.game_time>9.0 and not seen.has("resized"):
				seen.resized = true
				root.size = Vector2i(1920,1080)
			if task.game_time>10.0 and not seen.has("restored"):
				seen.restored = true
				root.size = Vector2i(1280,720)
			if task.game_time>12.0 and not seen.has("late"):
				seen.late = true
				await _capture("challenge-late")
	_send_key(KEY_SPACE,false)
	_send_key(KEY_D,false)
	root.size = Vector2i(1280,720)
	for frame: int in 6: await process_frame
	await _capture("result" if result != null else "timeout")
	var report := {"task":id,"success":result != null and result.is_success(),"status":int(result.status) if result != null else -1,"completion_count":completion_count,"seconds":task.game_time,"metrics":result.metrics if result != null else {},"input_count":inputs.size(),"resized_and_restored":seen.has("resized") and seen.has("restored"),"teaching_demonstrated":seen.has("demo") and seen.has("practice"),"result_panel_visible":host.result_panel.visible,"inputs":inputs.duplicate(true)}
	reports.append(report)
	print("P1_HOST_RESULT ",JSON.stringify(report))
	host.queue_free()
	await process_frame

func _send_key(code: int, down: bool) -> void:
	if bool(keys.get(code,false)) == down: return
	keys[code] = down
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	root.push_input(event,true)
	inputs.append({"key":OS.get_keycode_string(code),"down":down,"phase":task.phase,"phase_time":task.phase_time,"game_time":task.game_time})

func _platform_edge(action: StringName, down: bool) -> void:
	_send_key(KEY_D if action == &"ui_right" else KEY_SPACE,down)

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event,true)
		inputs.append({"button":button.name,"down":down,"phase":"prepare"})
		await process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUTPUT+"/%s-%s.png" % [current_id,label]
	var picture := root.get_texture().get_image()
	var error := picture.save_png(path)
	captures.append({"task":current_id,"stage":label,"path":path,"size":[picture.get_width(),picture.get_height()],"save_error":error,"phase":task.phase,"game_time":task.game_time})
