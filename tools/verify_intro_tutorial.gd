extends Node

@onready var root: Window = get_tree().root

var lesson: TutorialController
var output := "res://artifacts/tutorial-review"
var errors: Array[String] = []
var keys := false
var gamepad := false
var before_discovery: Dictionary
var before_files: Dictionary
var frame_times: Array[float] = []
var audit := false
var sampling := false
var last_frame_usec := 0
var quick := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window_size := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			window_size = Vector2i(int(parts[0]), int(parts[1]))
		quick = quick or arg == "--quick"
		audit = audit or arg == "--audit"
		keys = keys or arg == "--keys"
		gamepad = gamepad or arg == "--gamepad"
	output += "/%dx%d-%s" % [window_size.x, window_size.y, "gamepad" if gamepad else ("keys" if keys else "mouse")]
	root.size = window_size
	root.title = "楚物志 · 入门教学验证"
	DirAccess.make_dir_recursive_absolute(output)
	var gm := root.get_node("GameManager")
	before_discovery = DiscoveryManager._discovered.duplicate(true)
	for path in [DiscoveryManager._storage_path, HeritageMinigamePreferences.storage_path]:
		before_files[path] = _digest(path)
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().create_timer(1.0).timeout
	await _menu_stable(menu)
	for node in menu.find_children("*", "Button", true, false):
		if node.text == "开始游戏" and node.is_visible_in_tree():
			await _raw_click(node.get_global_rect().get_center())
			break
	await get_tree().create_timer(0.5).timeout
	await _menu_stable(menu)
	for node in menu.find_children("*", "PanelContainer", true, false):
		if node is FrontendStatefulCard and node.title == "教学模式":
			await _raw_click(node.get_global_rect().get_center())
			break
	var deadline := Time.get_ticks_msec() + 90000
	while gm.tutorial_controller == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	lesson = gm.tutorial_controller
	var scene := get_tree().current_scene
	if lesson == null:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/entry-error.png")
		push_error("No tutorial: " + str(get_tree().current_scene))
		get_tree().quit(1)
		return
	lesson.progress_path = output + "/progress.cfg"
	await _capture("01-welcome")
	await _check_pause_round_trip("welcome")
	await _activate(lesson.overlay.primary)
	await get_tree().create_timer(4.0).timeout
	await _capture("02-move")
	if not keys and not gamepad:
		var original_step := lesson.step
		await _raw_click(Vector2(10, 1100))
		await get_tree().create_timer(0.1 if quick else 21.0).timeout
		_check(lesson.step == original_step and TurnManager.turn_timer.is_stopped(), "idle never skips the action")
		if not quick:
			_check(lesson.overlay.hint.visible, "idle offers optional help")
			await _capture("02-idle-hint")
		if lesson.hud.pause_overlay.visible: await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
		await _key(KEY_ESCAPE)
		_check(lesson.hud.pause_overlay.visible, "pause opens")
		await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
		if audit:
			var generation := TurnManager.get_session_generation()
			await _key(KEY_ESCAPE)
			for button in lesson.hud.pause_overlay.continue_button.get_parent().get_children():
				if button is Button and button.text == "重新开始":
					await _raw_click(button.get_global_rect().get_center())
					break
			while gm.tutorial_controller == null or TurnManager.get_session_generation() == generation:
				await get_tree().process_frame
			await get_tree().create_timer(0.5).timeout
			lesson = gm.tutorial_controller
			lesson.progress_path = output + "/progress.cfg"
			_check(lesson.step == 0 and lesson.player.current_energy == 6 and lesson.player.非遗牌手牌.is_empty(), "restart restores fresh practice state")
			await _activate(lesson.overlay.primary)
			await get_tree().create_timer(4.0).timeout
			if not quick: await _sample_switches()
	if keys or gamepad:
		if gamepad: await _pad(JOY_BUTTON_DPAD_RIGHT)
		else: await _key(KEY_RIGHT)
		await _confirm()
	else:
		await _click(lesson.hud.get_tutorial_map_rect(TutorialDefinition.DESTINATION).get_center())
	await get_tree().create_timer(1.5).timeout
	_check(lesson._arrived, "real movement reaches destination")
	await _activate(lesson.hud.btn_end_turn)
	await get_tree().create_timer(0.3).timeout
	_check(lesson.step == 2, "move advances to collection")
	await _capture("03-collect")
	await _activate(lesson.hud.btn_action)
	await get_tree().create_timer(2.2).timeout
	_check(lesson.step == 3, "real collection advances to food")
	await _capture("04-card")
	await _activate(lesson.hud.detail_panel.get_node("BtnClose"))
	await _activate(lesson.hud.btn_food)
	await get_tree().create_timer(0.5).timeout
	await _capture("05-food")
	await _check_pause_round_trip("food")
	if lesson.hud.backpack_panel.grid_container.get_child_count() == 0:
		push_error("Tutorial stopped before food"); gm.reset_session(); get_tree().quit(1); return
	var item = lesson.hud.backpack_panel.grid_container.get_child(0)
	if item.get("action_button") != null: await _activate(item.action_button)
	await get_tree().create_timer(0.6).timeout
	_check(lesson.step == 4, "food commits")
	await _activate(lesson.hud.backpack_panel.btn_close)
	await get_tree().create_timer(0.3).timeout
	var target = lesson._target()
	if target != null: await _activate(target)
	await get_tree().create_timer(0.4).timeout
	await _activate(lesson.hud.detail_panel.task_button)
	await get_tree().create_timer(0.4).timeout
	await _capture("06-inheritance")
	await _check_pause_round_trip("inheritance example")
	_check(lesson._attempt != null, "example uses real transaction")
	await _activate(lesson.overlay.primary)
	await get_tree().create_timer(0.4).timeout
	_check(lesson.step == 5 and lesson.player.current_score >= 5, "example unlocks real score")
	await _activate(lesson.hud.detail_panel.get_node("BtnClose"))
	await _activate(lesson.hud.score_label)
	await get_tree().create_timer(0.3).timeout
	await _capture("07-score")
	await _activate(lesson.hud.score_overlay.close_button)
	_check(lesson.step == 6, "viewing then closing score advances")
	await _activate(lesson.hud.btn_end_turn)
	await get_tree().create_timer(1.5).timeout
	_check(lesson.step == 7, "normal turn end completes lesson")
	await _capture("08-complete")
	await _check_pause_round_trip("complete")
	_check(DiscoveryManager._discovered == before_discovery, "discovery memory isolated")
	for path: String in before_files: _check(_digest(path) == before_files[path], "persistent data unchanged: " + path)
	for resolution in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1600)]:
		root.size = resolution
		await get_tree().create_timer(0.3).timeout
		await _capture("resize-%dx%d" % [resolution.x,resolution.y])
		_check(lesson.overlay.get_global_rect().encloses(lesson.overlay.modal.get_global_rect()), "summary stays inside screen")
	var report := {"performance_ms": _performance(), "errors":errors,"final_step":lesson.step,"score":lesson.player.current_score,"energy":lesson.player.current_energy}
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TUTORIAL_GUI_RESULT ", JSON.stringify(report))
	if audit:
		await _activate(lesson.overlay.primary)
		var exit_deadline := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < exit_deadline and (gm.is_tutorial_session() or not get_tree().current_scene.has_method("get_current_screen")):
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		_check(not gm.is_tutorial_session() and gm.player_data.is_empty(), "local setup has no tutorial hand or resources")
		_check(get_tree().current_scene.has_method("get_current_screen") and get_tree().current_scene.get_current_screen() == &"local_count", "completion enters fresh local setup")
		_check(DiscoveryManager._discovered == before_discovery, "discovery still isolated after leaving")
		print("TUTORIAL_EXIT_CHECK ", errors)
		report["errors"] = errors
		file = FileAccess.open(output + "/result.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t")); file.close()
	gm.reset_session(false)
	if is_instance_valid(scene): scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if errors.is_empty() else 1)

