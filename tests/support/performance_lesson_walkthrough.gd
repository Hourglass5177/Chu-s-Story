extends SceneTree

## 真实 AudioStream 时钟与普通 InputEvent 教学回放。
## 自动操作验证可运行性，不替代真人听审和教学可理解性验收。
var tasks: Array[String] = ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]
var current: int = -1
var task: HeritagePerformanceTask
var sent: Dictionary = {}
var reports: Array[Dictionary] = []
var wall_time: float = 0.0
var completing: bool = false

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://artifacts/performance-lessons")
	HeritageMinigamePreferences.configure_storage_path("user://performance-lesson-walkthrough.cfg")
	call_deferred("_next")

func _next() -> void:
	if is_instance_valid(task):
		task.cancel_external(&"walkthrough_cleanup")
		task.queue_free()
	current += 1
	if current >= tasks.size():
		var file := FileAccess.open("res://artifacts/performance-lessons/report.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(reports, "\t"))
		var all_passed: bool = true
		for report: Dictionary in reports: all_passed = all_passed and report.lesson_passed
		quit(0 if all_passed else 1)
		return
	var definition := load("res://InheritanceTasks/Definitions/%s.tres" % tasks[current]) as HeritageTaskDefinition
	task = definition.instantiate_task() as HeritagePerformanceTask
	root.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(definition.task_id, null, null, 0, 0, 1, true)
	context.test_mode = true
	context.metadata[&"music_chart"] = definition.music_chart
	context.metadata[&"presentation"] = definition.presentation
	context.metadata[&"skip_tutorial"] = false
	task.configure(context)
	sent.clear()
	wall_time = 0.0
	completing = false
	task.start_task()

func _process(delta: float) -> bool:
	if not is_instance_valid(task) or completing: return false
	wall_time += delta
	if task.run_state == HeritageTaskBase.RunState.FINISHED or wall_time > 150.0:
		_complete(false)
		return false
	if task.phase == HeritageStageTask.Phase.COUNTDOWN:
		_complete(true)
		return false
	if task.phase != HeritageStageTask.Phase.PRACTICE: return false
	var ms: int = roundi(task.clock.seconds() * 1000.0)
	for event: Dictionary in task.lesson_judge.events:
		if event.kind == "rest": continue
		var direction: int = int(event.direction)
		if task.instrument in ["pluck", "sing", "drum"]: direction = 0
		var action: StringName = &"ui_left" if direction < 0 else (&"ui_right" if direction > 0 else &"ui_accept")
		var input_id := "%d:%d:%s" % [task.lesson_step, task.lesson_round, event.id]
		if ms >= int(event.time_ms) and not sent.has(input_id):
			sent[input_id] = true
			_edge(action, true)
		var release_ms: int = int(event.end_ms) if event.kind == "hold" else int(event.time_ms) + 50
		if ms >= release_ms and not sent.has(input_id + "-up"):
			sent[input_id + "-up"] = true
			_edge(action, false)
	return false

func _edge(action: StringName, down: bool) -> void:
	var event := InputEventKey.new()
	var code := KEY_A if action == &"ui_left" else (KEY_D if action == &"ui_right" else KEY_SPACE)
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	root.push_input(event, true)

func _complete(passed: bool) -> void:
	completing = true
	var report := {"task": tasks[current], "lesson_passed": passed, "score": task.lesson_judge.score(),
		"ghost_inputs": task.lesson_judge.ghosts, "wall_seconds": wall_time, "normal_input": true,
		"real_audio_clock": true, "human_listening_review": false}
	reports.append(report)
	print("LESSON_WALKTHROUGH ", JSON.stringify(report))
	call_deferred("_next")
