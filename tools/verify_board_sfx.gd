extends Node

var _heard: Array[StringName] = []
var _checks: Array[Dictionary] = []
var _failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("BOARD_SFX_GUI_REQUIRED: parsing successful; use a GUI run for audio checks")
		get_tree().quit()
		return
	get_window().size = Vector2i(1280, 720)
	DiscoveryManager._storage_path = "res://artifacts/board-audio/test-discovery.cfg"
	get_tree().current_scene = null
	BoardSfx.cue_played.connect(func(cue): _heard.append(cue))
	await _change("res://main_menu.tscn")
	var menu := get_tree().current_scene as MainMenu
	var pointer := preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
	var start := _find_button(menu, "开始游戏")
	_heard.clear()
	await pointer.click(start)
	await _wait(.25)
	_check("真实指针开始按钮仅一次确认音", _heard.count(&"confirm") == 1, {"cues":_heard.duplicate(), "page":menu._current_screen})
	menu._preferences.ui_sound_enabled = false
	_heard.clear()
	menu._preferences.request_feedback(&"invalid")
	await _wait(.2)
	_check("前端关闭反馈偏好有效", _heard.is_empty())
	menu._preferences.ui_sound_enabled = true
	BoardSfx._last.clear()
	_heard.clear()
	for i in range(20): BoardSfx.request(&"confirm")
	BoardSfx.request(&"invalid")
	await _wait(.15)
	_check("同帧批量点击合并且错误优先", _heard == [&"invalid"])
	var bus := AudioServer.get_bus_index(BoardSfx.BUS)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(bus, capture)
	var preview := PackedVector2Array()
	for cue: StringName in BoardSfx.CUES:
		for voice in BoardSfx._voices: voice.stop()
		BoardSfx._last.clear()
		capture.clear_buffer()
		BoardSfx.request(cue)
		await _wait(BoardSfx._streams[cue].get_length() + .10)
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for frame in frames: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		_check("音频输出 " + String(cue), peak > .001 and peak < .9, {"peak": peak})
		preview.append_array(frames)
		var gap := PackedVector2Array()
		gap.resize(int(AudioServer.get_mix_rate() * .22))
		preview.append_array(gap)
	_save_wav(preview)
	# 播放变化不能消耗全局规则 RNG。
	seed(8261)
	var expected := randi()
	seed(8261)
	BoardSfx._last.clear()
	BoardSfx.request(&"move")
	await _wait(.1)
	_check("音效变体不消耗全局随机序列", randi() == expected)
	GameManager.player_data = [{"name":"音效检查", "job":"美食博主", "location":"十堰"}]
	await _change("res://main_map.tscn")
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.turn_timer.stop()
	await _wait(.3)
	var player: PlayerClass = TurnManager.players[0]
	var food := ResourceManager.食物牌库.back() as 食物牌
	player.current_money = 0
	_heard.clear()
	var bought: bool = ResourceManager.buy_food(player, food)
	await _wait(.15)
	_check("购买失败没有交易成功音", not bought and not _heard.has(&"trade"))
	player.current_money = 1000
	_heard.clear()
	BoardSfx._last.clear()
	bought = ResourceManager.buy_food(player, food)
	await _wait(.15)
	_check("真实购买只发一次交易音并合并抽牌音", bought and _heard == [&"trade"])
	_heard.clear()
	FoodManager.food_resolution_finished.emit(player, FoodResolutionResult.new(true, false, "无事发生", food))
	await _wait(.15)
	_check("食物未生效不响恢复音", _heard.is_empty())
	FoodManager.food_resolution_finished.emit(player, FoodResolutionResult.new(true, true, "成功", food))
	await _wait(.15)
	_check("食物成功生效响恢复音", _heard == [&"recover"])
	_heard.clear()
	player.is_bot = true
	for i in range(12):
		BoardSfx.request(&"turn", player)
		BoardSfx.request(&"card", player)
		BoardSfx.request(&"trade", player)
	await _wait(.15)
	_check("电脑批量操作合并为交易音且没有回合提醒", _heard == [&"trade"])
	player.is_bot = false
	BoardSfx._last.clear()
	_heard.clear()
	TurnManager.turn_timer.start(4.5)
	BoardSfx._warning_played = false
	get_tree().paused = true
	await _wait(.2)
	_check("暂停时不发倒计时警告", not _heard.has(&"warning"))
	get_tree().paused = false
	await _wait(.3)
	TurnManager.turn_timer.stop()
	_check("真人倒计时阈值只提醒一次", _heard.count(&"warning") == 1)
	BoardSfx._last.clear()
	_heard.clear()
	var dice := BoardDicePresenter.new()
	get_tree().current_scene.add_child(dice)
	await dice.play(player, [2, 5], func(): return true)
	await _wait(.1)
	_check("正式骰子演出滚动与落定各一次", _heard.count(&"dice_roll") == 1 and _heard.count(&"dice_land") == 1)
	dice.queue_free()
	var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
	get_tree().current_scene.add_child(host)
	_heard.clear()
	BoardSfx._last.clear()
	BoardSfx.request(&"trade")
	await _wait(.15)
	_check("小游戏屏蔽主体音效", _heard.is_empty())
	host.queue_free()
	await _wait(.2)
	BoardSfx.request(&"back")
	await _wait(.15)
	_check("小游戏退出恢复主体音效", _heard == [&"back"])
	_check("播放器池始终只有四个", BoardSfx._voices.size() == 4)
	await _change("res://main_menu.tscn")
	_check("切场景清理播放与过期占用", BoardSfx._scopes.size() == 1)
	var file := FileAccess.open("res://artifacts/board-audio/sfx-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":_failed,"checks":_checks}, "\t"))
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("BOARD_SFX_RESULT ", _checks.size(), " checks; ", _failed, " failures")
	get_tree().quit(0 if _failed == 0 else 1)

func _find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := _find_button(child, caption)
		if found != null: return found
	return null

func _change(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await get_tree().scene_changed
	await _wait(.8)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _check(label: String, passed: bool, evidence: Dictionary = {}) -> void:
	_checks.append({"check":label,"passed":passed,"evidence":evidence})
	if not passed: _failed += 1
	print("BOARD_SFX_CHECK ", label, ": ", passed, " ", evidence)

func _save_wav(frames: PackedVector2Array) -> void:
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for index in range(frames.size()):
		data.encode_s16(index * 4, int(clampf(frames[index].x, -1, 1) * 32767))
		data.encode_s16(index * 4 + 2, int(clampf(frames[index].y, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = int(AudioServer.get_mix_rate())
	stream.data = data
	stream.save_to_wav("res://artifacts/board-audio/sfx-runtime-preview.wav")
