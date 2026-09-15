extends SceneTree

## Authored static covers rendered with the production stage. This is asset
## composition, not a recorded playthrough or a success-verification fixture.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size=Vector2i(1000,600)
	root.content_scale_size=Vector2i(1000,600)
	var folder := "res://InheritanceTasks/Art/Pixel/v3/runtime/revision-covers"
	DirAccess.make_dir_recursive_absolute(folder)
	for id: String in ["xisai_shenzhou_hui","xingshan_min_ge"]:
		var definition := load("res://InheritanceTasks/Definitions/%s.tres"%id) as HeritageTaskDefinition
		for avatar: StringName in HeritageAvatarCatalog.IDS:
			var canvas := definition.presentation.stage_scene.instantiate() as HeritagePixelCanvas
			canvas.artwork=definition.presentation
			canvas.avatar_id=avatar
			root.add_child(canvas)
			canvas.size=Vector2(1000,600)
			var state: Dictionary = {"animation_time":0.0,"lane":1.0,"distance":0.0,"speed":200.0,
				"obstacles":[{"lane":0,"gap":360.0,"kind":"boat"},{"lane":2,"gap":570.0,"kind":"boat"}],
				"music_time":41.0,"bird_y":230.0,"bird_pose":"glide","gates":[],"followers":[]}
			canvas.receive_visual_state(state)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/%s-%s.png"%[id,avatar])
			canvas.queue_free()
			await process_frame
	quit()
