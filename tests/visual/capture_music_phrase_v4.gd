extends SceneTree

## Actual Host, actual audio clock and ordinary keyboard inputs. Captures one
## practice excerpt at its real timestamps; no score/pose/phase is injected.
const IDS := ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]
const OUT := "res://artifacts/music-motion-v4/"
var ids: Array[String] = []
var index := -1
var host: HeritageTaskHost
var task: HeritagePerformanceTask
var target_step := 0
var sent: Dictionary = {}
var frames: Array[Dictionary] = []
var inputs: Array[Dictionary] = []
var recording := false
var capturing := false
var completing := false
var next_frame := 0.0
var wall := 0.0
var lesson: Dictionary = {}

# This capture-only host can run while the developer inspects screenshots in
# another app. Production Host focus suspension is unchanged and tested apart.
class UnattendedCaptureHost extends HeritageTaskHost:
	func _set_suspension(reason: StringName, enabled: bool) -> void:
		if reason != &"window_focus": super._set_suspension(reason, enabled)

func _initialize() -> void:
	ids.assign(IDS if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args())
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(2560, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	HeritageMinigamePreferences.configure_storage_path("user://music-motion-v4.cfg")
	_next.call_deferred()

func _next() -> void:
	if is_instance_valid(host):
		host.cancel(&"motion_review_complete")
		host.queue_free()
		await process_frame
	index += 1
	if index >= ids.size(): quit(); return
	var id: String = ids[index]
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	for frame: int in 3: await process_frame
	DirAccess.make_dir_recursive_absolute(OUT + id)
	var definition := load("res://InheritanceTasks/Definitions/%s.tres" % id) as HeritageTaskDefinition
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode = true
	context.avatar_id = &"travel_blogger"
	host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	host.set_script(UnattendedCaptureHost)
	root.add_child(host)
	host.configure(definition, context)
	host.begin()
	host.start_from_preparation(true)
	task = host.active_task as HeritagePerformanceTask
	target_step = 1 if id in ["laohekou_si_xian", "jingzhou_hua_gu_xi", "ti_qin_xi"] else 0
	lesson = task.lesson_steps[target_step].duplicate(true)
	sent.clear(); frames.clear(); inputs.clear()
	recording = false; completing = false; next_frame = 0.0; wall = 0.0

func _process(delta: float) -> bool:
	if not is_instance_valid(task) or completing: return false
	wall += delta
	if wall > 140.0 or task.run_state == HeritageTaskBase.RunState.FINISHED:
		push_error("MOTION_REVIEW_FAILED %s phase=%s step=%s round=%s state=%s score=%s suspended=%s" % [ids[index], task.phase, task.lesson_step, task.lesson_round, task.run_state, task.lesson_judge.score(),host._suspension_reasons]); quit(2); return false
	var active := task.phase == HeritageStageTask.Phase.PRACTICE and task.lesson_step == target_step
	if recording and not active:
		completing = true
		_finish.call_deferred()
		return false
	if task.phase != HeritageStageTask.Phase.PRACTICE: return false
	var ms := roundi(task.clock.seconds() * 1000.0)
	if active: recording = true
	for e: Dictionary in task.lesson_judge.events:
		if e.kind == "rest": continue
		var id := "%d:%d:%s" % [task.lesson_step, task.lesson_round, e.id]
		var direction := int(e.direction)
		if task.instrument in ["pluck", "sing", "drum"]: direction = 0
		var code := KEY_A if direction < 0 else (KEY_D if direction > 0 else KEY_SPACE)
		if ms >= int(e.time_ms) and not sent.has(id):
			sent[id] = true; _key(code, true, ms)
		var release := int(e.end_ms) if e.kind == "hold" else int(e.time_ms) + 55
		if ms >= release and not sent.has(id + ":up"):
			sent[id + ":up"] = true; _key(code, false, ms)
	if active and ms >= next_frame and not capturing:
		next_frame = ms + 1000.0 / 24.0
		_capture.call_deferred()
	return false

func _key(code: int, down: bool, ms: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down
	root.push_input(event, true)
	if recording: inputs.append({"time_ms":ms, "key":OS.get_keycode_string(code), "down":down,
		"judged_edges":task.lesson_judge.input_edges.duplicate(true), "judged_states":task.lesson_judge.states.duplicate(true),
		"judgment_ms":task._judgment_ms(), "offset_ms":task.input_offset_ms,
		"phase":task.phase, "round":task.lesson_round})

func _capture() -> void:
	capturing = true
	await RenderingServer.frame_post_draw
	if task.phase != HeritageStageTask.Phase.PRACTICE or task.lesson_step != target_step:
		capturing = false
		return
	var ms := roundi(task.clock.seconds() * 1000.0)
	var filename := "%04d.jpg" % frames.size()
	root.get_texture().get_image().save_jpg(OUT + ids[index] + "/" + filename, .94)
	frames.append({"file":filename, "time_ms":ms, "phase":task.phase, "step":task.lesson_step})
	capturing = false

func _finish() -> void:
	while capturing: await process_frame
	var file := FileAccess.open(OUT + ids[index] + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":ids[index], "lesson":lesson, "frames":frames, "inputs":inputs,
		"method":"Actual Godot Host; real audio clock; Viewport.push_input keyboard; timestamped rendered frames",
		"capture_only_window_focus_isolation":true,
		"window_size":str(root.size), "capture_size":str(root.get_texture().get_size()),
		"practice_step_completed":task.lesson_step > target_step or task.phase == HeritageStageTask.Phase.COUNTDOWN,
		"user_accepted":false, "listening_review":false}, "\t"))
	print("MOTION_REVIEW_CAPTURE ", ids[index], " frames=",frames.size(), " inputs=",inputs.size())
	_next.call_deferred()
