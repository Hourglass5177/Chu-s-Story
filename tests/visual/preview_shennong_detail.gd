extends SceneTree

const Driver = preload("res://tools/heritage_motion_input_driver.gd")
var task: HeritageStageTask
var reports: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var definition := load("res://InheritanceTasks/Definitions/yandi_shennong_chuanshuo.tres") as HeritageTaskDefinition
	var output := "res://artifacts/input-revision/shennong-route"
	DirAccess.make_dir_recursive_absolute(output)
	var jobs: Array[Dictionary]=[]
	for avatar in [&"food_blogger",&"travel_blogger",&"life_blogger",&"business_blogger",&"adventure_blogger",&"magic_blogger"]:
		jobs.append({"avatar":avatar,"size":Vector2i(1280,720)})
	for dimensions in [Vector2i(1920,1080),Vector2i(2560,1600)]:
		jobs.append({"avatar":&"food_blogger","size":dimensions})
	for job in jobs:
		root.size=job.size
		root.content_scale_size=job.size
		task=definition.task_scene.instantiate()
		root.add_child(task)
		task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var context:=HeritageTaskRunContext.new(definition.task_id)
		context.test_mode=true
		context.avatar_id=job.avatar
		context.metadata={"skip_tutorial":true,"host_instruction_overlay":true,"host_controls":true,&"presentation":definition.presentation}
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		var controls:Dictionary={}
		var result:Dictionary={}
		task.task_completed.connect(func(r:HeritageTaskResult):result.merge({"status":r.status,"metrics":r.metrics}),CONNECT_ONE_SHOT)
		for i in 370:task._process(1.0/120.0)
		var next_capture:=1.5
		for frame in 45*60:
			if task.run_state==HeritageTaskBase.RunState.FINISHED:break
			Driver.platform(task,1.0/60.0,controls,false)
			task._process(1.0/60.0)
			if task.game_time>=next_capture:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output+"/%s-%s-%02d.png"%[job.avatar,job.size.x,int(next_capture)])
				next_capture+=8.0
			if job==jobs[0] and frame<72:
				await process_frame
				if frame%3==0:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output+"/motion-%03d.png"%frame)
		result.merge({"avatar":job.avatar,"window":str(job.size),"game_time":task.game_time,"normal_input":true})
		reports.append(result)
		print("SHENNONG_DETAIL ",JSON.stringify(result))
		task.queue_free()
		await process_frame
	var file:=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
	quit(0 if reports.all(func(r):return r.get("status",-1)==HeritageTaskResult.Status.SUCCESS) else 1)
