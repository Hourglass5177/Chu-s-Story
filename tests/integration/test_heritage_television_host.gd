extends GutTest

const HOST := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
const PREF_PATH := "user://test_heritage_television_host.cfg"
var _viewport: SubViewport


func before_each() -> void:
	HeritageMinigamePreferences.configure_storage_path(PREF_PATH)
	_remove_preferences()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.gui_disable_input = false
	add_child_autofree(_viewport)


func after_each() -> void:
	_remove_preferences()
	HeritageMinigamePreferences.configure_storage_path()


func test_preparation_blocks_gameplay_clock_and_entry_until_normal_start_click() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	watch_signals(host)
	host.begin()
	await wait_process_frames(3)
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.IDLE)
	assert_false(host.active_task.visible)
	assert_eq(host.active_task.elapsed_seconds, 0.0)
	assert_signal_not_emitted(host, "task_entered")
	assert_true(host.prepare_panel.visible)
	_click(host.get("_start_button"))
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_false(host.prepare_panel.visible)
	assert_signal_emit_count(host, "task_entered", 1)
	assert_same(_viewport.gui_get_focus_owner(), host.active_task)
	host.start_from_preparation()
	assert_signal_emit_count(host, "task_entered", 1)


func test_exit_from_preparation_settles_once_then_returns_without_discovery() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	var events: Array[String] = []
	host.task_finished.connect(func(result: HeritageTaskResult) -> void:
		assert_eq(result.status, HeritageTaskResult.Status.MANUAL_ABORT)
		events.append("settled"))
	host.return_requested.connect(func() -> void: events.append("returned"))
	watch_signals(host)
	host.begin()
	host._show_exit_confirm()
	host._confirm_abort()
	host._confirm_abort()
	assert_eq(events, ["settled", "returned"])
	assert_signal_not_emitted(host, "task_entered")
	assert_false(host.result_panel.visible)


func test_start_checks_technical_failure_without_discovery() -> void:
	var host := _make_host(&"huangmei_xi")
	watch_signals(host)
	host.begin()
	assert_signal_not_emitted(host, "task_finished")
	host.start_from_preparation()
	assert_signal_emit_count(host, "task_finished", 1)
	assert_signal_not_emitted(host, "task_entered")
	assert_true(host.result_panel.visible)
	assert_eq(host.result_title.text, "设备或素材暂不可用")
	assert_false(host.result_message.text.contains("返还"), "练习故障没有正式成本退款")


func test_relearn_is_explicit_and_presentation_is_forwarded() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	var lesson_task := host.definition.instantiate_task() as HeritageStageTask
	HeritageMinigamePreferences.complete_tutorial(&"xia_lian_dan_shu", maxi(4,lesson_task.tutorial_version()))
	lesson_task.free()
	var presentation := HeritageTaskPresentation.new()
	host.definition = host.definition.duplicate()
	host.definition.presentation = presentation
	host.begin()
	assert_true((host.get("_relearn_button") as Button).visible)
	host.start_from_preparation(true)
	assert_true(host.active_task.context.metadata[&"force_tutorial"])
	assert_false(host.active_task.context.metadata[&"skip_tutorial"])
	assert_same(host.active_task.context.metadata[&"presentation"], presentation)


func test_settings_and_exit_do_not_release_an_independent_pause_reason() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	host.begin()
	host.start_from_preparation()
	host._on_pause_pressed()
	host._show_settings()
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.SUSPENDED)
	host._hide_settings()
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.SUSPENDED)
	host._show_exit_confirm()
	host._hide_exit_confirm()
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.SUSPENDED)
	host._on_resume_pressed()
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.RUNNING)


func test_migrated_games_offer_first_lesson_and_explicit_relearn() -> void:
	for id: StringName in [&"gu_pen_ge", &"ezhou_diaohua_jianzhi", &"xisai_shenzhou_hui"]:
		var host := _make_host(id)
		host.begin()
		assert_eq((host.get("_start_button") as Button).text, "开始教学")
		assert_false((host.get("_relearn_button") as Button).visible)
		host.start_from_preparation()
		assert_true(host.active_task.is_tutorial_active())
		host.cancel(&"test_complete")
		host.queue_free()
		await wait_process_frames(1)
		HeritageMinigamePreferences.complete_tutorial(id, 5 if id in [&"gu_pen_ge",&"ezhou_diaohua_jianzhi"] else 4)
		host = _make_host(id)
		host.begin()
		assert_eq((host.get("_start_button") as Button).text, "开始")
		assert_true((host.get("_relearn_button") as Button).visible)
		host.start_from_preparation(true)
		assert_true(host.active_task.is_tutorial_active())
		host.cancel(&"test_complete")
		host.queue_free()
		await wait_process_frames(1)


