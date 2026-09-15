extends SceneTree

## Deterministic UI fixture only. No microphone, task attempt or discovery writes.
func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var host: HeritageTaskHost = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
	viewport.add_child(host)
	host.context = HeritageTaskRunContext.new()
	host.context.practice_mode = true
	var fixture := HeritageTaskResult.new(HeritageTaskResult.Status.FAILURE, &"huangmei_xi",
		&"line_threshold_not_met", "留意第二句的旋律走向", {"ok": true, "score": 65.0,
		"line_scores": [85.5, 44.5], "completeness": 95.0, "pitch": 50.0, "rhythm": 80.0,
		"details": {"line_completeness": [100.0, 90.0], "line_pitch": [80.0, 20.0],
			"line_rhythm": [90.0, 70.0]}})
	host._show_result(fixture)
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600),
			Vector2i(2048, 1536), Vector2i(3440, 1440)]:
		viewport.size = dimensions
		for frame in 5: await process_frame
		RenderingServer.force_draw(false)
		await process_frame
		var output := "res://artifacts/vocal-result-%dx%d.png" % [dimensions.x, dimensions.y]
		var picture := viewport.get_texture().get_image()
		if picture == null or picture.is_empty():
			push_error("Result preview requires a real renderer")
			quit(1)
			return
		if picture.save_png(output) != OK:
			quit(1)
			return
		print("VOCAL_RESULT_PREVIEW: ", output)
	quit()
