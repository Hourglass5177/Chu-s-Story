extends SceneTree

## Huangmei uses only its art scene here: no microphone or scorer is created.
## Xingshan runs the real audio clock and accepts only ordinary key events.
const OUT := "res://artifacts/pixel-v3/preserved-detail"
var flight: HeritageStageTask
var next_capture: float = 2.0
var motion_capture: int = 0
var wall_time: float = 0.0
var finishing: bool = false
var capture_pending: bool = false

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1000,600)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUT)
	var definition := load("res://InheritanceTasks/Definitions/huangmei_xi.tres") as HeritageTaskDefinition
	for avatar: StringName in HeritageAvatarCatalog.IDS:
		var viewport := HeritagePixelStage.new()
		root.add_child(viewport)
		viewport.configure(definition.presentation,avatar)
		var display := TextureRect.new()
		display.texture = viewport.get_texture()
		display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		display.size = Vector2(1000,600)
		root.add_child(display)
		for pose: StringName in [&"ready",&"prepare",&"hold",&"release",&"success"]:
			viewport.update_state({"listening":false,"action":pose,"animation_time":2.0,"action_time":.9})
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+"/huangmei-%s-%s.png"%[avatar,pose])
		display.queue_free()
		viewport.queue_free()
		await process_frame
	print("HUANGMEI_ART_ONLY six identities x five states; no task, recorder or scorer instantiated")
	definition = load("res://InheritanceTasks/Definitions/xingshan_min_ge.tres") as HeritageTaskDefinition
	flight = definition.instantiate_task() as HeritageStageTask
	root.add_child(flight)
	flight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode = true
	context.avatar_id = &"food_blogger"
	context.metadata = {"skip_tutorial":true,"host_controls":true,"host_instruction_overlay":true,&"presentation":definition.presentation}
	flight.configure(context)
	flight.task_completed.connect(_finished,CONNECT_ONE_SHOT)
	flight.start_task()

func _process(delta: float) -> bool:
	if not is_instance_valid(flight) or finishing: return false
	wall_time += delta
	if wall_time>60.0:
		flight.complete_technical_error(&"preview_timeout","预览超时")
		return false
	if flight.phase!=HeritageStageTask.Phase.LIVE or flight.resume_countdown>0: return false
	var desired := 300.0
	for gate: Dictionary in flight.get("gates"):
		if not bool(gate.done):
			desired=float(gate.y)
			break
	var y := float(flight.get("bird_y"))
	var speed := float(flight.get("vertical_speed"))
	if y+speed*.10>desired+40.0 and speed> -50.0:
		_edge(false)
		_edge(true)
	elif y<desired-15.0: _edge(false)
	if not capture_pending and flight.game_time>=next_capture:
		_capture("xingshan-%02d"%int(next_capture))
		next_capture+=7.0
	elif not capture_pending and flight.game_time>10.0+motion_capture*.05 and motion_capture<36:
		_capture("flock-motion-%02d"%motion_capture)
		motion_capture+=1
	return false

func _edge(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=KEY_SPACE
	event.physical_keycode=KEY_SPACE
	event.pressed=down
	flight.task_input(event)

func _capture(name: String) -> void:
	capture_pending=true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	capture_pending=false

func _finished(result: HeritageTaskResult) -> void:
	finishing=true
	var report := {"status":result.status,"reason":result.reason,"metrics":result.metrics,"real_audio_clock":true,"ordinary_key_input":true,"wall_seconds":wall_time,"huangmei_art_only_no_microphone":true}
	print("PRESERVED_DETAIL ",JSON.stringify(report))
	var file := FileAccess.open(OUT+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	await _capture("xingshan-finish")
	flight.queue_free()
	await process_frame
	quit(0 if result.status==HeritageTaskResult.Status.SUCCESS else 1)
