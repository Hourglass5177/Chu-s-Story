extends "res://tests/visual/preview_action_story_v3.gd"

func _run() -> void:
	root.content_scale_size = Vector2i(1000,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(1000,600)
	for avatar: StringName in [&"travel_blogger",&"business_blogger"]:
		folder = "res://artifacts/dong-anatomy-motion-v8-final/"+str(avatar)
		DirAccess.make_dir_recursive_absolute(folder)
		var task := _create("dong_yong_chuanshuo",avatar)
		var flat_frame := 0
		var brake_frame := 0
		var brake_started := false
		for tick: int in 30*120:
			Motion.cart(task)
			task._process(DT)
			if task.pose==&"brake": brake_started=true
			if tick%4==0:
				if task.game_time>=3.0 and flat_frame<48:
					await _shot("flat-%03d"%flat_frame)
					flat_frame+=1
				if brake_started and brake_frame<48:
					await _shot("brake-%03d"%brake_frame)
					brake_frame+=1
			if task.run_state==HeritageTaskBase.RunState.FINISHED: break
		print("DONG_MOTION_INPUT ",avatar," time=",task.game_time," stops=",task.mistakes)
		task.queue_free()
		await process_frame
	quit()
