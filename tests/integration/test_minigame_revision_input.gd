extends GutTest

var viewport: SubViewport
var host: HeritageTaskHost

func before_each() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://revision-input-test.cfg")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)

func after_each() -> void:
	HeritageMinigamePreferences.configure_storage_path()

func _start(id: String) -> HeritageStageTask:
	host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
	viewport.add_child(host)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.test_mode = true
	context.metadata.skip_tutorial = true
	host.configure(load("res://InheritanceTasks/Definitions/%s.tres"%id),context)
	host.begin()
	host.start_from_preparation(false)
	var task := host.active_task as HeritageStageTask
	task.set_process(false)
	task.set_physics_process(false)
	for i: int in 370: task._process(1.0/120.0)
	return task

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode=code; e.physical_keycode=code; e.pressed=down
	viewport.push_input(e,true)

func _mouse(point: Vector2, button: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position=point; e.button_index=button; e.pressed=down
	viewport.push_input(e,true)

func _tick(task: HeritageStageTask, frames: int) -> void:
	for i: int in frames: task._process(1.0/120.0)

func test_host_keyboard_hold_survives_mouse_motion_click_and_another_key_release() -> void:
	var task := _start("yandi_shennong_chuanshuo")
	await wait_process_frames(3)
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	_key(KEY_D,true)
	_tick(task,30)
	assert_gt(task.get("_velocity").x,230.0)
	for i: int in 20:
		var motion := InputEventMouseMotion.new()
		motion.position=task.get_global_rect().get_center(); motion.relative=Vector2(50,0)
		viewport.push_input(motion,true)
		_tick(task,1)
	assert_true(task.pressed[1])
	assert_eq(task.get_input_device(),&"keyboard")
	_key(KEY_RIGHT,true)
	_key(KEY_D,false)
	assert_true(task.pressed[1])
	_mouse(task.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT,true)
	_tick(task,8)
	assert_true(task.pressed[1])
	assert_lt(task.get("_velocity").y,0.0)
	_mouse(Vector2(-20,-20),MOUSE_BUTTON_RIGHT,false)
	assert_false(task.pressed[0])
	_key(KEY_RIGHT,false)
	assert_false(task.pressed[1])
	assert_same(viewport.gui_get_focus_owner(),task)

func test_host_mouse_move_button_and_right_jump_release_outside() -> void:
	var task := _start("yandi_shennong_chuanshuo")
	await wait_process_frames(3)
	var motion := InputEventMouseMotion.new()
	motion.relative=Vector2(50,0); motion.position=task.get_global_rect().get_center()
	viewport.push_input(motion,true)
	await wait_process_frames(2)
	var button: Button = task.get("_mouse_controls")[1]
	assert_true(button.visible)
	assert_eq(button.focus_mode,Control.FOCUS_NONE)
	_mouse(button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
	_tick(task,30)
	assert_gt(task.get("_velocity").x,230.0)
	_mouse(button.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT,true)
	_tick(task,8)
	assert_lt(task.get("_velocity").y,0.0)
	assert_true(task.pressed[1])
	_mouse(Vector2(-20,-20),MOUSE_BUTTON_RIGHT,false)
	_mouse(Vector2(-20,-20),MOUSE_BUTTON_LEFT,false)
	assert_false(task.pressed[0])
	assert_false(task.pressed[1])

func test_device_switch_reuses_hint_rows_and_cached_preferences() -> void:
	var task := _start("yandi_shennong_chuanshuo")
	await wait_process_frames(4)
	var rows: int = host.hint_rows_created
	var reads := HeritageMinigamePreferences.disk_read_count
	for i: int in 12:
		_key(KEY_D,true); _key(KEY_D,false)
		_mouse(task.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT,true)
		_mouse(task.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT,false)
		await wait_process_frames(1)
	assert_eq(host.hint_rows_created,rows)
	assert_eq(HeritageMinigamePreferences.disk_read_count,reads)

func test_hidden_hint_pages_do_not_animate_and_pause_refreshes_current_device() -> void:
	var task := _start("yandi_shennong_chuanshuo")
	await wait_process_frames(4)
	var prepare := host.get("_prepare_hints") as Control
	var pause := host.get("_pause_hints") as Control
	var live := host.get("_play_hints") as Control
	var old_signature: String = prepare.get_meta(&"hint_signature", "")
	var uploads := HeritageTelevisionStyle.texture_upload_count
	var fonts := HeritageTelevisionStyle.font_creation_count
	_mouse(task.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT,true)
	await wait_process_frames(2)
	assert_eq(String(prepare.get_meta(&"hint_signature", "")),old_signature,"Hidden page is not reshaped by the live key.")
	for row: Node in prepare.get_children():
		assert_false(row.get_child(0).is_processing(),"Hidden key animation must stop.")
	assert_eq(HeritageTelevisionStyle.texture_upload_count,uploads,"Input must not upload UI textures.")
	assert_eq(HeritageTelevisionStyle.font_creation_count,fonts,"Input must not duplicate fonts.")
	assert_eq(String(live.get_node("jump").get_child(0).get("glyph")),"mouse_right")
	_mouse(Vector2(-20,-20),MOUSE_BUTTON_RIGHT,false)
	host._on_pause_pressed()
	await wait_process_frames(3)
	assert_true(pause.is_visible_in_tree())
	assert_eq(String(pause.get_node("jump").get_child(0).get("glyph")),"mouse_right","Opening pause refreshes its deferred glyphs.")
	assert_false(live.is_visible_in_tree())

func test_pixel_fonts_and_styles_share_their_cached_render_resources() -> void:
	assert_same(HeritageTelevisionStyle.pixel_font(),HeritageTelevisionStyle.pixel_font())
	assert_same(HeritageTelevisionStyle.pixel_box("button",12.0,2.0),HeritageTelevisionStyle.pixel_box("button",12.0,2.0))
	assert_ne(HeritageTelevisionStyle.pixel_font(),HeritageTelevisionStyle.pixel_font(true))
