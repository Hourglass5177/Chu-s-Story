extends SceneTree

## Actual preparation/tutorial Host, kept separate from standalone input replays.
const TASKS := ["laohekou_si_xian","tujia_saye_erhe","jingzhou_hua_gu_xi","han_ju","ti_qin_xi","gu_pen_ge"]
const OUTPUT := "res://artifacts/music-host-v4/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	AudioServer.set_bus_mute(0,true)
	HeritageMinigamePreferences.configure_storage_path("user://music_host_visual_v3.cfg")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		for frame: int in 5: await process_frame
		for id: String in TASKS:
			var definition := load("res://InheritanceTasks/Definitions/"+id+".tres") as HeritageTaskDefinition
			var context := HeritageTaskRunContext.new(definition.task_id)
			context.test_mode = true
			context.avatar_id = &"travel_blogger"
			var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
			root.add_child(host)
			host.configure(definition,context)
			host.begin()
			await _shot(id+"-prepare-%d"%dimensions.x)
			host.start_from_preparation(true)
			await _shot(id+"-teaching-%d"%dimensions.x)
			host.cancel(&"visual_review_finished")
			host.queue_free()
			await process_frame
	HeritageMinigamePreferences.configure_storage_path()
	quit()

func _shot(name: String) -> void:
	for frame: int in 7: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
	print("MUSIC_HOST_CAPTURE ",name)