func _menu_stable(menu: Control) -> void:
	for tick in 120:
		await get_tree().process_frame
		var page: FrontendScreen = menu._pages[menu.get_current_screen()]
		if page.screen_state == FrontendScreen.ScreenState.ACTIVE:
			await get_tree().process_frame
			return

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if sampling and last_frame_usec > 0:
		frame_times.append(float(now - last_frame_usec) / 1000.0)
	last_frame_usec = now

func _sample_switches() -> void:
	await get_tree().create_timer(1.0).timeout
	var count := lesson.overlay.find_children("*", "", true, false).size()
	# Warm both devices before measuring; no screenshots or file writes in this loop.
	await _key(KEY_SHIFT)
	await _raw_click(Vector2(4, 800))
	sampling = true
	for cycle in 60:
		await _key(KEY_SHIFT)
		await _raw_click(Vector2(4, 800))
	sampling = false
	_check(lesson.overlay.find_children("*", "", true, false).size() == count, "device switches keep the hint tree")

func _performance() -> Dictionary:
	if frame_times.is_empty(): return {}
	var times := frame_times.duplicate()
	times.sort()
	return {"frames": times.size(), "device_switches":120, "p95":times[floori((times.size()-1)*0.95)], "p99":times[floori((times.size()-1)*0.99)], "max":times.back()}

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

func _activate(control: Control) -> void:
	if keys or gamepad:
		await _confirm()
	else:
		await _click(control.get_global_rect().get_center())

func _confirm() -> void:
	if lesson.hud.pause_overlay.visible: await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
	# A harmless direction announces the device; the controller assigns semantic focus.
	if gamepad:
		await _pad(JOY_BUTTON_LEFT_STICK)
	else:
		await _key(KEY_SHIFT)
	await get_tree().process_frame
	if not gamepad:
		await _key(KEY_ENTER)
	else:
		for down in [true, false]:
			var event := InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_A
			event.pressed = down
			root.push_input(event, true)
			await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)
		await get_tree().process_frame

func _key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await get_tree().process_frame

func _click(point: Vector2) -> void:
	if lesson.hud.pause_overlay.visible:
		await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
	await _raw_click(point)

func _raw_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout

func _capture(name: String) -> void:
	print("LAYOUT ", name, " root=", lesson.overlay.size, " modal=",lesson.overlay.modal.size, " img=",lesson.overlay.illustration.size, " min=",lesson.overlay.modal.get_combined_minimum_size(), " button=",lesson.overlay.primary.get_global_rect())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name + ".png")

func _check(value: bool, message: String) -> void:
	if not value: errors.append(message); print("TUTORIAL_CHECK_FAILED ",message)

func _check_pause_round_trip(context: String) -> void:
	if lesson.hud.pause_overlay.visible:
		await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
	var previous_step := lesson.step
	var previous_attempt := lesson._attempt
	var previous_paused := get_tree().paused
	await _key(KEY_ESCAPE)
	_check(lesson.hud.pause_overlay.visible, context + " can pause")
	await _raw_click(lesson.hud.pause_overlay.continue_button.get_global_rect().get_center())
	_check(lesson.step == previous_step and lesson._attempt == previous_attempt, context + " resumes same step and transaction")
	_check(get_tree().paused == previous_paused, context + " preserves nested pause ownership")
