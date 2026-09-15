extends SceneTree

## UI-only inspection: fabricated result states are labelled in the capture list.
## This does not demonstrate a successful gameplay run or record microphone input.
var host: HeritageTaskHost
var captures: Array[Dictionary] = []
const OUTPUT := "res://artifacts/pixel-host-v2"


func _initialize() -> void:
	root.content_scale_size = Vector2i(2560, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1280, 720)
	root.title = "楚物志 · 像素宿主界面检查"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_inspect.call_deferred()


func _inspect() -> void:
	AudioServer.set_bus_mute(0, true)
	HeritageMinigamePreferences.configure_storage_path("user://pixel_host_v2_inspection.cfg")
	for frame: int in 5: await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	for frame: int in 5: await process_frame
	for task_id: StringName in [&"xia_lian_dan_shu", &"yandi_shennong_chuanshuo"]:
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/%s.tres" % task_id).duplicate() as HeritageTaskDefinition
		definition.presentation = definition.presentation.duplicate() as HeritageTaskPresentation
		definition.presentation.version = 2
		var context := HeritageTaskRunContext.new(task_id, null, null, 0, 0, 809, true)
		context.avatar_id = &"travel_blogger"
		host.configure(definition, context)
		host.begin()
		await capture(String(task_id) + "-prepare-1280")
		host.start_from_preparation(true)
		await capture(String(task_id) + "-teaching-1280")
		while String(host.active_task.call("get_instruction_state").get("phase", "")) == "demo":
			await process_frame
		await capture(String(task_id) + "-practice-1280")
		host._on_pause_pressed()
		await capture(String(task_id) + "-pause-1280")
		host._show_settings()
		await capture(String(task_id) + "-settings-1280")
		host._hide_settings()
		host._show_result(HeritageTaskResult.failure(task_id, &"ui_inspection", "还差一点，再试一次"))
		await capture(String(task_id) + "-result-layout-only-1280")
		host._show_result(HeritageTaskResult.technical_error(task_id, &"ui_inspection", "素材暂时无法读取，请返回后重试"))
		await capture(String(task_id) + "-error-layout-only-1280")
		host.cancel(&"ui_inspection_finished")
		host.queue_free()
		await process_frame
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1600)]:
		root.size = dimensions
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/xia_lian_dan_shu.tres").duplicate() as HeritageTaskDefinition
		definition.presentation = definition.presentation.duplicate() as HeritageTaskPresentation
		definition.presentation.version = 2
		host.configure(definition, HeritageTaskRunContext.new(definition.task_id, null, null, 0, 0, 809, true))
		host.begin()
		await capture("prepare-" + str(dimensions.x))
		host.cancel(&"ui_inspection_finished")
		host.queue_free()
		await process_frame
	var report := FileAccess.open(OUTPUT + "/layout.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(captures, "\t"))
	HeritageMinigamePreferences.configure_storage_path()
	quit()


func capture(label: String) -> void:
	for frame: int in 7: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")
	captures.append({"name": label, "window": str(root.size), "integer_scale": host.get("_pixel_integer_scale"), "physical_scale": host._physical_scale(), "screen": str(host.task_container.get_global_rect()), "button_px": (host.get("_start_button") as Control).size.y * host._physical_scale(), "body_font_px": (host.get("_prepare_goal") as Control).get_theme_font_size("font_size") * host._physical_scale()})
	print("PIXEL_HOST_CAPTURE ", label)
