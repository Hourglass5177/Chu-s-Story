extends GutTest

const HOST := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
var viewport: SubViewport


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)


func make_host(version: int = 2) -> HeritageTaskHost:
	var host := HOST.instantiate() as HeritageTaskHost
	viewport.add_child(host)
	var definition := HeritageTaskManager.get_definition(&"xia_lian_dan_shu").duplicate() as HeritageTaskDefinition
	definition.presentation = definition.presentation.duplicate() as HeritageTaskPresentation
	definition.presentation.version = version
	var context := HeritageTaskRunContext.new(definition.task_id, null, null, 0, 0, 701, true)
	host.configure(definition, context)
	host.begin()
	return host


func test_pixel_screen_uses_integer_physical_scale_at_all_required_sizes() -> void:
	var host := make_host()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600)]:
		viewport.size = dimensions
		await wait_process_frames(5)
		var factor: int = host.get("_pixel_integer_scale")
		var screen := host.task_container.get_global_rect()
		assert_eq(screen.size, Vector2(500, 300) * factor)
		assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(screen))
		for button: Button in [host.get("_start_button"), host.pause_button, host.abort_button, host.get_node("%SettingsButton")]:
			assert_gte(button.size.y * host._physical_scale(), 48.0)
			assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(button.get_global_rect()))
		assert_gte(host.get("_prepare_goal").get_theme_font_size("font_size") * host._physical_scale(), 24.0)
		host._show_settings()
		await wait_process_frames(3)
		var box := host.get("_settings_box") as Control
		assert_true(host.settings_panel.get_global_rect().encloses(box.get_global_rect()), "设置控件保持在面板内")
		host._hide_settings()


func test_teaching_overlay_is_opt_in_and_modal_focus_stays_in_top_panel() -> void:
	var host := make_host()
	await wait_process_frames(3)
	assert_true(bool(host.active_task.context.metadata.get(&"host_instruction_overlay", false)))
	assert_eq(host.pause_button.focus_mode, Control.FOCUS_NONE)
	assert_eq(host.get_node("%SettingsButton").focus_mode, Control.FOCUS_ALL, "准备页侧边设置仍可由键盘进入")
	assert_false((host.get("_prepare_settings") as Control).visible, "准备页不再重复两个设置入口")
	assert_same(viewport.gui_get_focus_owner(), host.get("_start_button"))
	host._show_settings()
	await wait_process_frames(3)
	assert_eq((host.get("_start_button") as Control).focus_mode, Control.FOCUS_NONE)
	assert_same(viewport.gui_get_focus_owner(), host.get("_volume_slider"))
	var last := host.get("_settings_return") as Control
	assert_eq(last.focus_next, (host.get("_volume_slider") as Control).get_path())
	host._hide_settings()
	assert_same(viewport.gui_get_focus_owner(), host.get("_start_button"))


func test_legacy_art_also_receives_current_shell_and_tutorial_controls() -> void:
	var host := make_host(1)
	await wait_process_frames(3)
	assert_true(bool(host.get("_pixel_shell")))
	assert_true(bool(host.active_task.context.metadata.get(&"host_instruction_overlay", false)))
	assert_true((host.get("_prepare_hints") as Control).visible)
	assert_false(host.get_node("%VolumeKnob").visible)


func test_preparation_side_settings_accepts_real_pointer_and_returns_to_start() -> void:
	var host := make_host()
	await wait_process_frames(5)
	var settings_button := host.get_node("%SettingsButton") as Button
	var pointer := InputEventMouseButton.new()
	pointer.position = settings_button.get_global_rect().get_center()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.pressed = true
	viewport.push_input(pointer, true)
	pointer = pointer.duplicate() as InputEventMouseButton
	pointer.pressed = false
	viewport.push_input(pointer, true)
	assert_true(host.settings_panel.visible, "侧边设置通过真实指针点击打开")
	assert_false(host.prepare_panel.visible)
	assert_false(bool(host.get("_challenge_started")))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	assert_true(host.prepare_panel.visible)
	assert_same(viewport.gui_get_focus_owner(), host.get("_start_button"))


func test_exit_from_new_preparation_settles_before_return_without_result_page() -> void:
	var host := make_host()
	var order: Array[String] = []
	host.task_finished.connect(func(_result: HeritageTaskResult) -> void: order.append("settle"))
	host.return_requested.connect(func() -> void: order.append("return"))
	host._show_exit_confirm()
	host._confirm_abort()
	host._confirm_abort()
	assert_eq(order, ["settle", "return"])
	assert_false(host.result_panel.visible)


func test_escape_and_start_pause_without_aborting_and_nested_settings_restore() -> void:
	var host := make_host()
	watch_signals(host)
	host.start_from_preparation(true)
	await wait_process_frames(3)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	assert_true(host.pause_panel.visible)
	assert_false(host.exit_confirm.visible)
	assert_signal_not_emitted(host, "task_finished")
	host._show_settings()
	assert_false(host.pause_panel.visible, "设置上层只显示一张卡片")
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.SUSPENDED)
	host._hide_settings()
	assert_true(host.pause_panel.visible)
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.SUSPENDED)
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	viewport.push_input(start, true)
	assert_false(host.pause_panel.visible)
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_signal_not_emitted(host, "task_finished")
