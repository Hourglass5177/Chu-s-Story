extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	add_child(host)
	var definition := load("res://InheritanceTasks/Definitions/tianmen_tang_su.tres") as HeritageTaskDefinition
	var context := HeritageTaskRunContext.new(definition.task_id, null, null, 0, 0, 557, true)
	context.test_mode = true
	context.avatar_id = &"life_blogger"
	context.metadata["skip_tutorial"] = true
	host.configure(definition, context)
	host.begin()
	host.start_from_preparation()
	var task := host.active_task as HeritageStageTask
	var held := false
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if task.phase != HeritageStageTask.Phase.LIVE: continue
		if not held:
			var press := InputEventKey.new()
			press.physical_keycode = KEY_SPACE
			press.keycode = KEY_SPACE
			press.pressed = true
			get_viewport().push_input(press, true)
			held = true
		if task.radius > 0.25:
			await RenderingServer.frame_post_draw
			var frame := task.pixel_stage.get_texture().get_image()
			frame.save_png("res://Tutorial/tangsu_example.png")
			print("TUTORIAL_EXAMPLE_CAPTURE ", frame.get_size())
			host.queue_free()
			await get_tree().process_frame
			get_tree().quit(0)
			return
	push_error("Tutorial example capture timed out")
	get_tree().quit(1)
