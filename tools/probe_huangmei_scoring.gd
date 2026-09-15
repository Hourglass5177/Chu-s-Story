extends SceneTree

## Diagnostic only: synthetic silence through the real recording effect and scorer.
## Never opens a microphone, writes audio, or changes discovery/session state.
var scorer := OnnxCrepeVocalScorer.new()
var previous_frame_usec: int = 0
var worst_frame_usec: int = 0
var heartbeat_count: int = 0
var finished: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if previous_frame_usec > 0:
		worst_frame_usec = maxi(worst_frame_usec, now - previous_frame_usec)
	previous_frame_usec = now
	heartbeat_count += 1
	return false

func _run() -> void:
	AudioServer.add_bus()
	var bus := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus, "HuangmeiProbe")
	AudioServer.set_bus_mute(bus, true)
	var effect := AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, effect)
	var bytes := PackedByteArray()
	bytes.resize(48000 * 14 * 4)
	bytes.fill(0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	wav.stereo = true
	wav.data = bytes
	var player := AudioStreamPlayer.new()
	player.stream = load("res://arts/非遗媒体资源/数字版/黄梅戏-女驸马-参考唱段-v1.ogg") if OS.get_cmdline_user_args().has("--reference") else wav
	player.bus = "HuangmeiProbe"
	root.add_child(player)
	effect.set_recording_active(true)
	player.play()
	print("HUANGMEI_PROBE recording 13.65s, reference=", OS.get_cmdline_user_args().has("--reference"), "; no microphone")
	if OS.get_cmdline_user_args().has("--reference"):
		var playback_deadline := Time.get_ticks_msec() + 20000
		while player.playing and Time.get_ticks_msec() < playback_deadline:
			await process_frame
	else:
		await create_timer(13.65).timeout
	scorer.set("_state", OnnxCrepeVocalScorer.CaptureState.RECORDING)
	scorer.set("_record_effect", effect)
	scorer.set("_record_player", player)
	scorer.set("_record_bus_name", &"HuangmeiProbe")
	scorer.set("_generation", 1)
	scorer.scoring_completed.connect(func(payload: Dictionary) -> void:
		finished = true
		print("HUANGMEI_PROBE result=", JSON.stringify(payload)))
	var started := Time.get_ticks_msec()
	var err := scorer.finish_capture_and_score()
	print("HUANGMEI_PROBE finish_capture_ms=", Time.get_ticks_msec() - started, " error=", err)
	while not finished and Time.get_ticks_msec() - started < 90000:
		await create_timer(0.02).timeout
	print("HUANGMEI_PROBE total_ms=", Time.get_ticks_msec() - started,
		" max_frame_ms=", worst_frame_usec / 1000.0, " heartbeats=", heartbeat_count)
	scorer.cancel_capture()
	await process_frame
	quit(0 if finished and err == OK else 1)
