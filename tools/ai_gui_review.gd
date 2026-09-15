extends Node

const MAIN := preload("res://main_map.tscn")
const POINTER := preload("res://tests/helpers/real_pointer_driver.gd")
var _pointer
var _bot_actions: int = 0
var _reports: Array = []
var _card_cache: Array = []
var _speed_review: bool = false
var _mixed_difficulty: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pointer = POINTER.new(get_viewport(), get_tree())
	_run.call_deferred()

func _run() -> void:
	_speed_review = "--speed-review" in OS.get_cmdline_user_args()
	_mixed_difficulty = "--mixed-difficulty" in OS.get_cmdline_user_args()
	for cards: Array in ResourceManager.地区非遗牌库.values(): _card_cache.append_array(cards)
	_card_cache.append_array(ResourceManager.食物牌库)
	_card_cache.append_array(ResourceManager.事件牌库)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ai-gui"))
	DiscoveryManager.configure_storage_path("res://artifacts/ai-gui/discovery.cfg")
	if _speed_review:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ai-speed-gui"))
		await _review(1, 1)
		GameManager.reset_session(false)
		await get_tree().process_frame
		get_tree().quit(0)
		return
	for config: Vector2i in [Vector2i(1, 1), Vector2i(1, 5), Vector2i(2, 2)]:
		await _review(config.x, config.y)
	var file := FileAccess.open("res://artifacts/ai-gui/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_reports, "\t"))
	GameManager.reset_session(false)
	await get_tree().process_frame
	get_tree().quit(0 if _reports.all(func(report: Dictionary): return bool(report.completed) and bool(report.pause_frozen) and bool(report.buttons_blocked)) else 1)

func _review(humans: int, bots: int) -> void:
	GameManager.configure_session(20260915 + humans + bots, GameManager.RuntimeProfile.NORMAL)
	GameManager.reset_session()
	var players: Array = []
	for index: int in humans + bots:
		players.append({"name": ("玩家" if index < humans else "电脑") + str(index + 1), "job": SimulationSchedule.PROFESSION_NAMES[index], "location": SimulationSchedule.LOCATION_NAMES[index], "is_bot": index >= humans})
		if _mixed_difficulty:
			var first_difficulty := 0 if bots == 1 else (2 if bots == 5 else 1)
			players.back()["ai_difficulty"] = posmod(index - humans + first_difficulty, 3) if index >= humans else 1
	GameManager.player_data = players
	var scene := MAIN.instantiate()
	get_tree().root.add_child(scene)
	for frame: int in 120:
		await get_tree().process_frame
		if TurnManager.GameOn: break
	var controller := get_tree().get_first_node_in_group("AI_SESSION") as AISessionController
	if _speed_review:
		await _capture_speed_controls(controller)
		GameManager.reset_session(false)
		scene.queue_free()
		await get_tree().process_frame
		return
	_bot_actions = 0
	controller.action_completed.connect(func(_actor: int, _kind: int, success: bool):
		if success: _bot_actions += 1
	)
	await _pointer.click(controller._speed)
	if _mixed_difficulty:
		await _pointer.click(controller._speed)
		await _pointer.click(controller._speed)
	var start := Time.get_ticks_msec()
	var captures := 0
	var buttons_blocked := false
	var pause_frozen := false
	var pause_checked := false
	var human_responses := 0
	while TurnManager.GameOn and Time.get_ticks_msec() - start < 600000:
		await get_tree().process_frame
		var player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
		var handoff := get_tree().get_first_node_in_group("PRIVATE_DECISION_HANDOFF")
		if handoff != null:
			await _pointer.click(handoff.find_child("AcceptHandoff", true, false))
			continue
		var overlay: EventOverlay = TurnManager.hud.get_event_overlay()
		if overlay.visible and overlay._active_request != null and not overlay._active_request.requester.is_bot and overlay._options_box.get_child_count() > 0:
			await _pointer.click(overlay._options_box.get_child(0))
			human_responses += 1
			continue
		if not player.is_bot:
			if _bot_actions >= 2 and TurnManager.now_phase == TurnManager.TurnPhase.MOVING and not get_tree().paused and not TurnManager.is_movement_locked():
				var moves: Dictionary = player.map.query_moves(player)
				var target: MapSection
				var cost := -1
				for section: MapSection in moves:
					if section.type != MapSection.SectionType.风景 and int(moves[section].energy) > cost:
						target = section
						cost = int(moves[section].energy)
				if target != null: await player.map._on_section_clicked(target)
			if not TurnManager.hud.btn_end_turn.disabled and not get_tree().paused:
				await _pointer.click(TurnManager.hud.btn_end_turn)
		elif not controller.busy and TurnManager.modal_resolution_depth == 0 and InteractionCoordinator.get_active_snapshot().is_empty() and (TurnManager.now_phase in [TurnManager.TurnPhase.BEGIN, TurnManager.TurnPhase.END] or (TurnManager.now_phase == TurnManager.TurnPhase.ROLL_DICE and TurnManager.turn_timer.time_left < 1.8)):
			# Test clock only skips phase countdown waits; production AI submits every action.
			await TurnManager._on_timer_timeout()
		player = TurnManager.players[TurnManager.now_player_index]
		if player.is_bot and _bot_actions >= 2 and not controller.busy and captures == 0 and TurnManager.now_phase in [TurnManager.TurnPhase.MOVING, TurnManager.TurnPhase.ACTION]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/ai-gui/%dh%db.png" % [humans, bots])
			captures += 1
			buttons_blocked = TurnManager.hud.btn_end_turn.disabled and TurnManager.hud.btn_food.disabled and TurnManager.hud.btn_action.disabled
		if player.is_bot and _bot_actions >= 2 and not controller.busy and not pause_checked and TurnManager.modal_resolution_depth == 0:
			await _pointer.click(TurnManager.hud.pause_button)
			var paused_actions := _bot_actions
			for frame: int in 15: await get_tree().process_frame
			pause_frozen = controller.user_paused() and _bot_actions == paused_actions
			await _pointer.click(TurnManager.hud.pause_overlay.continue_button)
			pause_checked = true
	var times: Array[int] = controller.decision_times_usec.duplicate()
	times.sort()
	var report := {"humans": humans, "bots": bots, "completed": TurnManager.get_game_result() != null, "turns": TurnManager.now_turn, "bot_actions": _bot_actions, "captures": captures, "speed": controller.get_speed_multiplier(), "buttons_blocked": buttons_blocked, "pause_frozen": pause_frozen, "human_responses": human_responses, "decisions": times.size(), "p95_us": times[int(times.size() * 0.95)] if not times.is_empty() else 0, "max_us": times.back() if not times.is_empty() else 0, "interaction": InteractionCoordinator.get_active_snapshot()}
	_reports.append(report)
	report["difficulties"] = players.map(func(config: Dictionary): return config.get("ai_difficulty", 1))
	print("AI_GUI_MATCH ", JSON.stringify(report))
	GameManager.reset_session(false)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _capture_speed_controls(controller: AISessionController) -> void:
	TurnManager.turn_timer.stop()
	var results: Array = []
	for window_size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = window_size
		for frame: int in 10: await get_tree().process_frame
		for expected: float in [1.0, 1.5, 2.0, 3.0]:
			assert(is_equal_approx(controller.get_speed_multiplier(), expected))
			assert(controller._speed.text == "AI速度：x%.2f" % expected)
			await RenderingServer.frame_post_draw
			var filename := "%dx%d-x%.2f.png" % [window_size.x, window_size.y, expected]
			get_viewport().get_texture().get_image().save_png("res://artifacts/ai-speed-gui/" + filename)
			results.append({"window": str(window_size), "text": controller._speed.text, "rect": str(controller._speed.get_global_rect())})
			var hovered = await _pointer.click(controller._speed)
			if hovered != controller._speed:
				push_error("Speed click missed: %s; modal=%s" % [hovered, TurnManager.get_modal_snapshot()])
			assert(hovered == controller._speed)
		assert(is_equal_approx(controller.get_speed_multiplier(), 1.0))
	await _pointer.click(TurnManager.hud.pause_button)
	assert(controller.user_paused() and not controller._viewer_root.visible)
	await _pointer.click(TurnManager.hud.pause_overlay.continue_button)
	assert(not controller.user_paused() and controller._viewer_root.visible)
	var file := FileAccess.open("res://artifacts/ai-speed-gui/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"controls": results, "cycle_passed": true, "pause_passed": true}, "\t"))
	print("AI_SPEED_GUI_PASS ", JSON.stringify(results))
