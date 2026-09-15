extends SceneTree

## Current-engine walkthrough, actual audio clock + public InputEvents only.
## This is an automated operator, not human listening/play-feel acceptance.
var tasks: Array[String] = ["tujia_saye_erhe","laohekou_si_xian","jingzhou_hua_gu_xi","han_ju","ti_qin_xi","xingshan_min_ge"]
var task: HeritageStageTask
var index: int = -1
var edges: Dictionary = {}
var reports: Array[Dictionary] = []
var captured: bool = false
var paused_once: bool = false
var pause_left: float = 0.0
var total_wall: float = 0.0
var paused_hold: bool = false
var input_trace: Array[Dictionary] = []
var sent_down_count: int = 0
var trace_sequence: int = 0
var current_frame_ms: float = 0.0
var max_frame_ms: float = 0.0
var motion_capture_count: int = 0
var capture_enabled: bool = true

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://artifacts/rework-play")
	var args := OS.get_cmdline_user_args()
	if args.has("--no-captures"):
		capture_enabled=false
		args.erase("--no-captures")
	if not args.is_empty():
		tasks.clear()
		for arg: String in args: tasks.append(arg)
	call_deferred("_next")

func _next() -> void:
	if is_instance_valid(task):
		task.queue_free()
	index += 1
	if index >= tasks.size():
		var file := FileAccess.open("res://artifacts/rework-play/report.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(reports,"\t"))
		var success: bool = true
		for report: Dictionary in reports: success=success and int(report.status)==0
		quit(0 if success else 1)
		return
	var definition := load("res://InheritanceTasks/Definitions/%s.tres" % tasks[index]) as HeritageTaskDefinition
	task = definition.instantiate_task() as HeritageStageTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode=true
	context.metadata["skip_tutorial"]=true
	context.metadata[&"music_chart"]=definition.music_chart
	context.metadata[&"presentation"]=definition.presentation
	context.avatar_id = &"travel_blogger"
	task.configure(context)
	task.task_completed.connect(_finished,CONNECT_ONE_SHOT)
	edges.clear()
	captured=false
	paused_once=false
	paused_hold=false
	pause_left=0
	total_wall=0
	input_trace.clear()
	sent_down_count=0
	trace_sequence=0
	max_frame_ms=0
	motion_capture_count=0
	task.start_task()
	# Public task_input calls below remain ordinary InputEvents. Only this
	# automated fixture ignores unrelated OS events arriving at its window.
	_isolate_os_input(task)

func _process(delta: float) -> bool:
	if not is_instance_valid(task): return false
	current_frame_ms=delta*1000.0
	max_frame_ms=maxf(max_frame_ms,current_frame_ms)
	total_wall+=delta
	if total_wall>75:
		task.complete_technical_error(&"walkthrough_timeout","验证超时")
		return false
	if pause_left>0:
		pause_left-=delta
		if pause_left<=0: task.set_suspended(false)
		return false
	if task.phase!=HeritageStageTask.Phase.LIVE or task.resume_countdown>0: return false
	if capture_enabled and not captured and task.game_time>6:
		captured=true
		_capture.call_deferred()
	if capture_enabled and task is HeritagePerformanceTask and motion_capture_count < 12 and task.game_time >= 5.8 + motion_capture_count * 0.1:
		_capture_motion.call_deferred(motion_capture_count)
		motion_capture_count += 1
	var pause_target: float=5.0 if tasks[index]=="yandi_shennong_chuanshuo" else 10.0
	if task is HeritagePerformanceTask:
		for e: Dictionary in task.chart.events:
			if e.kind=="hold":
				pause_target=int(e.time_ms)/1000.0+0.4
				break
	if not paused_once and task.game_time>pause_target:
		paused_once=true
		paused_hold=task is HeritagePerformanceTask and task.instrument in ["sing","bow"]
		pause_left=0.8
		task.set_suspended(true)
		root.size=Vector2i(1920,1080)
		return false
	if task is HeritagePerformanceTask:
		var performance := task as HeritagePerformanceTask
		var ms: int=roundi(performance.clock.seconds()*1000)
		for i: int in performance.judge.events.size():
			var held_event: Dictionary=performance.judge.events[i]
			var held_state: Dictionary=performance.judge.states[i]
			if held_event.kind=="hold" and held_state.started and not held_state.done and not held_state.down:
				var held_direction: int=int(held_event.direction)
				_send(&"ui_accept" if held_direction==0 else (&"ui_left" if held_direction<0 else &"ui_right"),true,str(held_event.id),-1,"resume")
		for e: Dictionary in performance.chart.events:
			if e.kind=="rest": continue
			var direction: int=int(e.direction)
			if performance.instrument in ["pluck","sing","drum"]: direction=0
			var action: StringName=&"ui_accept" if direction==0 else (&"ui_left" if direction<0 else &"ui_right")
			if ms>=int(e.time_ms) and not edges.has(e.id):
				_send(action,true,str(e.id),int(e.time_ms),"chart")
				edges[e.id]=true
			if ms>=int(e.end_ms)+(60 if e.kind!="hold" else 0) and not edges.has(str(e.id)+"up"):
				_send(action,false,str(e.id),int(e.end_ms)+(60 if e.kind!="hold" else 0),"chart")
				edges[str(e.id)+"up"]=true
	elif tasks[index]=="xingshan_min_ge":
		var desired: float=300
		for gate: Dictionary in task.get("gates"):
			if not gate.done:
				desired=float(gate.y)
				break
		var y: float=task.get("bird_y")
		var speed: float=task.get("vertical_speed")
		if y+speed*0.10>desired+40 and speed>-50:
			_send(&"ui_accept",false)
			_send(&"ui_accept",true)
		elif y<desired-15: _send(&"ui_accept",false)
	elif tasks[index]=="xia_lian_dan_shu":
		_send(&"ui_accept",float(task.get("heat"))+float(task.get("velocity"))*0.13<float(task.get("target")))
	elif tasks[index]=="dong_yong_chuanshuo":
		preload("res://tools/heritage_motion_input_driver.gd").cart(task)
	elif tasks[index]=="tianmen_tang_su":
		var state: int=task.get("blow_phase")
		if state==0: _send(&"ui_accept",true)
		elif state==1:
			_send(&"ui_accept",float(task.get("radius"))<[0.59,0.69,0.62][int(task.get("trial"))])
	elif tasks[index]=="yandi_shennong_chuanshuo":
		preload("res://tools/heritage_motion_input_driver.gd").platform(task,delta,edges)
	elif tasks[index]=="xiabaoping_minjian_gushi" and float(task.get("reveal_left"))<=0.0:
		preload("res://tests/support/action_story_input.gd").solve_scene(task)
	return false

func _send(action: StringName, down: bool, event_id: String = "", scheduled_ms: int = -1, source: String = "operator") -> void:
	var event := InputEventKey.new()
	event.physical_keycode = {&"ui_accept":KEY_SPACE,&"ui_left":KEY_A,&"ui_right":KEY_D,&"ui_up":KEY_W,&"ui_down":KEY_S}.get(action,KEY_SPACE)
	event.keycode = event.physical_keycode
	event.pressed=down
	trace_sequence+=1
	if down: sent_down_count+=1
	var trace: Dictionary={"sequence":trace_sequence,"action":str(action),"down":down,"source":source,
		"event_id":event_id,"scheduled_ms":scheduled_ms,"wall_seconds":total_wall,"frame_delta_ms":current_frame_ms}
	if task is HeritagePerformanceTask:
		trace["audio_ms_before"]=roundi(task.clock.seconds()*1000.0)
		trace["judgment_ms_before"]=task._judgment_ms()
		trace["ghosts_before"]=task.judge.ghosts
	# Same controller entry as focused keyboard/gamepad GUI input.
	task.task_input(event)
	if task is HeritagePerformanceTask:
		trace["judgment_ms_after"]=task._judgment_ms()
		trace["ghosts_after"]=task.judge.ghosts
		trace["last_hit"]=task.judge.last_hit
	input_trace.append(trace)

func _isolate_os_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	if node is Control:
		if node.has_focus(): node.release_focus()
		node.focus_mode=Control.FOCUS_NONE
		node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():_isolate_os_input(child)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image()
	if not screenshot.is_empty(): screenshot.save_png("res://artifacts/rework-play/%s.png" % tasks[index])

func _capture_motion(number: int) -> void:
	var id := tasks[index]
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if not screenshot.is_empty(): screenshot.save_png("res://artifacts/rework-play/%s-motion-%02d.png" % [id, number])

func _finished(result: HeritageTaskResult) -> void:
	var trace_path := "res://artifacts/rework-play/%s-inputs.json"%tasks[index]
	var trace_file := FileAccess.open(trace_path,FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(input_trace,"\t"))
	reports.append({"task":tasks[index],"status":result.status,"reason":result.reason,"metrics":result.metrics,"wall_seconds":total_wall,"normal_input":true,"pause_resize":paused_once,"hold_pause":paused_hold,
		"os_input_isolated":true,"captures_enabled":capture_enabled,"sent_down_count":sent_down_count,"input_trace_path":trace_path,"max_frame_delta_ms":max_frame_ms})
	print("WALKTHROUGH ",JSON.stringify(reports[-1]))
	call_deferred("_next")
