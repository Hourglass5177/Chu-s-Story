extends GutTest

class SampleClockScorer extends VocalScorer:
	var status := {"ready": false, "done": false, "seconds": 0.0, "error": ""}
	var scored := false
	var paused := false
	func is_available() -> bool: return true
	func begin_capture(_id: StringName, _seconds: float) -> Error: return OK
	func get_capture_status() -> Dictionary: return status
	func finish_capture_and_score() -> Error:
		scored = true
		return OK
	func set_capture_paused(value: bool) -> void: paused = value

class FinishedNativeCapture extends RefCounted:
	var cancelled := false
	var failed := false
	func get_status() -> Dictionary: return {"done": true}
	func take_result() -> Dictionary:
		var samples := PackedFloat32Array()
		samples.resize(16000)
		return {"ok": not failed, "samples": samples, "sample_rate": 16000, "error": "device_lost" if failed else ""}
	func cancel() -> void: cancelled = true

func _task(scorer: VocalScorer) -> HeritageTaskBase:
	var task := load("res://InheritanceTasks/Tasks/huangmei_xi.tscn").instantiate() as HeritageTaskBase
	add_child_autofree(task)
	var context := HeritageTaskRunContext.new(&"huangmei_xi")
	context.services[&"vocal_scorer"] = scorer
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.call("_enter_countdown")
	task.call("_begin_recording")
	return task

func test_digital_silence_is_technical_error_not_a_failed_song() -> void:
	# Packaging regression: the old DLL has CREPE but no working capture adapter.
	assert_true(ClassDB.class_exists(&"WindowsVocalCapture"), "验证必须加载新增的 Windows 采集适配器")
	var samples := PackedFloat32Array()
	samples.resize(16000)
	var result := OnnxCrepeVocalScorer._check_recording_signal(samples)
	assert_false(result.ok)
	assert_eq(result.reason, &"recording_no_signal")

func test_dc_and_corrupted_input_are_not_sent_to_pitch_model() -> void:
	var samples := PackedFloat32Array()
	samples.resize(1000)
	samples.fill(0.25)
	assert_false(OnnxCrepeVocalScorer._check_recording_signal(samples).ok)
	samples[10] = NAN
	assert_false(OnnxCrepeVocalScorer._check_recording_signal(samples).ok)

func test_quiet_but_valid_signal_is_not_discarded() -> void:
	var samples := PackedFloat32Array()
	for i in 16000:
		samples.append(0.0001 * sin(float(i) * 0.1))
	assert_true(OnnxCrepeVocalScorer._check_recording_signal(samples).ok)

func test_opening_failure_is_technical_and_does_not_score() -> void:
	var scorer := SampleClockScorer.new()
	var task := _task(scorer)
	watch_signals(task)
	scorer.status.error = "microphone_conversion:0x88890008"
	task.call("_process", 0.1)
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.TECHNICAL_ERROR)
	assert_false(scorer.scored)

func test_audio_samples_not_render_delta_control_recording_completion() -> void:
	var scorer := SampleClockScorer.new()
	var task := _task(scorer)
	scorer.status.ready = true
	task.call("_process", 0.1)
	scorer.status.seconds = 3.0
	task.call("_process", 20.0)
	assert_eq(task.run_state, HeritageTaskBase.RunState.RUNNING)
	assert_false(scorer.scored)
	assert_eq(task.get_time_display(), "11")
	scorer.status.seconds = 13.65
	scorer.status.done = true
	task.call("_process", 0.01)
	assert_true(scorer.scored)
	assert_eq(task.get_time_display(), "评分中")

func test_disconnect_during_capture_and_pause_are_safe() -> void:
	var scorer := SampleClockScorer.new()
	var task := _task(scorer)
	scorer.status.ready = true
	task.call("_process", 0.1)
	task.set_suspended(true)
	assert_true(scorer.paused)
	task.set_suspended(false)
	assert_false(scorer.paused)
	watch_signals(task)
	scorer.status.error = "capture_device_lost"
	task.call("_process", 0.1)
	var result: HeritageTaskResult = get_signal_parameters(task, "task_completed")[0]
	assert_eq(result.status, HeritageTaskResult.Status.TECHNICAL_ERROR)
	assert_false(scorer.scored)

func test_native_silence_passes_through_adapter_as_single_technical_result() -> void:
	var scorer := OnnxCrepeVocalScorer.new()
	var native_capture := FinishedNativeCapture.new()
	scorer._native_capture = native_capture
	scorer._state = OnnxCrepeVocalScorer.CaptureState.RECORDING
	watch_signals(scorer)
	assert_eq(scorer.finish_capture_and_score(), OK)
	var deadline := Time.get_ticks_msec() + 5000
	while scorer.is_worker_running() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_false(scorer.is_worker_running())
	assert_true(native_capture.cancelled)
	assert_signal_emit_count(scorer, "scoring_completed", 1)
	var args: Variant = get_signal_parameters(scorer, "scoring_completed")
	if args != null:
		assert_false(bool(args[0].ok))
		assert_eq(args[0].reason, &"recording_no_signal")
	scorer.cancel_capture()

func test_native_error_never_starts_model_and_cannot_complete_after_cancel() -> void:
	var scorer := OnnxCrepeVocalScorer.new()
	var native_capture := FinishedNativeCapture.new()
	native_capture.failed = true
	scorer._native_capture = native_capture
	scorer._state = OnnxCrepeVocalScorer.CaptureState.RECORDING
	watch_signals(scorer)
	assert_eq(scorer.finish_capture_and_score(), OK)
	assert_false(scorer.is_worker_running())
	scorer.cancel_capture()
	await get_tree().process_frame
	assert_signal_not_emitted(scorer, "scoring_completed")
	assert_true(native_capture.cancelled)
