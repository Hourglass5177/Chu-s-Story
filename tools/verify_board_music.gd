extends Node

## 独立 GUI 验证：只截取本进程 BoardMusic 总线输出，不录系统或麦克风。
var _failures := 0
var _results: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("此工具需要真实音频输出与 GUI，请勿添加 --headless。")
		get_tree().quit(2)
		return
	# 保留验证器；后续使用正式 SceneTree 切场景路径。
	get_tree().current_scene = null
	get_window().size = Vector2i(1280, 720)
	await _change_scene("res://main_menu.tscn")
	var player := BoardMusic.get_node_or_null("BackgroundMusic") as AudioStreamPlayer
	_check("主菜单自动播放", player != null and player.playing)
	if player == null:
		get_tree().quit(1)
		return
	var original_id := player.get_instance_id()
	var bus := AudioServer.get_bus_index(BoardMusic.MUSIC_BUS)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(bus, capture)
	player.seek(20.0)
	await _wait(1.2)
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := _peak(samples)
	_check("音乐总线有实际非零 PCM 输出", peak > 0.001, {"peak": peak, "frames": samples.size(), "driver": AudioServer.get_driver_name()})
	var position := player.get_playback_position()
	get_tree().paused = true
	await _wait(0.45)
	_check("对局暂停不暂停音乐", player.get_playback_position() > position + 0.2)
	get_tree().paused = false
	BoardMusic.ensure_started()
	_check("重复请求不重建或重头播放", player.get_instance_id() == original_id and player.get_playback_position() > position)
	# 验证原 MP3 的真实曲尾，而非缩短版测试音频。
	capture.clear_buffer()
	player.seek(player.stream.get_length() - 0.8)
	await _wait(2.0)
	_check("曲尾自动循环回开头", player.playing and player.get_playback_position() < 3.0, {"position": player.get_playback_position(), "length": player.stream.get_length()})
	_save_wav(capture.get_buffer(capture.get_frames_available()), "res://artifacts/board-audio/loop-boundary.wav")
	player.seek(30.0)
	await _wait(0.2)
	var host_scene := load("res://InheritanceTasks/UI/heritage_task_host.tscn") as PackedScene
	var host := host_scene.instantiate() as HeritageTaskHost
	get_tree().current_scene.add_child(host)
	var context := HeritageTaskRunContext.new(&"han_ju", null, null, 0, 0, 1, true)
	host.configure(load("res://InheritanceTasks/Definitions/han_ju.tres"), context)
	host.begin()
	await _wait(0.2)
	position = player.get_playback_position()
	capture.clear_buffer()
	await _wait(0.4)
	peak = _peak(capture.get_buffer(capture.get_frames_available()))
	_check("小游戏准备页暂停 BGM 且总线静音", player.stream_paused and absf(player.get_playback_position() - position) < 0.1 and peak < 0.00001, {"peak": peak})
	var second_host := host_scene.instantiate() as HeritageTaskHost
	get_tree().current_scene.add_child(second_host)
	host.queue_free()
	await _wait(0.15)
	_check("嵌套占用不会过早恢复", player.stream_paused)
	second_host.queue_free()
	await _wait(0.9)
	_check("最后一个小游戏退出后从原位置续播", not player.stream_paused and player.get_playback_position() > position + 0.3 and player.get_playback_position() < position + 2.0)
	GameManager.player_data = [{"name": "音频检查", "job": "美食博主", "location": "十堰"}]
	position = player.get_playback_position()
	await _change_scene("res://main_map.tscn")
	TurnManager.get_node("TurnTimer").stop()
	_check("主菜单进入地图保持同一播放器", BoardMusic.get_node("BackgroundMusic").get_instance_id() == original_id and player.playing and player.get_playback_position() > position)
	# Host 未走结果页就销毁整个场景，也必须释放音乐占用。
	host = host_scene.instantiate() as HeritageTaskHost
	get_tree().current_scene.add_child(host)
	_check("地图传承入口让声", player.stream_paused)
	await _change_scene("res://main_menu.tscn")
	await _wait(0.3)
	_check("带 Host 切回主菜单清理占用", BoardMusic._silence_owners.is_empty() and not player.stream_paused and player.playing and player.get_instance_id() == original_id)
	var report := FileAccess.open("res://artifacts/board-audio/verification.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures": _failures, "checks": _results}, "\t"))
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("BOARD_MUSIC_RESULT ", _results.size(), " checks; ", _failures, " failures")
	get_tree().quit(0 if _failures == 0 else 1)


func _change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await get_tree().scene_changed
	await _wait(0.5)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(label: String, passed: bool, evidence: Dictionary = {}) -> void:
	_results.append({"check": label, "passed": passed, "evidence": evidence})
	if not passed: _failures += 1
	print("BOARD_MUSIC_CHECK ", label, ": ", passed, " ", evidence)


func _peak(frames: PackedVector2Array) -> float:
	var result := 0.0
	for frame in frames:
		result = maxf(result, maxf(absf(frame.x), absf(frame.y)))
	return result


func _save_wav(frames: PackedVector2Array, path: String) -> void:
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for index in range(frames.size()):
		data.encode_s16(index * 4, int(clampf(frames[index].x, -1.0, 1.0) * 32767))
		data.encode_s16(index * 4 + 2, int(clampf(frames[index].y, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = int(AudioServer.get_mix_rate())
	stream.data = data
	stream.save_to_wav(path)