func test_pixel_shell_and_controls_fit_three_sizes_and_live_resize() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	host.begin()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600)]:
		_viewport.size = dimensions
		await wait_process_frames(4)
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		assert_true(viewport_rect.encloses(host.prepare_panel.get_global_rect()), str(dimensions))
		assert_true(viewport_rect.encloses(host.task_container.get_global_rect()), str(dimensions))
		for button: Button in [host.get("_start_button"), host.abort_button, host.pause_button, host.get_node("%SettingsButton")]:
			assert_gte(button.size.y * host._physical_scale(), 44.0)
			assert_true(viewport_rect.encloses(button.get_global_rect()), str(dimensions) + str(button.name))
		assert_gte(host.get("_prepare_goal").get_theme_font_size("font_size") * host._physical_scale(), 18.0)
		assert_eq(host.get_node("SafeMargin/Panel/Television").texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	host.start_from_preparation()
	_viewport.size = Vector2i(1280, 720)
	await wait_process_frames(4)
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_true(host.task_container.get_global_rect().encloses(host.active_task.get_global_rect()))


func test_practice_retry_keeps_identity_but_formal_result_has_no_free_retry() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	host.context.avatar_id = &"life_blogger"
	host.begin()
	host.start_from_preparation()
	host.active_task.complete_success()
	assert_true(host.get_node("%RetryButton").visible)
	assert_true((host.get("_result_art") as TextureRect).visible)
	assert_same((host.get("_result_art") as TextureRect).texture,host.active_task.pixel_stage.get_texture())
	host.get_node("%RetryButton").pressed.emit()
	assert_eq(host.context.avatar_id, &"life_blogger")
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.IDLE)
	assert_true(host.prepare_panel.visible)
	host.context.practice_mode = false
	host._show_result(HeritageTaskResult.failure(&"xia_lian_dan_shu"))
	assert_false(host.get_node("%RetryButton").visible)


func test_canvas_stretch_preserves_physical_button_and_font_minimums() -> void:
	_viewport.size = Vector2i(1280, 720)
	_viewport.size_2d_override = Vector2i(2560, 1440)
	_viewport.size_2d_override_stretch = true
	var host := _make_host(&"xia_lian_dan_shu")
	host.begin()
	await wait_process_frames(4)
	assert_almost_eq(host._physical_scale(), 0.5, 0.01)
	var start := host.get("_start_button") as Button
	assert_gte(start.size.y * host._physical_scale(), 44.0)
	assert_gte(host.get("_prepare_goal").get_theme_font_size("font_size") * host._physical_scale(), 18.0)


func test_volume_changes_only_the_minigame_bus() -> void:
	var host := _make_host(&"xia_lian_dan_shu")
	var master := AudioServer.get_bus_volume_db(0)
	host.begin()
	host.start_from_preparation()
	host._on_volume_changed(35)
	assert_eq(HeritageMinigamePreferences.volume_percent(), 35)
	assert_almost_eq(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(host.AUDIO_BUS)), 0.35, 0.001)
	assert_eq(AudioServer.get_bus_volume_db(0), master)
	assert_eq((host.active_task.get("sfx") as AudioStreamPlayer).bus, host.AUDIO_BUS)


