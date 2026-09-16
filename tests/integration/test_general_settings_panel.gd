extends GutTest

var viewport: SubViewport
var panel: GameSettingsPanel
var saved_values: Dictionary
var saved_path: String
var saved_dirty: bool
var test_path: String

func before_each() -> void:
	saved_values = Settings.values.duplicate(true)
	saved_path = Settings.storage_path
	saved_dirty = Settings.dirty
	test_path = "user://settings_panel_test_%d.cfg" % Time.get_ticks_usec()
	Settings.storage_path = test_path
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.dirty = false
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)
	panel = GameSettingsPanel.mount(viewport)
	await wait_process_frames(2)
	panel.open_panel()
	await wait_process_frames(2)

func after_each() -> void:
	panel.close_panel(true)
	Settings._save_timer.stop()
	Settings.values = saved_values
	Settings.storage_path = saved_path
	Settings.dirty = saved_dirty
	Settings.last_save_error = OK
	if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)

func _key(key: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		viewport.push_input(event,true)
		await wait_process_frames(1)

func test_keyboard_slider_and_focus_stay_in_panel() -> void:
	panel._controls["master_volume"].grab_focus()
	await _key(KEY_LEFT)
	assert_eq(Settings.get_value("master_volume"),95)
	for index in range(20):
		await _key(KEY_TAB)
		assert_true(panel.is_ancestor_of(viewport.gui_get_focus_owner()))
	await _key(KEY_ESCAPE)
	assert_false(panel.visible)

func test_gamepad_accept_and_return_use_local_mapping() -> void:
	panel.show_page("accessibility")
	await wait_process_frames(2)
	panel._controls["reduce_motion"].grab_focus()
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_A
		event.pressed = pressed
		viewport.push_input(event,true)
		await wait_process_frames(2)
	assert_true(Settings.get_value("reduce_motion"))
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	viewport.push_input(back,true)
	await wait_process_frames(2)
	assert_false(panel.visible)

func test_late_gamepad_event_cannot_enter_reopened_panel() -> void:
	panel.show_page("accessibility")
	panel._controls["reduce_motion"].grab_focus()
	panel._queue_action(&"ui_accept",true)
	panel._queue_action(&"ui_accept",false)
	panel.close_panel()
	panel.open_panel()
	panel._controls["reduce_motion"].grab_focus()
	await wait_process_frames(3)
	assert_false(Settings.get_value("reduce_motion"))

func test_display_confirmation_consumes_one_escape_and_keeps_settings_open() -> void:
	Settings.preview_display(1)
	await wait_process_frames(2)
	assert_true(panel._confirm_layer.visible)
	await _key(KEY_ESCAPE)
	assert_false(Settings.preview_active)
	assert_false(panel._confirm_layer.visible)
	assert_true(panel.visible)
	assert_eq(Settings.get_value("display_mode"),0)

func test_panel_fits_each_supported_size_and_updates_without_recreation() -> void:
	var original_id: int = panel._controls["master_volume"].get_instance_id()
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		viewport.size = resolution
		await wait_process_frames(3)
		assert_true(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(panel._paper.get_global_rect()))
		for page: String in ["audio","display","accessibility"]:
			panel.show_page(page)
			await wait_process_frames(2)
			assert_true(panel._paper.get_global_rect().encloses(panel.find_child("SettingsDone",true,false).get_global_rect()))
	assert_eq(panel._controls["master_volume"].get_instance_id(),original_id)

func test_forced_owner_exit_closes_settings_even_when_save_fails() -> void:
	Settings.storage_path = test_path + "/missing/settings.cfg"
	Settings.set_value("master_volume",50)
	panel.close_panel()
	assert_true(panel.visible)
	assert_true(panel._status.text.contains("未能保存"))
	panel.close_panel(true)
	assert_false(panel.visible)
	Settings.storage_path = test_path
