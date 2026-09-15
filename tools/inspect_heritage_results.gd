extends SceneTree

## Paper is completed via normal pointer events. Huangmei below is synthetic UI
## data only, explicitly excluding microphone capture and vocal score validation.
class NoCapturePreview extends VocalScorer:
	func is_available() -> bool: return true
	func begin_capture(_id: StringName,_duration: float) -> Error: return ERR_UNAVAILABLE

var host: Control

func _initialize() -> void:
	root.content_scale_size = Vector2i(2560,1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute("res://artifacts/craft-pixel-ui")
	call_deferred("_inspect")

func _inspect() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	for frame: int in 5: await process_frame
	await _open(&"ezhou_diaohua_jianzhi")
	var task = host.active_task
	var path: PackedVector2Array = task.get("_path")
	var transform: Transform2D = task.get_global_transform()
	_click(transform*path[0],true)
	for segment: int in path.size()-1:
		for sample: int in 40:
			var event := InputEventMouseMotion.new()
			event.position = transform*path[segment].lerp(path[segment+1],float(sample+1)/40.0)
			event.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(event,true)
			await process_frame
	_click(transform*path[-1],false)
	for frame: int in 5: await process_frame
	await _capture("paper-normal-input-result")
	print("PAPER_NORMAL_INPUT ",host.result_title.text," progress=",task.progress)
	host.cancel(&"preview_complete")
	host.queue_free()
	await process_frame
	await _open(&"huangmei_xi")
	host.active_task.call("_enter_countdown")
	host.active_task.complete_success({"ok":true,"score":72.5,"line_scores":[73.0,72.0],"completeness":90.0,"pitch":70.0,"rhythm":72.0,"details":{"line_completeness":[90.0,90.0],"line_pitch":[70.0,70.0],"line_rhythm":[72.0,72.0]}},"两句都接上了（界面预览数据）")
	for frame: int in 5: await process_frame
	await _capture("huangmei-synthetic-result-layout")
	host.cancel(&"preview_complete")
	host.queue_free()
	await process_frame
	quit()

func _open(id: StringName) -> void:
	var scene = load("res://InheritanceTasks/UI/heritage_task_host.tscn")
	host = scene.instantiate()
	root.add_child(host)
	var definition = load("res://InheritanceTasks/Definitions/%s.tres" % id)
	var context_class = load("res://InheritanceTasks/Data/heritage_task_run_context.gd")
	var context = context_class.new(id,null,null,0,0,88,true)
	context.metadata["skip_tutorial"] = true
	if id == &"huangmei_xi": context.services[&"vocal_scorer"] = NoCapturePreview.new()
	host.configure(definition,context)
	host.begin()
	for frame: int in 3: await process_frame
	host.start_from_preparation()
	for frame: int in 3: await process_frame

func _click(point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	root.push_input(event,true)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/craft-pixel-ui/%s.png" % label)
	print("RESULT_LAYOUT ",label," return=",host.return_button.get_global_rect()," art=",host.get("_result_art").get_global_rect())
