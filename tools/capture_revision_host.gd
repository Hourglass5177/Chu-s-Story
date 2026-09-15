extends SceneTree

class CaptureHost extends HeritageTaskHost:
	func _set_suspension(reason: StringName, enabled: bool) -> void:
		if reason != &"window_focus": super._set_suspension(reason,enabled)

var host: HeritageTaskHost
var folder := "res://artifacts/input-revision/screens"

func _initialize() -> void:
	root.content_scale_size=Vector2i(2560,1600)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	HeritageMinigamePreferences.configure_storage_path("user://revision-capture.cfg")
	_run.call_deferred()

func _make(id: String, teaching: bool = false) -> void:
	if is_instance_valid(host):
		host.cancel(); host.queue_free(); await process_frame
	host=load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
	host.set_script(CaptureHost)
	root.add_child(host)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode=true
	context.avatar_id=&"food_blogger"
	context.metadata.skip_tutorial=not teaching
	host.configure(load("res://InheritanceTasks/Definitions/%s.tres"%id),context)
	host.begin()
	await process_frame

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
	print("CAPTURE ",name)

func _key(code: Key, down: bool) -> void:
	var e:=InputEventKey.new()
	e.keycode=code;e.physical_keycode=code;e.pressed=down
	root.push_input(e,true)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		root.size=resolution
		await _make("xiabaoping_minjian_gushi")
		await create_timer(.3).timeout
		await _shot("prepare-"+str(resolution.x))
	root.size=Vector2i(1280,720)
	await _make("yandi_shennong_chuanshuo")
	host.start_from_preparation(false)
	await create_timer(.3).timeout
	await _shot("countdown")
	await create_timer(2.85).timeout
	await _shot("start")
	_key(KEY_D,true)
	for i: int in 12:
		await create_timer(.06).timeout
		await _shot("run-%02d"%i)
	_key(KEY_SPACE,true)
	await create_timer(.12).timeout
	await _shot("jump")
	_key(KEY_SPACE,false);_key(KEY_D,false)
	await _make("laohekou_si_xian",true)
	host.start_from_preparation(true)
	await create_timer(1.6).timeout
	await _shot("teaching")
	await _make("xisai_shenzhou_hui")
	host.start_from_preparation(false)
	await create_timer(3.6).timeout
	await _shot("boat")
	host.cancel()
	quit()
