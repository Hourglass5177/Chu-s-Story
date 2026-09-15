extends GutTest

const Profile := preload("res://InheritanceTasks/Common/heritage_input_profile.gd")
const HOST := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
const PREFS := "user://test_ui_input_v4.cfg"

func before_each() -> void:
	HeritageMinigamePreferences.configure_storage_path(PREFS)
	if FileAccess.file_exists(PREFS): DirAccess.remove_absolute(PREFS)

func after_each() -> void:
	if FileAccess.file_exists(PREFS): DirAccess.remove_absolute(PREFS)
	HeritageMinigamePreferences.configure_storage_path()

func key(code: int, down: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down
	return event

func test_puzzle_has_four_semantic_directions_and_legacy_edges() -> void:
	var profile := Profile.new(&"puzzle")
	var actions: Array = []; var edges: Array = []
	profile.semantic_edge.connect(func(action: StringName,down: bool) -> void: actions.append([action,down]))
	profile.action_edge.connect(func(direction: int,down: bool) -> void: edges.append([direction,down]))
	for code: int in [KEY_A,KEY_D,KEY_W,KEY_S]:
		assert_true(profile.route_event(key(code)))
		profile.route_event(key(code,false))
	assert_eq(actions,[[&"left",true],[&"left",false],[&"right",true],[&"right",false],[&"up",true],[&"up",false],[&"down",true],[&"down",false]])
	assert_eq(edges[4],[-2,true]); assert_eq(edges[6],[2,true])

func test_binding_persists_per_task_and_prompts_follow_saved_binding() -> void:
	var profile := Profile.new(&"primary",&"first")
	assert_true(profile.rebind(&"primary","keyboard",{"type":"key","code":KEY_J}).ok)
	assert_false(profile.route_event(key(KEY_SPACE)))
	assert_true(profile.route_event(key(KEY_J)))
	assert_true(profile.held(0))
	assert_eq(profile.control_hints()[0].glyphs,["key_j"])
	var reopened := Profile.new(&"primary",&"first")
	assert_true(reopened.handles_event(key(KEY_J)))
	var unrelated := Profile.new(&"primary",&"second")
	assert_true(unrelated.handles_event(key(KEY_SPACE)))
	profile.reset_bindings()
	assert_true(profile.handles_event(key(KEY_SPACE)))

func test_conflict_cancel_or_explicit_swap_and_reserved_pause() -> void:
	var profile := Profile.new(&"dance")
	var binding := {"type":"key","code":KEY_D}
	assert_eq(profile.rebind(&"left","keyboard",binding).reason,"conflict")
	profile.route_event(key(KEY_D)); assert_true(profile.held(1)); assert_false(profile.held(-1))
	profile.clear()
	assert_true(profile.rebind(&"left","keyboard",binding,true).ok)
	profile.route_event(key(KEY_D)); assert_true(profile.held(-1))
	profile.route_event(key(KEY_A)); assert_true(profile.held(1))
	assert_false(profile.rebind(&"left","keyboard",{"type":"key","code":KEY_ESCAPE}).ok)
	assert_false(profile.rebind(&"left","gamepad",{"type":"button","code":JOY_BUTTON_START}).ok)

func test_two_source_hold_trigger_strength_and_non_active_releases_keep_device() -> void:
	var profile := Profile.new(&"cart")
	var axis := InputEventJoypadMotion.new()
	axis.device = 3; axis.axis = JOY_AXIS_TRIGGER_RIGHT; axis.axis_value = 0.75
	profile.route_event(axis)
	assert_eq(profile.device,&"gamepad"); assert_eq(profile.active_gamepad,3)
	assert_almost_eq(profile.action_value(&"push"),0.75,0.001)
	profile.route_event(key(KEY_D)); assert_almost_eq(profile.action_value(&"push"),1.0,0.001)
	profile.route_event(key(KEY_D,false)); assert_almost_eq(profile.action_value(&"push"),0.75,0.001)
	profile.note_event_device(axis)
	profile.note_event_device(key(KEY_D,false))
	assert_eq(profile.device,&"gamepad","A key release must not steal the active device.")
	axis.axis_value = 0.1; profile.route_event(axis)
	assert_false(profile.held(1))

func test_corrupt_saved_action_falls_back_without_touching_other_preferences() -> void:
	HeritageMinigamePreferences.save_volume_percent(65)
	HeritageMinigamePreferences.save_offset(37)
	HeritageMinigamePreferences.save_offset(-45,"pad:headphones")
	HeritageMinigamePreferences.save_input_bindings(&"puzzle",{"left":false,"right":{"keyboard":[{"type":"key","code":KEY_ESCAPE}]}})
	var profile := Profile.new(&"puzzle")
	assert_true(profile.handles_event(key(KEY_A)))
	assert_true(profile.handles_event(key(KEY_D)))
	assert_eq(HeritageMinigamePreferences.volume_percent(),65)
	assert_eq(HeritageMinigamePreferences.offset_ms(),37)
	assert_eq(HeritageMinigamePreferences.offset_ms("pad:headphones"),-45)
	assert_eq(HeritageMinigamePreferences.offset_ms("new-device"),37)

func test_every_profile_has_consistent_keyboard_bindings_and_hints() -> void:
	for kind: StringName in [&"heat",&"primary",&"platform",&"dance",&"bow",&"spotlight",&"puzzle",&"trace",&"cart",&"escort"]:
		var profile := Profile.new(kind)
		for action: Dictionary in profile.get_action_definitions():
			var binding: Dictionary = profile.bindings_for(action.id,"keyboard")[0]
			assert_true(profile.route_event(key(int(binding.code))))
			assert_true(profile.held(int(action.direction)),String(kind)+":"+String(action.id))
			assert_gt(profile.action_value(action.id),0.0)
			profile.route_event(key(int(binding.code),false))
			assert_false(profile.held(int(action.direction)))

func test_mouse_dual_actions_release_outside_and_wheel_is_one_pulse() -> void:
	var profile := Profile.new(&"bow")
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = true
	profile.route_event(event); assert_true(profile.held(1)); assert_false(profile.held(-1))
	event.pressed = false; event.position = Vector2(-200,-200)
	assert_true(profile.release_pointer(event)); assert_false(profile.held(1))
	var boat := Profile.new(&"escort")
	var edges: Array = []
	boat.semantic_edge.connect(func(action: StringName,down: bool) -> void: edges.append([action,down]))
	event.button_index = MOUSE_BUTTON_WHEEL_UP; event.pressed = true
	boat.route_event(event)
	assert_eq(edges,[[&"accelerate",true],[&"accelerate",false]])
	assert_false(boat.has_pressed_sources())

func make_host(id: StringName, viewport: SubViewport) -> HeritageTaskHost:
	var host := HOST.instantiate() as HeritageTaskHost
	viewport.add_child(host)
	var definition := HeritageTaskManager.get_definition(id)
	var context := HeritageTaskRunContext.new(id,null,null,0,0,772,true)
	context.test_mode = true
	host.configure(definition,context); host.begin()
	return host

func test_all_fifteen_preparations_have_current_shell_without_starting_media() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.gui_disable_input = false
	add_child_autofree(viewport)
	for id: StringName in [&"xia_lian_dan_shu",&"laohekou_si_xian",&"xiabaoping_minjian_gushi",&"tujia_saye_erhe",&"xingshan_min_ge",&"yandi_shennong_chuanshuo",&"tianmen_tang_su",&"dong_yong_chuanshuo",&"jingzhou_hua_gu_xi",&"han_ju",&"ti_qin_xi",&"gu_pen_ge",&"ezhou_diaohua_jianzhi",&"xisai_shenzhou_hui",&"huangmei_xi"]:
		var host := make_host(id,viewport)
		await wait_process_frames(2)
		assert_true(host.get("_pixel_shell"),String(id))
		assert_true(host.prepare_panel.visible)
		assert_eq(host.active_task.run_state,HeritageTaskBase.RunState.IDLE)
		assert_gte((host.get("_prepare_goal") as Label).get_theme_font_size("font_size") * host._physical_scale(),24.0)
		var expected_version: int = 6 if host.active_task is HeritagePerformanceTask else 4
		if id in [&"gu_pen_ge",&"ezhou_diaohua_jianzhi"]: expected_version = 5
		assert_eq(host._tutorial_version(),expected_version)
		host.free()

func test_bindings_modal_keeps_pause_and_restores_settings_focus() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.gui_disable_input = false
	add_child_autofree(viewport)
	var host := make_host(&"xia_lian_dan_shu",viewport)
	host.start_from_preparation(true)
	host._on_pause_pressed(); host._show_settings(); host._show_bindings()
	await wait_process_frames(4)
	assert_true((host.get("_bindings_panel") as Control).visible)
	assert_false(host.settings_panel.visible)
	assert_eq(host.active_task.run_state,HeritageTaskBase.RunState.SUSPENDED)
	assert_true((host.get("_bindings_panel") as Control).is_ancestor_of(viewport.gui_get_focus_owner()))
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		viewport.size = dimensions; await wait_process_frames(3)
		assert_true((host.get("_bindings_panel") as Control).get_global_rect().encloses((host.get("_bindings_box") as Control).get_global_rect()))
		assert_true((host.get("_bindings_panel") as Control).get_global_rect().encloses((host.get("_bindings_return") as Control).get_global_rect()),"Return stays inside the bindings page.")
	host._hide_bindings(); assert_true(host.settings_panel.visible)
	assert_eq(host.active_task.run_state,HeritageTaskBase.RunState.SUSPENDED)
	host._hide_settings(); assert_true(host.pause_panel.visible)
	host._on_resume_pressed(); assert_eq(host.active_task.run_state,HeritageTaskBase.RunState.RUNNING)

func test_skip_does_not_complete_lesson_and_held_input_blocks_countdown() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.gui_disable_input = false
	add_child_autofree(viewport)
	var host := make_host(&"xia_lian_dan_shu",viewport)
	host.start_from_preparation(true)
	var task := host.active_task as HeritageStageTask
	task.set_physics_process(false)
	assert_true(task.is_tutorial_active())
	task.skip_tutorial()
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	assert_false(HeritageMinigamePreferences.tutorial_done(task.task_id,4))
	task.task_input(key(KEY_SPACE))
	for i: int in 400: task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	task.task_input(key(KEY_SPACE,false)); task._process(1.0/120.0)
	assert_eq(task.phase,HeritageStageTask.Phase.LIVE)
	assert_false(task.pressed[0])

func test_result_uses_live_art_and_ending_clock_without_more_gameplay() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720)
	add_child_autofree(viewport)
	var host := make_host(&"tianmen_tang_su",viewport)
	host.start_from_preparation(false)
	var task := host.active_task as HeritageStageTask
	var settled: Array[HeritageTaskResult] = []
	host.task_finished.connect(func(result: HeritageTaskResult) -> void: settled.append(result))
	task.complete_success({"successes":2},"糖泡成形了")
	assert_eq(settled.size(),1,"Result art must not postpone settlement.")
	assert_true(host.result_panel.visible)
	assert_eq((host.get("_result_art") as TextureRect).texture,task.pixel_stage.get_texture())
	var before: Dictionary = task.get_presentation_state().duplicate(true)
	for i: int in 60: host._process(1.0/60.0)
	assert_gt(float(host.get("_result_visual_elapsed")),0.9)
	assert_eq(task.get_presentation_state(),before,"Ending animation must not advance sugar pressure, growth or score.")
	assert_eq(settled.size(),1)
