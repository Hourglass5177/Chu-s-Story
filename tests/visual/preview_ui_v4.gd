extends SceneTree

const OUTPUT := "res://artifacts/ui-v4-preview"
var host: HeritageTaskHost

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1280,720)
	root.title = "楚物志 · 小游戏界面检查"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_run.call_deferred()

func _run() -> void:
	AudioServer.set_bus_mute(0,true)
	HeritageMinigamePreferences.configure_storage_path("user://ui_v4_visual.cfg")
	for i: int in 5: await process_frame
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		for i: int in 5: await process_frame
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/xia_lian_dan_shu.tres") as HeritageTaskDefinition
		var context := HeritageTaskRunContext.new(definition.task_id,null,null,0,0,558,true)
		context.test_mode = true
		host.configure(definition,context); host.begin()
		await capture("prepare-%d" % dimensions.x)
		host.start_from_preparation(true)
		await capture("teaching-%d" % dimensions.x)
		host._on_pause_pressed(); host._show_settings()
		await capture("settings-%d" % dimensions.x)
		host._show_bindings()
		await capture("bindings-%d" % dimensions.x)
		for child: Node in host.get("_bindings_box").get_children():
			if child is Control: print("BINDING_RECT ",child.name," ",child.get_global_rect()," ",child.visible)
		host.cancel(&"ui_capture_finished"); host.queue_free()
		await process_frame
		var guide: Node = load("res://UI/GameGuide/digital_game_guide.tscn").instantiate()
		root.add_child(guide)
		guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.MAIN_MENU),false)
		guide.set("_developer_view_enabled",true)
		guide.open_minigame_gallery()
		await capture("gallery-%d" % dimensions.x)
		guide.set("_developer_view_enabled",false)
		guide.close_guide(false); guide.queue_free()
		await process_frame
	HeritageMinigamePreferences.configure_storage_path()
	quit()

func capture(label: String) -> void:
	for i: int in 7: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")
	print("UI_V4_CAPTURE ",label)
