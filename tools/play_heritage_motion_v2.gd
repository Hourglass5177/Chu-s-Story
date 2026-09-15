extends SceneTree

const Driver = preload("res://tools/heritage_motion_input_driver.gd")
var task: HeritageStageTask
var jobs: Array[Dictionary] = []
var job_index: int = -1
var controls: Dictionary = {}
var reports: Array[Dictionary] = []
var wall_seconds: float = 0.0
var paused_once: bool = false
var pause_left: float = 0.0
var captured: bool = false

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/motion-v2-play")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		for id: String in ["yandi_shennong_chuanshuo","dong_yong_chuanshuo"]:
			jobs.append({"id":id,"size":size,"mistake":false})
	jobs.append({"id":"yandi_shennong_chuanshuo","size":Vector2i(1280,720),"mistake":true})
	jobs.append({"id":"dong_yong_chuanshuo","size":Vector2i(1280,720),"mistake":true})
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		jobs = jobs.filter(func(job: Dictionary) -> bool: return str(job.id) in args)
	call_deferred("_next")

func _next() -> void:
	if is_instance_valid(task): task.queue_free()
	job_index += 1
	if job_index >= jobs.size():
		var output := FileAccess.open("res://artifacts/motion-v2-play/report.json",FileAccess.WRITE)
		output.store_string(JSON.stringify(reports,"\t"))
		var passed: bool = not reports.is_empty()
		for report: Dictionary in reports: passed = passed and int(report.status)==HeritageTaskResult.Status.SUCCESS
		quit(0 if passed else 1)
		return
	var job: Dictionary = jobs[job_index]
	root.size = job.size
	root.content_scale_size = job.size
	task = load("res://InheritanceTasks/Tasks/%s.tscn" % job.id).instantiate() as HeritageStageTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(StringName(job.id))
	context.test_mode = true
	context.metadata["skip_tutorial"] = true
	task.configure(context)
	task.task_completed.connect(_finished,CONNECT_ONE_SHOT)
	controls.clear()
	wall_seconds = 0
	paused_once = false
	pause_left = 0
	captured = false
	task.start_task()

func _process(delta: float) -> bool:
	if not is_instance_valid(task) or task.run_state==HeritageTaskBase.RunState.FINISHED: return false
	wall_seconds += delta
	if wall_seconds > 60:
		task.complete_technical_error(&"walkthrough_timeout","操作验证超时")
		return false
	if pause_left > 0:
		pause_left -= delta
		if pause_left <= 0: task.set_suspended(false)
		return false
	if task.phase != HeritageStageTask.Phase.LIVE or task.resume_countdown > 0: return false
	if not paused_once and task.game_time > 6:
		paused_once = true
		pause_left = 0.6
		task.set_suspended(true)
		controls.clear()
		root.size = Vector2i(jobs[job_index].size)*0.8
		return false
	if not captured and task.game_time > 12:
		captured = true
		_capture.call_deferred()
	if jobs[job_index].id == "yandi_shennong_chuanshuo": Driver.platform(task,delta,controls,bool(jobs[job_index].mistake))
	else: Driver.cart(task,bool(jobs[job_index].mistake))
	return false

func _capture() -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if not screenshot.is_empty(): screenshot.save_png("res://artifacts/motion-v2-play/%02d-%s.png" % [job_index,jobs[job_index].id])

func _finished(result: HeritageTaskResult) -> void:
	var job: Dictionary = jobs[job_index]
	reports.append({"task":job.id,"viewport":str(job.size),"planned_mistake":job.mistake,
		"status":result.status,"reason":result.reason,"metrics":result.metrics,
		"wall_seconds":wall_seconds,"pause_resize":paused_once,"normal_input":true,
		"human_playtest":false,"rendered":DisplayServer.get_name()!="headless"})
	print("MOTION_V2_WALKTHROUGH ",JSON.stringify(reports[-1]))
	call_deferred("_next")
