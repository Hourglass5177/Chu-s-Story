extends SceneTree

## Real Host/layout/rendering and ordinary events. Focus isolation is only for
## unattended profiling; production focus behavior is tested separately.
class ProfileHost extends HeritageTaskHost:
	func _set_suspension(reason: StringName, enabled: bool) -> void:
		if reason != &"window_focus": super._set_suspension(reason, enabled)

var host: HeritageTaskHost
var frame_ms: Array[float] = []
var edge_ms: Array[float] = []
var runs: Array = []
var label_name := "before"
var active := false
var previous_usec: int = 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty(): label_name = OS.get_cmdline_user_args()[0]
	HeritageMinigamePreferences.configure_storage_path("user://input-benchmark.cfg")
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if active and previous_usec > 0: frame_ms.append((now-previous_usec)/1000.0)
	previous_usec=now
	return false

func _run() -> void:
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		print("BENCH start ",resolution)
		root.size = resolution
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
		host.set_script(ProfileHost)
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/yandi_shennong_chuanshuo.tres") as HeritageTaskDefinition
		var context := HeritageTaskRunContext.new(definition.task_id)
		context.test_mode = true
		context.metadata.skip_tutorial = true
		host.configure(definition,context)
		host.begin()
		print("BENCH prepared")
		host.start_from_preparation(false)
		print("BENCH started")
		await create_timer(4.0).timeout
		frame_ms.clear(); edge_ms.clear(); active = true
		var rows_before: int = host.hint_rows_created
		var reads_before := HeritageMinigamePreferences.disk_read_count
		for i: int in 180:
			if i%30 == 0: print("BENCH frame ",i)
			var key := InputEventKey.new()
			key.keycode = KEY_D; key.physical_keycode = KEY_D; key.pressed = i%2 == 0
			var t := Time.get_ticks_usec()
			root.push_input(key,true)
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(30,0); motion.position = Vector2(700,400)
			root.push_input(motion,true)
			var pad := InputEventJoypadButton.new()
			pad.button_index = JOY_BUTTON_DPAD_LEFT; pad.pressed = i%2 == 0
			root.push_input(pad,true)
			edge_ms.append((Time.get_ticks_usec()-t)/1000.0)
			await process_frame
		active = false
		frame_ms.sort(); edge_ms.sort()
		runs.append({"size":str(resolution),"measurement":"wall_clock_process_frames","frames":frame_ms.size(),"p95_ms":_p(frame_ms,.95),"p99_ms":_p(frame_ms,.99),"max_ms":frame_ms.max(),"dispatch_p95_ms":_p(edge_ms,.95),"dispatch_p99_ms":_p(edge_ms,.99),"new_hint_rows":host.hint_rows_created-rows_before,"config_reads":HeritageMinigamePreferences.disk_read_count-reads_before,"phase":host.active_task.phase})
		host.cancel(); host.queue_free(); await process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/input-revision")
	FileAccess.open("res://artifacts/input-revision/"+label_name+".json",FileAccess.WRITE).store_string(JSON.stringify(runs,"\t"))
	print(JSON.stringify(runs))
	quit()

func _p(values: Array[float], quantile: float) -> float:
	return values[mini(values.size()-1,floori(values.size()*quantile))]
