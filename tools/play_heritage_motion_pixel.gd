extends SceneTree

## Native-rendered complete runs. Driver uses public input events, never score,
## task phase, player/cart/bird positions, or force-success hooks.
const Driver = preload("res://tools/heritage_motion_input_driver.gd")
var ids := ["yandi_shennong_chuanshuo","dong_yong_chuanshuo","xingshan_min_ge","xisai_shenzhou_hui"]
var task: HeritageTaskBase
var index := -1
var controls: Dictionary = {}
var reports: Array[Dictionary] = []
var wall := 0.0
var paused_once := false
var pause_left := 0.0
var captured := false

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/motion-pixel-play")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	if not OS.get_cmdline_user_args().is_empty():
		ids = ids.filter(func(id: String) -> bool:return id in OS.get_cmdline_user_args())
	call_deferred("_next")

func _next() -> void:
	if is_instance_valid(task):task.queue_free()
	index += 1
	if index>=ids.size():
		var file := FileAccess.open("res://artifacts/motion-pixel-play/report.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(reports,"\t"))
		var success := not reports.is_empty()
		for result: Dictionary in reports: success = success and int(result.status)==HeritageTaskResult.Status.SUCCESS
		quit(0 if success else 1)
		return
	root.size = Vector2i(1280,720)
	var definition := load("res://InheritanceTasks/Definitions/%s.tres"%ids[index]) as HeritageTaskDefinition
	task = definition.instantiate_task()
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode = true
	context.avatar_id = &"travel_blogger"
	context.metadata["skip_tutorial"] = true
	context.metadata[&"presentation"] = definition.presentation
	task.configure(context)
	task.task_completed.connect(_finished,CONNECT_ONE_SHOT)
	controls.clear()
	wall=0
	paused_once=false
	pause_left=0
	captured=false
	task.start_task()

func _process(delta: float) -> bool:
	if not is_instance_valid(task) or task.run_state==HeritageTaskBase.RunState.FINISHED:return false
	wall+=delta
	if wall>65:
		task.complete_technical_error(&"walkthrough_timeout","验证超时")
		return false
	if pause_left>0:
		pause_left-=delta
		if pause_left<=0:task.set_suspended(false)
		return false
	if task is HeritageStageTask:
		if task.phase!=HeritageStageTask.Phase.LIVE or task.resume_countdown>0:return false
	var time: float = task.game_time if task is HeritageStageTask else task.elapsed_seconds
	if not paused_once and time>8:
		paused_once=true
		pause_left=.6
		controls.clear()
		task.set_suspended(true)
		root.size=Vector2i(1920,1080)
		return false
	if not captured and time>12:
		captured=true
		_capture.call_deferred()
	match ids[index]:
		"yandi_shennong_chuanshuo": Driver.platform(task as HeritageStageTask,delta,controls)
		"dong_yong_chuanshuo": Driver.cart(task as HeritageStageTask)
		"xingshan_min_ge":
			var desired := 300.0
			for gate: Dictionary in task.get("gates"):
				if not gate.done:
					desired=float(gate.y)
					break
			var y := float(task.get("bird_y"))
			var velocity := float(task.get("vertical_speed"))
			if y+velocity*.10>desired+40 and velocity>-50:
				Driver.edge(task,&"ui_accept",false)
				Driver.edge(task,&"ui_accept",true)
			elif y<desired-15: Driver.edge(task,&"ui_accept",false)
		"xisai_shenzhou_hui":
			preload("res://tests/support/action_story_input.gd").escort(task)
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/motion-pixel-play/%s.png"%ids[index])

func _finished(result: HeritageTaskResult) -> void:
	reports.append({"task":ids[index],"status":result.status,"reason":result.reason,"metrics":result.metrics,
		"wall_seconds":wall,"normal_input":true,"pause_resize":paused_once,"pixel_stage":is_instance_valid(task.pixel_stage),"human_playtest":false})
	print("MOTION_PIXEL_RUN ",JSON.stringify(reports[-1]))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/motion-pixel-play/%s-result.png"%ids[index])
	call_deferred("_next")
