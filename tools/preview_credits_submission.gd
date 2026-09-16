extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await create_timer(1.0).timeout
	menu.call("_show_credits_modal", null)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/credits-submission/credits-1280.png")
	print("CREDITS_PREVIEW_COMPLETE")
	menu.queue_free()
	await process_frame
	quit()
