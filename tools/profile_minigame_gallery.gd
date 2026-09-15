extends SceneTree

## Full menu → gallery → production practice Host. No screenshots/readback in
## the measurement interval; every sample uses monotonic wall-clock time.
var menu: Node
var host: HeritageTaskHost
var samples: Array[Dictionary] = []
var report: Array[Dictionary] = []
var collecting := false
var last_usec := 0
var input_usec := 0
var switched := false
var run_name := "before"

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty(): run_name = OS.get_cmdline_user_args()[0]
	HeritageMinigamePreferences.configure_storage_path("user://gallery-perf-isolated.cfg")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting and last_usec > 0:
		samples.append({"frame_ms":(now-last_usec)/1000.0,"input_ms":input_usec/1000.0,"switch":switched,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
			"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
	last_usec=now
	input_usec=0
	switched=false
	return false

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode=code; e.physical_keycode=code; e.pressed=down
	root.push_input(e,true)

func _pointer(click: bool) -> void:
	var p := host.active_task.get_global_rect().get_center()
	for i: int in 8:
		var motion := InputEventMouseMotion.new()
		motion.position=p+Vector2(i*3,0); motion.global_position=motion.position
		motion.relative=Vector2(4,0)
		root.push_input(motion,true)
	if click:
		for down: bool in [true,false]:
			var e := InputEventMouseButton.new()
			e.position=p; e.global_position=p; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down
			root.push_input(e,true)

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	print("PERF loading menu")
	menu=load("res://main_menu.tscn").instantiate()
	print("PERF add menu")
	root.add_child(menu); current_scene=menu
	print("PERF menu ready")
	for i: int in 5: await process_frame
	print("PERF guide")
	menu.open_game_guide()
	var guide: Node = menu.get_game_guide()
	var reveal := InputEventKey.new()
	reveal.keycode=KEY_D; reveal.ctrl_pressed=true; reveal.shift_pressed=true; reveal.pressed=true
	guide._input(reveal)
	print("PERF gallery")
	guide.open_minigame_gallery()
	print("PERF gallery ready")
	await create_timer(1.0).timeout
	var sizes: Array[Vector2i] = [Vector2i(1920,1080),Vector2i(2560,1600)]
	if run_name.begins_with("final"): sizes.push_front(Vector2i(1280,720))
	for size_value: Vector2i in sizes:
		root.size=size_value
		for id: StringName in [&"yandi_shennong_chuanshuo",&"xia_lian_dan_shu",&"jingzhou_hua_gu_xi"]:
			menu._on_minigame_replay_requested(id)
			host=menu.get("_practice_host")
			await create_timer(.6).timeout
			host.start_from_preparation(false)
			# Same public action as the visible skip-teaching button. Measure LIVE,
			# not an incomplete tutorial that happens to accept the injected keys.
			if host.active_task.is_tutorial_active(): host.active_task.skip_tutorial()
			await create_timer(3.8).timeout
			for mode: String in ["keyboard","alternating"]:
				print("GALLERY_PERF ",id," ",size_value," ",mode)
				samples.clear(); collecting=true
				var rows := host.hint_rows_created
				var reads := HeritageMinigamePreferences.disk_read_count
				var uploads := HeritageTelevisionStyle.texture_upload_count
				var fonts := HeritageTelevisionStyle.font_creation_count
				var start := Time.get_ticks_msec()
				var next_edge := start
				var edge := 0
				var duration := 8000 if run_name.begins_with("final") and mode=="alternating" else 4000
				while Time.get_ticks_msec()-start<duration:
					var t := Time.get_ticks_usec()
					if Time.get_ticks_msec()>=next_edge:
						var old := host.active_task.get_input_device()
						if mode=="alternating" and edge%2==1:
							_key(KEY_D,false); _key(KEY_SPACE,false); _pointer(true)
						else:
							_key(KEY_D,edge%4!=2); _key(KEY_SPACE,edge%4==0)
						if mode=="alternating" and edge%4==3:
							var pad := InputEventJoypadButton.new()
							pad.button_index=JOY_BUTTON_A; pad.pressed=true
							root.push_input(pad,true)
							pad.pressed=false; root.push_input(pad,true)
						switched=old!=host.active_task.get_input_device()
						edge+=1; next_edge+=100
					elif mode=="alternating": _pointer(false)
					input_usec+=Time.get_ticks_usec()-t
					await process_frame
				collecting=false
				_key(KEY_D,false); _key(KEY_SPACE,false)
				var times: Array[float]=[]
				var dispatch: Array[float]=[]
				for sample: Dictionary in samples:
					times.append(sample.frame_ms); dispatch.append(sample.input_ms)
				times.sort(); dispatch.sort()
				var result := {"task":id,"size":str(size_value),"mode":mode,"frames":times.size(),
					"p95_ms":times[floori(times.size()*.95)],"p99_ms":times[floori(times.size()*.99)],"max_ms":times.max(),
					"dispatch_p99_ms":dispatch[floori(dispatch.size()*.99)],"rows_created":host.hint_rows_created-rows,
					"disk_reads":HeritageMinigamePreferences.disk_read_count-reads,"samples":samples.duplicate(true),
					"ui_texture_uploads":HeritageTelevisionStyle.texture_upload_count-uploads,"font_creations":HeritageTelevisionStyle.font_creation_count-fonts,
					"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
					"phase":host.active_task.phase,"suspended":host.active_task.run_state == HeritageTaskBase.RunState.SUSPENDED,"test_mode":host.active_task.context.test_mode}
				report.append(result)
				print("GALLERY_RESULT ",id," ",mode," p99=",result.p99_ms," max=",result.max_ms)
			menu._on_practice_return_requested()
			await create_timer(.3).timeout
	DirAccess.make_dir_recursive_absolute("res://artifacts/performance-gallery")
	FileAccess.open("res://artifacts/performance-gallery/"+run_name+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
