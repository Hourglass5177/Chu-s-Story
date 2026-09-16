extends Node

## 主体 BGM 独立于场景及游戏暂停；小游戏占用声音时保留播放位置。
const MUSIC_PATH := "res://Audio/Music/chuwuzhi-bgm.mp3"
const MUSIC_BUS: StringName = &"BoardMusic"
const DEFAULT_VOLUME_DB := -10.0

var _player: AudioStreamPlayer
var _fade: Tween
var _silence_owners: Dictionary[int, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func ensure_started() -> void:
	# 无窗口模拟与逻辑测试不解码音乐，也不打开音频设备。
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(_player):
		var stream := load(MUSIC_PATH) as AudioStreamMP3
		if stream == null:
			push_error("主体背景音乐加载失败：" + MUSIC_PATH)
			return
		stream = stream.duplicate() as AudioStreamMP3
		stream.loop = true
		stream.loop_offset = 0.0
		var bus_index := AudioServer.get_bus_index(MUSIC_BUS)
		if bus_index < 0:
			AudioServer.add_bus()
			bus_index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus_index, MUSIC_BUS)
			AudioServer.set_bus_send(bus_index, &"Master")
			AudioServer.set_bus_volume_db(bus_index, DEFAULT_VOLUME_DB)
		Settings.apply_audio()
		_player = AudioStreamPlayer.new()
		_player.name = "BackgroundMusic"
		_player.bus = MUSIC_BUS
		_player.stream = stream
		add_child(_player)
	if _player.playing or _player.stream_paused:
		return
	_player.volume_linear = 0.0
	_player.play()
	_update_silence()


func hold_for(owner: Node) -> void:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	var owner_id := owner.get_instance_id()
	if _silence_owners.has(owner_id):
		return
	_silence_owners[owner_id] = true
	# 包括正常返回、放弃、技术错误以及切场景；不依赖通关结果回调。
	owner.tree_exited.connect(_release_owner.bind(owner_id), CONNECT_ONE_SHOT)
	_update_silence()


func is_minigame_active() -> bool:
	return not _silence_owners.is_empty()


func _release_owner(owner_id: int) -> void:
	_silence_owners.erase(owner_id)
	_update_silence()


func _update_silence() -> void:
	if not is_instance_valid(_player):
		return
	if is_instance_valid(_fade):
		_fade.kill()
	if not _silence_owners.is_empty():
		# 立即让出演唱/教学音频，不留下淡出尾音混进采集或节拍。
		_player.stream_paused = true
		_player.volume_linear = 0.0
	else:
		_player.stream_paused = false
		_fade = create_tween()
		_fade.tween_property(_player, "volume_linear", 1.0, 0.65)
