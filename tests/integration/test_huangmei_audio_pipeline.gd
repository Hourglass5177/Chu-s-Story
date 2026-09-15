extends GutTest

## Use authorized reference audio as the input. Never access a user's microphone
## or save a recording. Exercise AudioEffectRecord -> PCM -> ONNX -> task result.
class ReferenceScorer extends OnnxCrepeVocalScorer:
	func _get_availability_reason() -> StringName:
		return &"" if ClassDB.class_exists(&"CrepePitchExtractor") else &"crepe_extension_unavailable"

	func _create_capture_graph(root: Window) -> Error:
		_record_bus_name = StringName("HuangmeiTest_%d" % get_instance_id())
		AudioServer.add_bus()
		var bus := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, _record_bus_name)
		AudioServer.set_bus_mute(bus, true)
		_record_effect = AudioEffectRecord.new()
		_record_effect.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(bus, _record_effect)
		_record_player = AudioStreamPlayer.new()
		_record_player.stream = load("res://arts/非遗媒体资源/数字版/黄梅戏-女驸马-参考唱段-v1.ogg")
		_record_player.bus = _record_bus_name
		root.add_child(_record_player)
		_record_effect.set_recording_active(true)
		_record_player.play()
		return OK


func test_full_reference_capture_scores_without_blocking_and_survives_pause() -> void:
	var initial_bus_count := AudioServer.get_bus_count()
	var scorer := ReferenceScorer.new()
	assert_true(scorer.is_available(), "Windows 验证必须实际加载本地评分扩展")
	if not scorer.is_available():
		return
	var task := load("res://InheritanceTasks/Tasks/huangmei_xi.tscn").instantiate() as HeritageTaskBase
	add_child_autofree(task)
	var context := HeritageTaskRunContext.new(&"huangmei_xi")
	context.services[&"vocal_scorer"] = scorer
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.call("_enter_countdown")
	task.call("_begin_recording")
	# Audio mixing and SceneTree timers do not share a clock. Waiting 13.65
	# SceneTree seconds can cut the reference short on the Dummy audio driver.
	# Finish the actual source, with a wall-clock watchdog, before scoring it.
	var playback_deadline := Time.get_ticks_msec() + 20000
	while scorer._record_player.playing and Time.get_ticks_msec() < playback_deadline:
		await get_tree().process_frame
	assert_false(scorer._record_player.playing, "参考唱段必须完整播放，不用墙钟截断声卡输入")
	task.time_left = 0.1
	watch_signals(task)
	watch_signals(scorer)
	var started := Time.get_ticks_msec()
	task.call("_finish_recording")
	var capture_ms := Time.get_ticks_msec() - started
	assert_lt(capture_ms, 500, "录音收尾不能长时间阻塞主线程")
	task.call("_process", 0.5)
	assert_almost_eq(task.time_left, 0.1, 0.001)
	task.set_suspended(true)
	var heartbeat_count := 0
	var worst_frame_ms := 0
	var previous := Time.get_ticks_msec()
	while scorer.is_worker_running() and Time.get_ticks_msec() - started < 30000:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		worst_frame_ms = maxi(worst_frame_ms, now - previous)
		previous = now
		heartbeat_count += 1
	assert_false(scorer.is_worker_running(), "完整双句录音须在30秒内返回评分")
	assert_gt(heartbeat_count, 2, "评分期间主线程必须持续响应")
	assert_lt(worst_frame_ms, 500, "后台评分不能卡住主线程")
	assert_signal_emit_count(scorer, "scoring_completed", 1)
	assert_signal_not_emitted(task, "task_completed")
	task.set_suspended(false)
	assert_signal_emit_count(task, "task_completed", 1)
	var result_args: Variant = get_signal_parameters(task, "task_completed")
	if result_args != null:
		var result: HeritageTaskResult = result_args[0]
		print("HUANGMEI_REFERENCE_RESULT: ", JSON.stringify(result.metrics))
		assert_eq(result.status, HeritageTaskResult.Status.SUCCESS, "授权双句参考唱段应能通过实际录音与评分链路")
		assert_gte(float(result.metrics.get("pitch", 0.0)), 70.0, "参考唱段不能因尾部漏检把整句旋律错位")
	assert_eq(AudioServer.get_bus_count(), initial_bus_count)
	print("HUANGMEI_AUDIO_PIPELINE: capture_ms=%d total_ms=%d max_frame_ms=%d heartbeats=%d" % [
		capture_ms, Time.get_ticks_msec() - started, worst_frame_ms, heartbeat_count])
	task.cancel_external()
	scorer.cancel_capture()
	# The scorer's keepalive owns any cancelled worker until its callback joins it.
	# A timeout must fail this test, not start a second unbounded wait.
	await get_tree().process_frame
