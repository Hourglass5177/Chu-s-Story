extends SceneTree

var host: Control
var captures: Array[Dictionary] = []

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(2560, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/television-ui")
	call_deferred("_inspect")

func _inspect() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	for frame in 5: await process_frame
	var host_scene = load("res://InheritanceTasks/UI/heritage_task_host.tscn")
	host = host_scene.instantiate()
	root.add_child(host)
	var definition = load("res://InheritanceTasks/Definitions/xia_lian_dan_shu.tres")
	var context_class = load("res://InheritanceTasks/Data/heritage_task_run_context.gd")
	var context = context_class.new(definition.task_id, null, null, 0, 0, 77, true)
	host.configure(definition, context)
	host.begin()
	for frame in 5: await process_frame
	await _capture("prepare-1280")
	host.start_from_preparation()
	for frame in 10: await process_frame
	host._on_pause_pressed()
	for frame in 3: await process_frame
	await _capture("pause-1280")
	host._show_settings()
	for frame in 3: await process_frame
	await _capture("settings-1280")
	host._hide_settings()
	host._on_resume_pressed()
	var result_class = load("res://InheritanceTasks/Data/heritage_task_result.gd")
	var result = result_class.new(result_class.Status.FAILURE, &"huangmei_xi", &"line_threshold_not_met", "留意第二句的收尾", {"ok": true,"score":65.0,"line_scores":[85.5,44.5],"completeness":95.0,"pitch":50.0,"rhythm":80.0,"details":{"line_completeness":[100.0,90.0],"line_pitch":[80.0,20.0],"line_rhythm":[90.0,70.0]}})
	host._show_result(result)
	for frame in 5: await process_frame
	await _capture("results-1280")
	root.size = Vector2i(1920,1080)
	for frame in 5: await process_frame
	await _capture("results-1920")
	var file := FileAccess.open("res://artifacts/television-ui/layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(captures, "\t"))
	host.cancel(&"visual_inspection_finished")
	host.queue_free()
	await process_frame
	quit()

func _capture(name_value: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/television-ui/%s.png" % name_value)
	var start: Button = host.get("_start_button")
	captures.append({"name":name_value,"window":str(root.size),"host_size":str(host.size),"screen_scale":host._physical_scale(),"stretch":str(root.get_stretch_transform()),"start_height":start.size.y * host._physical_scale(),"body_font":host.get("_prepare_goal").get_theme_font_size("font_size") * host._physical_scale(),"stage":str(host.task_container.get_global_rect())})
	print("TV_CAPTURE ", captures[-1])
