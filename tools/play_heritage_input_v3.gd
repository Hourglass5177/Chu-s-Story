extends SceneTree

## Real-time current-engine input walkthrough. The observer reads the visible
## heat/route and sends key/mouse/pad events through Viewport.push_input only.
## No task phase, position, score, clock or result is injected.
const Driver := preload("res://tools/heritage_motion_input_driver.gd")
var scenarios: Array[String] = ["heat_keyboard","shennong_keyboard","shennong_mouse","shennong_gamepad"]
var current := -1
var task: HeritageStageTask
var controls: Dictionary = {}
var edges: Dictionary = {}
var reports: Array[Dictionary] = []
var wall := 0.0
var input_count := 0
var resized_once := false

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	var requested := OS.get_cmdline_user_args()
	if not requested.is_empty(): scenarios.assign(requested)
	DirAccess.make_dir_recursive_absolute("res://artifacts/input-v3-play")
	call_deferred("_next")

func _next() -> void:
	if is_instance_valid(task):
		task.queue_free()
		await process_frame
	current += 1
	if current >= scenarios.size():
		var filename := "report-%s.json" % scenarios[0] if scenarios.size() == 1 else "report.json"
		var file := FileAccess.open("res://artifacts/input-v3-play/" + filename,FileAccess.WRITE)
		file.store_string(JSON.stringify({"method":"Real-time Viewport.push_input key/mouse/gamepad events; original route physics; no visual acceptance inferred","runs":reports},"\t"))
		var ok := not reports.is_empty()
		for report: Dictionary in reports: ok = ok and int(report.status) == HeritageTaskResult.Status.SUCCESS
		quit(0 if ok else 1)
		return
	var scenario := scenarios[current]
	var id := "xia_lian_dan_shu" if scenario.begins_with("heat") else "yandi_shennong_chuanshuo"
	task = load("res://InheritanceTasks/Tasks/%s.tscn" % id).instantiate() as HeritageStageTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = true
	task.configure(context)
	task.task_completed.connect(_finished,CONNECT_ONE_SHOT)
	controls = {"edge_callback":_send_platform}
	edges.clear()
	wall = 0.0
	input_count = 0
	resized_once = false
	task.start_task()
	print("INPUT_V3_START ",scenario)

func _process(delta: float) -> bool:
	if not is_instance_valid(task) or task.run_state == HeritageTaskBase.RunState.FINISHED: return false
	wall += delta
	if wall > 65.0:
		push_error("INPUT_V3_TIMEOUT " + scenarios[current])
		quit(2)
		return false
	if task.phase != HeritageStageTask.Phase.LIVE or task.resume_countdown > 0.0: return false
	if not resized_once and task.game_time > 9.0:
		resized_once = true
		root.size = Vector2i(1920,1080)
	if scenarios[current].begins_with("heat"):
		if task.game_time >= float(controls.get("next_heat_decision",0.0)):
			controls["next_heat_decision"] = task.game_time + 0.12
			var predicted := float(task.heat)+float(task.velocity)*0.13
			var down := bool(edges.get("key:%d" % KEY_SPACE,false))
			if down and predicted > float(task.target)+0.025: down = false
			elif not down and predicted < float(task.target)-0.025: down = true
			_send_key(KEY_SPACE,down)
	else:
		Driver.platform(task,delta,controls)
	return false

func _send_platform(action: StringName, down: bool) -> void:
	match scenarios[current]:
		"shennong_mouse":
			_send_mouse(MOUSE_BUTTON_LEFT if action == &"ui_right" else MOUSE_BUTTON_RIGHT,down)
		"shennong_gamepad":
			var button := JOY_BUTTON_DPAD_RIGHT if action == &"ui_right" else JOY_BUTTON_A
			var key := "pad:%d" % button
			if bool(edges.get(key,false)) == down: return
			edges[key] = down
			var event := InputEventJoypadButton.new()
			event.button_index = button
			event.pressed = down
			root.push_input(event,true)
			input_count += 1
		_:
			_send_key(KEY_D if action == &"ui_right" else KEY_SPACE,down)

func _send_key(code: int, down: bool) -> void:
	var id := "key:%d" % code
	if bool(edges.get(id,false)) == down: return
	edges[id] = down
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	root.push_input(event,true)
	input_count += 1

func _send_mouse(button: int, down: bool) -> void:
	var id := "mouse:%d" % button
	if bool(edges.get(id,false)) == down: return
	edges[id] = down
	var factor := minf(task.size.x/1000.0,task.size.y/600.0)
	# Both buttons can be held while the pointer stays on the movement button.
	var point := (task.size-Vector2(1000,600)*factor)*0.5+Vector2(245,540)*factor
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event,true)
	input_count += 1

func _finished(result: HeritageTaskResult) -> void:
	var report := {"scenario":scenarios[current],"status":result.status,"seconds":task.game_time,"metrics":result.metrics,"input_events":input_count,"resized":resized_once,"last_device":task.get_input_device()}
	reports.append(report)
	print("INPUT_V3_RESULT ",JSON.stringify(report))
	for code: int in [KEY_D,KEY_SPACE]: _send_key(code,false)
	for button: int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: _send_mouse(button,false)
	call_deferred("_next")
