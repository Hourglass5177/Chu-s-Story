extends Node

const MAIN := preload("res://main_map.tscn")
const POINTER := preload("res://tests/helpers/real_pointer_driver.gd")
var _pointer
var _scene: Node
var _controller: AISessionController
var _done: bool = false
var _applied: bool = false
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pointer = POINTER.new(get_viewport(), get_tree())
	_run.call_deferred()

func _require(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)

func _wait_until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return false

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ai-gui/" + name + ".png")

func _incoming(source: PlayerClass, target: PlayerClass, amount: int) -> void:
	_done = false
	_applied = await EventManager._resolve_incoming_effect(source, target, &"event", "电脑对战响应验证", EventManager._apply_energy.bind(amount))
	_done = true

func _inherit(player: PlayerClass, card: 非遗牌) -> void:
	_done = false
	_applied = await _controller._perform_inheritance(player, card)
	_done = true

func _run() -> void:
	var difficulty := 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--difficulty="): difficulty = int(argument.get_slice("=", 1))
	DiscoveryManager.configure_storage_path("res://artifacts/ai-gui/interaction-discovery.cfg")
	GameManager.configure_session(91780, GameManager.RuntimeProfile.NORMAL)
	GameManager.reset_session()
	GameManager.player_data = [
		{"name": "响应玩家", "job": "美食博主", "location": "十堰", "is_bot": false},
		{"name": "另一位玩家", "job": "商业博主", "location": "随州", "is_bot": false},
		{"name": "测试电脑", "job": "生活博主", "location": "孝感", "is_bot": true, "ai_difficulty": difficulty},
	]
	_scene = MAIN.instantiate()
	get_tree().root.add_child(_scene)
	await _wait_until(func(): return TurnManager.GameOn)
	_controller = get_tree().get_first_node_in_group("AI_SESSION")
	_controller.set_process(false)
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var human: PlayerClass = TurnManager.players[0]
	var bot: PlayerClass = TurnManager.players[2]
	var response := load("res://Cards/事件牌/金蝉脱壳.tres") as 事件牌
	human.事件牌手牌.append(response)
	var energy_before := human.current_energy
	_incoming(bot, human, -2)
	_require(await _wait_until(func(): return get_tree().get_first_node_in_group("PRIVATE_DECISION_HANDOFF") != null), "Missing private handoff")
	var handoff := get_tree().get_first_node_in_group("PRIVATE_DECISION_HANDOFF")
	if handoff != null:
		_require(get_tree().paused and not TurnManager.hud.event_overlay.visible, "Private options visible before handoff")
		await _save("human-handoff")
		await _pointer.click(handoff.find_child("AcceptHandoff", true, false))
	var overlay: EventOverlay = TurnManager.hud.event_overlay
	_require(await _wait_until(func(): return overlay._active_request != null), "Human response did not open")
	if overlay._active_request != null:
		_require(overlay._active_request.requester == human, "Wrong response owner")
		await _save("human-response")
		await _pointer.click(overlay._options_box.get_child(0))
	_require(await _wait_until(func(): return _done), "Human response stalled")
	_require(not _applied and human.current_energy == energy_before and not human.事件牌手牌.has(response), "Human defense did not cancel exactly once")
	await TurnManager.hud.wait_for_card_hand_animations()
	bot.事件牌手牌.append(response)
	_controller.set_process(true)
	energy_before = bot.current_energy
	_incoming(human, bot, -6)
	_require(await _wait_until(func(): return _done), "Computer defense stalled in a human turn")
	_require(not _applied and bot.current_energy == energy_before and not bot.事件牌手牌.has(response), "Computer defense failed")
	_controller.set_process(false)
	await TurnManager.hud.wait_for_card_hand_animations()
	# Construct a legal registered ACTION fixture; the attempt itself uses production cost and RNG.
	TurnManager.now_player_index = 2
	TurnManager.turn_start.emit(2)
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	var national: 非遗牌
	for cards: Array in ResourceManager.地区非遗牌库.values():
		for card: 非遗牌 in cards:
			if card.inheritance_task_id == &"han_ju": national = card
	_require(national != null, "Missing inheritance card")
	if national != null:
		bot.非遗牌手牌.append(national)
		var discovery_before := DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME)
		energy_before = bot.current_energy
		_inherit(bot, national)
		_require(await _wait_until(func(): return _controller._inheritance_view.visible), "Automatic inheritance view did not open")
		await _save("automatic-inheritance")
		var random_state := _controller.inheritance.rng.state
		await _pointer.click(TurnManager.hud.pause_button)
		for frame: int in 20: await get_tree().process_frame
		_require(_controller.user_paused() and not _done, "Pause did not freeze automatic inheritance")
		_require(_controller.inheritance.rng.state == random_state, "Pause resampled inheritance")
		await _pointer.click(TurnManager.hud.pause_overlay.continue_button)
		_require(await _wait_until(func(): return _done), "Inheritance did not resume")
		_require(_applied and bot.current_energy == energy_before - 1, "Incorrect formal inheritance cost")
		_require(DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME) == discovery_before, "Automatic inheritance unlocked minigame gallery")
	var report := {"passed": _failures.is_empty(), "failures": _failures, "human_response": true, "computer_response": true, "inheritance_pause": true}
	var file := FileAccess.open("res://artifacts/ai-gui/interactions.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("AI_GUI_INTERACTIONS ", JSON.stringify(report))
	GameManager.reset_session(false)
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)
