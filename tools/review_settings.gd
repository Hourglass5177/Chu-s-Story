extends Node
var sampling := false
var nodes_added := 0

func _count_node(_node: Node) -> void:
	if sampling: nodes_added += 1

func _ready() -> void:
	var test_path := "user://settings_visual_review_%d.cfg" % Time.get_ticks_usec()
	Settings.load_preferences(test_path,"user://settings_visual_no_legacy.cfg")
	var menu: MainMenu = load("res://main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var panel: GameSettingsPanel = menu._general_settings
	var output := "res://artifacts/settings-review"
	DirAccess.make_dir_recursive_absolute(output)
	var pointer = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(),get_tree())
	await get_tree().create_timer(0.5).timeout
	await pointer.click(menu.find_child("SettingsButton",true,false))
	if not panel.visible: return _fail("首页设置按钮未打开面板")
	panel._controls["sfx_volume"].grab_focus()
	await _key(KEY_LEFT)
	if Settings.get_value("sfx_volume") != 95: return _fail("滑块方向键未按5%调整")
	await pointer.click(panel._tabs["accessibility"])
	await pointer.click(panel._controls["reduce_motion"])
	if not bool(Settings.get_value("reduce_motion")) or not menu._preferences.reduce_motion: return _fail("辅助开关未同步到前端")
	await pointer.click(panel._tabs["display"])
	var modes: HBoxContainer = panel._controls["display_mode"]
	await pointer.click(modes.get_child(1))
	await get_tree().create_timer(0.5).timeout
	if not Settings.preview_active: return _fail("显示模式未通过真实选择进入确认")
	await _key(KEY_ESCAPE)
	if Settings.preview_active or not panel.visible: return _fail("Esc未只还原显示模式")
	await pointer.click(modes.get_child(1))
	await get_tree().create_timer(15.2).timeout
	if Settings.preview_active or int(Settings.get_value("display_mode")) != 0: return _fail("显示超时未还原")
	await pointer.click(modes.get_child(1))
	await get_tree().create_timer(0.4).timeout
	await pointer.click(panel._confirm_yes)
	if Settings.preview_active or int(Settings.get_value("display_mode")) != 1: return _fail("确认显示模式未保存")
	Settings.preview_display(0)
	Settings.confirm_display()
	await get_tree().create_timer(0.4).timeout
	panel.show_page("audio")
	await pointer.click(panel.find_child("ResetSettingsPage",true,false))
	await pointer.click(panel._confirm_yes)
	if Settings.get_value("sfx_volume") != 100 or not bool(Settings.get_value("reduce_motion")): return _fail("恢复本页默认越过分类边界")
	await _key(KEY_ESCAPE)
	if panel.visible: return _fail("Esc未关闭设置")
	print("SETTINGS_INPUT home, slider, tabs, toggle, display rollback/confirm, scoped reset, Escape PASS")
	Settings.set_value("reduce_motion",false)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		get_window().size = resolution
		await get_tree().create_timer(0.4).timeout
		panel.open_panel()
		for page: String in ["audio","display","accessibility"]:
			panel.show_page(page)
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output+"/%s-%dx%d.png" % [page,resolution.x,resolution.y])
		panel.close_panel()
	var input_reads := Settings.disk_reads
	var input_writes := Settings.disk_writes
	var count := panel.get_child_count()
	panel.open_panel()
	panel.show_page("audio")
	await get_tree().create_timer(1.0).timeout
	get_tree().node_added.connect(_count_node)
	sampling = true
	var samples: Array[float] = []
	for index in range(120):
		var start := Time.get_ticks_usec()
		var event: InputEvent
		if index % 2 == 0:
			event = InputEventMouseMotion.new()
			event.position = Vector2(500 + index,360)
			event.relative = Vector2(20,0)
		else:
			event = InputEventKey.new()
			event.keycode = KEY_TAB
			event.pressed = true
		Input.parse_input_event(event)
		await get_tree().process_frame
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	samples.sort()
	sampling = false
	print("SETTINGS_PERF p95=",samples[113]," p99=",samples[118]," max=",samples[119]," reads=",Settings.disk_reads-input_reads," writes=",Settings.disk_writes-input_writes," nodes_added=",nodes_added," children_delta=",panel.get_child_count()-count)
	panel.close_panel()
	menu.queue_free()
	await get_tree().process_frame
	var host: HeritageTaskHost = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
	add_child(host)
	var definition := HeritageTaskManager.get_definition(&"xia_lian_dan_shu")
	host.configure(definition,HeritageTaskRunContext.new(definition.task_id,null,null,0,0,701,true))
	host.begin()
	await get_tree().create_timer(0.6).timeout
	host._show_settings()
	await get_tree().create_timer(0.4).timeout
	await pointer.click(host.find_child("GeneralSettingsButton",true,false))
	if not host._general_settings.visible: return _fail("小游戏通用设置入口不可点击")
	host._general_settings.show_page("accessibility")
	await get_tree().process_frame
	var hovered: Control = await pointer.click(host._general_settings._controls["reduce_motion"])
	if hovered != host._general_settings._controls["reduce_motion"]: return _fail("小游戏设置点击未命中预期控件")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/minigame-settings.png")
	if not bool(host.active_task.context.metadata.get("reduce_motion",false)): return _fail("小游戏未同步辅助状态")
	host._general_settings._controls["reduce_motion"].grab_focus()
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_A
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	if bool(host.active_task.context.metadata.get("reduce_motion",true)): return _fail("手柄南键未操作辅助开关")
	await _key(KEY_ESCAPE)
	if host._general_settings.visible or not host.settings_panel.visible: return _fail("小游戏返回层级错误")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/minigame-return.png")
	host.queue_free()
	await get_tree().process_frame
	print("SETTINGS_INPUT minigame nested return, live preference sync PASS")
	if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
	print("SETTINGS_REVIEW_DONE")
	get_tree().quit()

func _key(code: Key, viewport: Viewport = null) -> void:
	if viewport == null: viewport = get_viewport()
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		viewport.push_input(event,true)
		await get_tree().process_frame

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
