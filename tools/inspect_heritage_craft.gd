extends SceneTree

## Visual capture only. Huangmei uses an unavailable capture adapter; no device opens.
class PreviewScorer extends VocalScorer:
	func is_available() -> bool: return true
	func begin_capture(_id: StringName, _duration: float) -> Error: return ERR_UNAVAILABLE

var host: Control

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/craft-pixel-ui")
	call_deferred("_inspect")

func _inspect() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame: int in 5: await process_frame
	for id: StringName in [&"tianmen_tang_su",&"gu_pen_ge",&"ezhou_diaohua_jianzhi",&"huangmei_xi"]:
		var host_scene = load("res://InheritanceTasks/UI/heritage_task_host.tscn")
		host = host_scene.instantiate()
		root.add_child(host)
		var definition = load("res://InheritanceTasks/Definitions/%s.tres" % id)
		var context_class = load("res://InheritanceTasks/Data/heritage_task_run_context.gd")
		var context = context_class.new(id,null,null,0,0,91,true)
		context.avatar_id = &"travel_blogger"
		context.metadata["skip_tutorial"] = true
		if id == &"huangmei_xi": context.services[&"vocal_scorer"] = PreviewScorer.new()
		host.configure(definition,context)
		host.begin()
		for frame: int in 3: await process_frame
		host.start_from_preparation()
		for frame: int in 16: await process_frame
		await _capture(str(id)+"-start")
		if id == &"huangmei_xi":
			# Lifecycle preview of the open curtain; it never reaches microphone opening.
			host.active_task.call("_enter_countdown")
			host.active_task.set_process(false)
			host.active_task.queue_redraw()
			for frame: int in 3: await process_frame
			await _capture(str(id)+"-curtain-open")
		for avatar: StringName in [&"travel_blogger",&"life_blogger",&"business_blogger",&"food_blogger",&"adventure_blogger",&"magic_blogger"]:
			if is_instance_valid(host.active_task.pixel_stage):
				host.active_task.pixel_stage.avatar_id = avatar
				host.active_task.pixel_stage.canvas.avatar_id = avatar
				host.active_task.queue_redraw()
				for frame: int in 3: await process_frame
				await _capture(str(id)+"-"+str(avatar))
		host.cancel(&"visual_preview_complete")
		host.queue_free()
		await process_frame
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/craft-pixel-ui/%s.png" % label)
	print("CRAFT_VISUAL ",label)
