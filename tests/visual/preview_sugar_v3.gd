extends SceneTree

const OUTPUT := "res://artifacts/sugar-v3-preview"
var host: HeritageTaskHost
var results: Array[Dictionary] = []

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1280,720)
	root.title = "楚物志 · 糖塑六角色输入检查"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_run.call_deferred()

func _run() -> void:
	AudioServer.set_bus_mute(0,true)
	HeritageMinigamePreferences.configure_storage_path("user://sugar_v3_visual.cfg")
	for id: String in ["travel","life","business","food","adventure","magic"]:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
		for i: int in 4: await process_frame
		host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
		root.add_child(host)
		var definition := load("res://InheritanceTasks/Definitions/tianmen_tang_su.tres") as HeritageTaskDefinition
		var context := HeritageTaskRunContext.new(definition.task_id,null,null,0,0,557,true)
		context.test_mode = true
		context.avatar_id = StringName(id+"_blogger")
		context.metadata["skip_tutorial"] = true
		host.configure(definition,context); host.begin()
		await capture(id+"-prepare")
		host.start_from_preparation()
		var task := host.active_task as HeritageStageTask
		var captured := {}
		var held := false
		var deadline := Time.get_ticks_msec()+35000
		while task.run_state != HeritageTaskBase.RunState.FINISHED and Time.get_ticks_msec()<deadline:
			await process_frame
			if task.phase != HeritageStageTask.Phase.LIVE: continue
			if task.blow_phase == 0 and not held:
				key(true); held=true
			if task.blow_phase == 1:
				var threshold: float = [0.35,0.70,0.66][mini(task.trial,2)]
				if task.radius > threshold:
					key(false); held=false
				elif task.radius > 0.25 and not captured.has("hold"):
					captured["hold"]=true; await capture(id+"-hold")
			if task.blow_phase == 2 and task.stage_time > 0.3 and not captured.has("release"):
				captured["release"]=true; await capture(id+"-release")
			if task.blow_phase == 3 and not captured.has("trial%d"%task.trial):
				captured["trial%d"%task.trial]=true; await capture(id+"-trial%d"%task.trial)
		key(false)
		await create_timer(0.6).timeout
		await capture(id+"-result")
		results.append({"avatar":id,"finished":task.run_state==HeritageTaskBase.RunState.FINISHED,
			"successes":task.successes,"outcomes":task.outcomes.duplicate(),"radii":task.outcome_radii.duplicate(),
			"elapsed":task.elapsed_seconds,"input":"normal InputEventKey Space dispatched through viewport; no score/position writes"})
		print("SUGAR_V3_INPUT ",JSON.stringify(results[-1]))
		host.queue_free(); await process_frame
	HeritageMinigamePreferences.configure_storage_path()
	var file:=FileAccess.open(OUTPUT+"/input-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")); file.close()
	quit()

func key(down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = down
	root.push_input(event,true)

func capture(label: String) -> void:
	for i: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+label+".png")
