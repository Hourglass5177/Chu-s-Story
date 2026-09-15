extends Node

const POINTER := preload("res://tests/helpers/real_pointer_driver.gd")
class ReviewLauncher extends FrontendSessionLauncher:
	var scene: Node
	func change_to_game_scene(tree: SceneTree, path: String) -> Error:
		scene = load(path).instantiate()
		tree.root.add_child(scene)
		return OK

var pointer
var menu: MainMenu
var failures: Array[String] = []
var screenshots: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pointer = POINTER.new(get_viewport(), get_tree())
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func frames(count: int = 20) -> void:
	for index: int in count: await get_tree().process_frame
	if count >= 20: await get_tree().create_timer(0.25).timeout

func click(control: Control) -> void:
	var hovered = await pointer.click(control)
	check(hovered == control, "Click missed " + String(control.name))
	await frames(20)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ai-difficulty-gui/" + name + ".png")
	screenshots.append(name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ai-difficulty-gui"))
	DiscoveryManager.configure_storage_path("res://artifacts/ai-difficulty-gui/discovery.cfg")
	menu = preload("res://main_menu.tscn").instantiate()
	add_child(menu)
	await frames()
	menu.set_local_player_counts(1, 3)
	menu._draft.players[0].profession_type = 5
	menu._draft.players[0].starting_region = MapSection.REGION.恩施
	menu._draft.players[0].display_name = "玩家1"
	for index: int in 3:
		menu._draft.players[index + 1].profession_type = index
		menu._draft.players[index + 1].starting_region = [MapSection.REGION.十堰, MapSection.REGION.随州, MapSection.REGION.孝感][index]
	for window_size: Vector2i in [Vector2i(1280,800), Vector2i(1920,1080), Vector2i(2560,1600)]:
		get_window().size = window_size
		await frames()
		for index: int in 3:
			menu._open_player_setup(index + 1, true)
			await frames()
			var page := menu._player_setup_page
			await click(page.difficulty_buttons[index])
			check(int(menu.get_draft_snapshot().players[index + 1].ai_difficulty) == index, "Difficulty not saved")
			check(page.difficulty_buttons[index].button_pressed, "Selected state missing")
			check(page.confirm_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "Confirm button outside viewport")
			await capture("%dx%d-difficulty%d" % [window_size.x, window_size.y, index])
			await click(page.confirm_button)
			check(menu.get_current_screen() == &"roster", "Did not return to roster")
		await capture("%dx%d-roster" % [window_size.x, window_size.y])
		for index: int in 3:
			check(menu._roster_page._cards[index + 1]._control_label.text == "AI·" + AIProfile.LABELS[index], "Roster badge missing difficulty")
	menu._open_player_setup(2, true)
	await frames()
	var page := menu._player_setup_page
	page.difficulty_buttons[0].grab_focus()
	var event := InputEventAction.new()
	event.action = &"ui_right"
	event.pressed = true
	get_viewport().push_input(event)
	await frames(2)
	check(get_viewport().gui_get_focus_owner() == page.difficulty_buttons[1], "Keyboard direction focus failed")
	event = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	get_viewport().push_input(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = false
	get_viewport().push_input(event)
	await frames(2)
	check(int(menu._draft.players[2].ai_difficulty) == 1, "Keyboard select failed")
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_DPAD_RIGHT
	joy.pressed = true
	get_viewport().push_input(joy)
	await frames(2)
	joy.pressed = false
	get_viewport().push_input(joy)
	check(get_viewport().gui_get_focus_owner() == page.difficulty_buttons[2], "Gamepad direction focus failed")
	joy = InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	print("AI_GAMEPAD_ACCEPT ", joy.is_action_pressed(&"ui_accept"), " ", InputMap.action_get_events(&"ui_accept"), " focus=", get_viewport().gui_get_focus_owner())
	get_viewport().push_input(joy)
	await frames(2)
	joy = InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	joy.pressed = false
	get_viewport().push_input(joy)
	await frames(2)
	check(int(menu._draft.players[2].ai_difficulty) == 2, "Gamepad selection failed")
	await click(page.difficulty_buttons[1])
	await click(page.confirm_button)
	menu.set_local_player_counts(1, 5)
	for index: int in [4, 5]:
		menu._draft.players[index].profession_type = index - 1
		menu._draft.players[index].starting_region = MapSection.REGION.黄冈 if index == 4 else MapSection.REGION.荆州
		check(int(menu._draft.players[index].ai_difficulty) == 1, "Added bot must default to normal")
	for window_size: Vector2i in [Vector2i(1280,800), Vector2i(1920,1080), Vector2i(2560,1600)]:
		get_window().size = window_size
		menu.show_screen(&"roster", false)
		await frames()
		check(menu._roster_page._cards.size() == 6, "Six-seat roster missing cards")
		check(menu._roster_page._start_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "Six-seat start outside viewport")
		await capture("%dx%d-six-seats" % [window_size.x, window_size.y])
	menu.set_local_player_counts(1, 3)
	menu.show_screen(&"roster", false)
	await frames()
	for index: int in 3: check(int(menu._draft.players[index + 1].ai_difficulty) == index, "Resize lost difficulty")
	var launcher := ReviewLauncher.new()
	menu.set_session_launcher(launcher)
	await click(menu._roster_page._start_button)
	for index: int in 300:
		await get_tree().process_frame
		if TurnManager.GameOn: break
	check(TurnManager.GameOn, "Formal launch failed")
	menu.hide()
	TurnManager.turn_timer.stop()
	await frames()
	var controller := get_tree().get_first_node_in_group("AI_SESSION") as AISessionController
	for index: int in 3:
		check(TurnManager.players[index + 1].ai_difficulty == index, "Runtime difficulty mismatch")
		check(is_equal_approx((controller.policies[index + 1] as AIPolicy).profile.inheritance_chance, [0.6,0.8,1.0][index]), "Runtime chance mismatch")
	await click(controller._speed)
	check(controller._speed.text == "AI速度：x1.50", "Speed control changed")
	await capture("mixed-formal-game")
	GameManager.reset_session(false)
	if launcher.scene != null: launcher.scene.queue_free()
	menu.queue_free()
	await frames(2)
	var file := FileAccess.open("res://artifacts/ai-difficulty-gui/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "screenshots": screenshots}, "\t"))
	print("AI_DIFFICULTY_GUI ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