func test_calibration_closes_only_host_pause_and_preserves_external_suspension() -> void:
	var host := _make_host(&"laohekou_si_xian")
	host.begin()
	host._show_settings()
	assert_true((host.get("_calibration_button") as Button).visible)
	assert_true((host.get("_calibration_button") as Button).disabled)

	host._hide_settings()
	host.start_from_preparation(true)
	assert_true(host.active_task.context.metadata[&"host_controls"])
	host._on_pause_pressed()
	host._show_settings()
	assert_false((host.get("_calibration_button") as Button).disabled)
	host.suspend()
	host._open_task_calibration()
	assert_false(host.active_task.get("calibrating"), "外部暂停不能由校准按钮解除")
	host.resume()
	host._open_task_calibration()
	assert_true(host.active_task.get("calibrating"))
	assert_false(host.settings_panel.visible)
	assert_false(host.pause_panel.visible)
	assert_eq(host.active_task.run_state, HeritageTaskBase.RunState.RUNNING)
	var calibration: HeritageBeatCalibration
	for child: Node in host.active_task.get_children():
		if child is HeritageBeatCalibration: calibration = child
	assert_not_null(calibration)
	var origin_before := calibration.origin
	var beat_before := calibration.next_beat
	host.suspend()
	calibration.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await get_tree().create_timer(0.04).timeout
	calibration._tap()
	assert_eq(calibration.next_beat, beat_before)
	assert_true(calibration.samples.is_empty())
	host.resume()
	assert_eq(calibration.origin, origin_before, "失焦原因仍存在时不能提前恢复")
	calibration.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	assert_gt(calibration.origin, origin_before, "恢复后平移时钟原点，不补播暂停期间节拍")
	calibration.closed.emit()
	await wait_process_frames(1)
	assert_false(host.active_task.get("calibrating"))
	host.active_task.set("phase", HeritageStageTask.Phase.LIVE)
	host._show_settings()
	assert_true((host.get("_calibration_button") as Button).disabled)


func test_paused_settings_apply_visual_assistance_to_current_stage_without_resetting_score() -> void:
	var host := _make_host(&"laohekou_si_xian")
	host.begin()
	host.start_from_preparation()
	var performance := host.active_task as HeritagePerformanceTask
	performance.set_process(false)
	performance.set_physics_process(false)
	# Select the live visual state; this test validates settings, not a playthrough.
	performance.phase = HeritageStageTask.Phase.LIVE
	performance.game_time = 1.25 # A nonzero pose clock makes the ambient freeze check meaningful.
	host._show_settings()
	var score_before := performance.judge.score()
	var time_before := performance.game_time
	var toggle := host.get("_visual_assistance") as CheckButton
	toggle.button_pressed = false
	assert_false(performance.visual_assistance)
	assert_false(bool(performance.get_performance_visual_state().visual_assistance))
	assert_false(performance.visual_aid_button.button_pressed)
	assert_false(bool(performance.context.metadata[&"music_visual_assistance"]))
	assert_false(HeritageMinigamePreferences.visual_assistance_enabled())
	assert_eq(performance.run_state, HeritageTaskBase.RunState.SUSPENDED)
	toggle.button_pressed = true
	assert_true(performance.visual_assistance)
	assert_true(bool(performance.get_performance_visual_state().visual_assistance))
	assert_true(performance.visual_aid_button.button_pressed)
	var motion_toggle := host.get("_reduce_motion") as CheckButton
	assert_not_null(performance.pixel_stage)
	for reduced: bool in [true, false]:
		motion_toggle.button_pressed = reduced
		var visual_state := performance.get_visual_state()
		assert_eq(bool(visual_state.reduced_motion), reduced)
		assert_eq(HeritageMinigamePreferences.reduced_motion_enabled(), reduced)
		performance.pixel_stage.update_state(visual_state)
		assert_eq(performance.pixel_stage.canvas.decoration_time(), 0.0 if reduced else time_before)
		assert_eq(performance.pixel_stage.canvas.animation_time(), time_before, "角色准备和接触动作仍使用原时钟")
	assert_eq(performance.judge.score(), score_before)
	assert_eq(performance.game_time, time_before)
	assert_eq(performance.run_state, HeritageTaskBase.RunState.SUSPENDED)


func _make_host(id: StringName) -> HeritageTaskHost:
	var host := HOST.instantiate() as HeritageTaskHost
	_viewport.add_child(host)
	var context := HeritageTaskRunContext.new(id, null, null, 0, 0, 55, true)
	host.configure(HeritageTaskManager.get_definition(id), context)
	return host


func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	_viewport.push_input(motion, true)
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = down
		_viewport.push_input(click, true)


func _remove_preferences() -> void:
	if FileAccess.file_exists(PREF_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH))
