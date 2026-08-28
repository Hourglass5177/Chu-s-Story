extends GutTest

const TEST_REFERENCE_PATH: String = "user://huangmei_vocal_similarity_test.json"


func after_all() -> void:
	if FileAccess.file_exists(TEST_REFERENCE_PATH):
		DirAccess.remove_absolute(TEST_REFERENCE_PATH)


func test_identical_relative_contours_pass_after_octave_transposition() -> void:
	var reference: Dictionary = _make_reference()
	var same_key: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(1.0, 0.35),
		reference
	)
	var octave_higher: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(2.0, 0.35),
		reference
	)
	assert_true(bool(same_key.ok))
	assert_gte(float(same_key.score), 60.0)
	assert_eq((same_key.line_scores as Array).size(), 2)
	assert_gte(float((same_key.line_scores as Array)[0]), 45.0)
	assert_gte(float((same_key.line_scores as Array)[1]), 45.0)
	var weighted_score: float = (
		float(same_key.completeness) * 0.10
		+ float(same_key.pitch) * 0.55
		+ float(same_key.rhythm) * 0.35
	)
	assert_almost_eq(float(same_key.score), weighted_score, 0.2)
	assert_almost_eq(float(octave_higher.pitch), float(same_key.pitch), 0.2)
	assert_almost_eq(float(octave_higher.score), float(same_key.score), 0.2)


func test_missing_second_line_is_a_normal_failed_attempt_not_a_technical_error() -> void:
	var payload: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(1.0, 0.35, false),
		_make_reference()
	)
	assert_true(bool(payload.ok), "没有唱全是玩法失败，不是模型故障")
	assert_lt(float(payload.score), 60.0)
	assert_eq(payload.reason, &"insufficient_voiced_audio")
	_assert_required_payload_keys(payload)


func test_each_line_threshold_can_block_an_otherwise_acceptable_average() -> void:
	var recording: Dictionary = _make_recording(1.0, 0.35)
	var times: PackedFloat32Array = recording.times
	var pitches: PackedFloat32Array = recording.pitches
	var confidences: PackedFloat32Array = recording.confidences
	var second_start: float = 1.29 + 0.35
	for index: int in times.size():
		if times[index] >= second_start and confidences[index] >= 0.35:
			var progress: float = (times[index] - second_start) / 1.19
			pitches[index] = _pitch_hz(63.0 - 7.0 * sin(progress * TAU))
	var payload: Dictionary = HuangmeiVocalSimilarity.score(recording, _make_reference())
	assert_true(bool(payload.ok))
	assert_lt(float(payload.score), 60.0)
	assert_eq(payload.reason, &"line_threshold_not_met")
	assert_lt(float((payload.line_scores as Array)[1]), 45.0)


func test_transposition_is_global_and_preserves_the_interval_between_lines() -> void:
	var recording: Dictionary = _make_recording(1.0, 0.35)
	var times: PackedFloat32Array = recording.times
	var pitches: PackedFloat32Array = recording.pitches
	var confidences: PackedFloat32Array = recording.confidences
	var second_start: float = 1.29 + 0.35
	for index: int in times.size():
		if times[index] >= second_start and confidences[index] >= 0.35:
			pitches[index] *= 2.0
	var payload: Dictionary = HuangmeiVocalSimilarity.score(recording, _make_reference())
	assert_true(bool(payload.ok))
	assert_lt(float(payload.score), 60.0, "只能整体移调，不能把第二句单独移高八度")


func test_inter_line_gap_contributes_to_rhythm_without_changing_pitch() -> void:
	var reference: Dictionary = _make_reference()
	var on_time: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(1.0, 0.35),
		reference
	)
	var late: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(1.0, 1.40),
		reference
	)
	assert_almost_eq(float(on_time.pitch), float(late.pitch), 0.2)
	assert_gt(float(on_time.rhythm), float(late.rhythm))


func test_invalid_reference_returns_a_complete_technical_payload() -> void:
	var payload: Dictionary = HuangmeiVocalSimilarity.score(
		_make_recording(1.0, 0.35),
		{"lines": []}
	)
	assert_false(bool(payload.ok))
	assert_eq(payload.reason, &"reference_analysis_invalid")
	_assert_required_payload_keys(payload)


func test_pcm16_decoder_downmixes_stereo_in_memory() -> void:
	var bytes := PackedByteArray([
		0x00, 0x80, 0xff, 0x7f,
		0x00, 0x00, 0x00, 0x00,
	])
	var decoded: Dictionary = OnnxCrepeVocalScorer._decode_recording(
		bytes,
		AudioStreamWAV.FORMAT_16_BITS,
		48000,
		true
	)
	assert_true(bool(decoded.ok))
	var samples: PackedFloat32Array = decoded.samples
	assert_eq(samples.size(), 2)
	assert_almost_eq(samples[0], -0.000015, 0.0001)
	assert_almost_eq(samples[1], 0.0, 0.0001)
	assert_eq(int(decoded.sample_rate), 48000)


func test_unsupported_recording_format_is_reported_without_writing_a_file() -> void:
	var decoded: Dictionary = OnnxCrepeVocalScorer._decode_recording(
		PackedByteArray([1, 2, 3, 4]),
		AudioStreamWAV.FORMAT_IMA_ADPCM,
		44100,
		false
	)
	assert_false(bool(decoded.ok))
	assert_eq(decoded.reason, &"recording_format_unsupported")


func test_paused_recording_segments_are_concatenated_in_memory_only() -> void:
	var first := PackedByteArray([1, 2, 3, 4])
	var second := PackedByteArray([5, 6, 7, 8])
	var merged: Dictionary = OnnxCrepeVocalScorer._merge_recording_segments([
		{
			"pcm_bytes": first,
			"format": AudioStreamWAV.FORMAT_16_BITS,
			"mix_rate": 48000,
			"stereo": false,
		},
		{
			"pcm_bytes": second,
			"format": AudioStreamWAV.FORMAT_16_BITS,
			"mix_rate": 48000,
			"stereo": false,
		},
	])
	assert_true(bool(merged.ok))
	assert_eq(merged.pcm_bytes, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
	assert_eq(int(merged.mix_rate), 48000)


func test_mismatched_pause_segment_is_a_technical_error() -> void:
	var merged: Dictionary = OnnxCrepeVocalScorer._merge_recording_segments([
		{
			"pcm_bytes": PackedByteArray([1, 2]),
			"format": AudioStreamWAV.FORMAT_16_BITS,
			"mix_rate": 48000,
			"stereo": false,
		},
		{
			"pcm_bytes": PackedByteArray([3, 4]),
			"format": AudioStreamWAV.FORMAT_16_BITS,
			"mix_rate": 44100,
			"stereo": false,
		},
	])
	assert_false(bool(merged.ok))
	assert_eq(merged.reason, &"recording_segment_mismatch")


func test_pause_request_is_idempotent_when_not_recording() -> void:
	var scorer := OnnxCrepeVocalScorer.new()
	scorer.set_capture_paused(true)
	scorer.set_capture_paused(false)
	assert_eq(int(scorer.get("_state")), OnnxCrepeVocalScorer.CaptureState.IDLE)


func test_headless_runtime_reports_microphone_unavailable_and_creates_no_bus() -> void:
	var scorer := OnnxCrepeVocalScorer.new()
	var original_bus_count: int = AudioServer.get_bus_count()
	assert_false(scorer.is_available())
	assert_eq(scorer.get_unavailable_reason(), &"microphone_unavailable_headless")
	assert_eq(scorer.begin_capture(&"huangmei_xi", 7.0), ERR_UNAVAILABLE)
	assert_eq(AudioServer.get_bus_count(), original_bus_count)
	scorer.cancel_capture()


func test_missing_reference_is_read_at_runtime_and_not_preloaded() -> void:
	var missing: Dictionary = OnnxCrepeVocalScorer._read_reference_analysis(
		"user://definitely_missing_huangmei_reference.json"
	)
	assert_false(bool(missing.ok))
	assert_eq(missing.reason, &"reference_analysis_missing")


func test_project_reference_json_matches_runtime_schema_and_self_scores() -> void:
	var loaded: Dictionary = OnnxCrepeVocalScorer._read_reference_analysis(
		OnnxCrepeVocalScorer.DEFAULT_REFERENCE_ANALYSIS_PATH
	)
	assert_true(bool(loaded.ok))
	if not bool(loaded.ok):
		return
	var reference: Dictionary = loaded.analysis
	var payload: Dictionary = HuangmeiVocalSimilarity.score(
		_recording_from_reference(reference),
		reference
	)
	assert_true(bool(payload.ok))
	assert_gte(float(payload.score), 60.0)
	assert_gte(float((payload.line_scores as Array)[0]), 45.0)
	assert_gte(float((payload.line_scores as Array)[1]), 45.0)


func test_native_inference_runs_on_worker_and_model_is_reused_process_wide() -> void:
	_write_test_reference()
	var scorer := OnnxCrepeVocalScorer.new()
	var generation: int = 41
	scorer.set("_generation", generation)
	scorer.set("_state", OnnxCrepeVocalScorer.CaptureState.SCORING)
	var captured: Array[Dictionary] = []
	scorer.scoring_completed.connect(func(payload: Dictionary) -> void: captured.append(payload))
	var worker := Thread.new()
	scorer.set("_worker_thread", worker)
	scorer.set("_worker_generation", generation)
	scorer.call("_retain_until_worker_completes")
	var work: Dictionary = {
		"generation": generation,
		"reference_path": TEST_REFERENCE_PATH,
		"model_path": OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH,
		"pcm_bytes": _make_pcm16_recording(),
		"format": AudioStreamWAV.FORMAT_16_BITS,
		"mix_rate": 16000,
		"stereo": false,
	}
	var started: Error = worker.start(
		Callable(scorer, "_score_recording_worker").bind(work),
		Thread.PRIORITY_NORMAL
	)
	assert_eq(started, OK)
	var deadline_msec: int = Time.get_ticks_msec() + 10000
	while captured.is_empty() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().create_timer(0.01).timeout
	assert_eq(captured.size(), 1, "后台 CREPE 推理必须在时限内回到主线程")
	if not captured.is_empty():
		assert_true(bool(captured[0].ok))
		_assert_required_payload_keys(captured[0])
	assert_false(scorer.is_worker_running())
	var first: Dictionary = OnnxCrepeVocalScorer._get_shared_extractor(
		OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH
	)
	var second: Dictionary = OnnxCrepeVocalScorer._get_shared_extractor(
		OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH
	)
	assert_true(bool(first.ok))
	assert_same(first.extractor, second.extractor, "同一进程必须复用同一个 CREPE 会话")


func test_native_crepe_silence_cannot_count_as_two_valid_lines() -> void:
	var extractor_result: Dictionary = OnnxCrepeVocalScorer._get_shared_extractor(
		OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH
	)
	assert_true(bool(extractor_result.ok))
	if not bool(extractor_result.ok):
		return
	var silence := PackedFloat32Array()
	silence.resize(16000 * 14)
	silence.fill(0.0)
	var extracted: Dictionary = (extractor_result.extractor as Object).call(
		&"extract_pitch",
		silence,
		16000
	)
	assert_true(bool(extracted.ok))
	var reference_result: Dictionary = OnnxCrepeVocalScorer._read_reference_analysis(
		OnnxCrepeVocalScorer.DEFAULT_REFERENCE_ANALYSIS_PATH
	)
	var payload: Dictionary = HuangmeiVocalSimilarity.score(extracted, reference_result.analysis)
	assert_true(bool(payload.ok))
	assert_lt(float(payload.score), 60.0)
	assert_eq(payload.reason, &"insufficient_voiced_audio")


func test_cancelling_background_inference_is_non_blocking_and_suppresses_late_result() -> void:
	_write_test_reference()
	var scorer := OnnxCrepeVocalScorer.new()
	var generation: int = 73
	scorer.set("_generation", generation)
	scorer.set("_state", OnnxCrepeVocalScorer.CaptureState.SCORING)
	watch_signals(scorer)
	var worker := Thread.new()
	scorer.set("_worker_thread", worker)
	scorer.set("_worker_generation", generation)
	scorer.call("_retain_until_worker_completes")
	var start_error: Error = worker.start(
		Callable(scorer, "_score_recording_worker").bind(_make_worker_work(generation)),
		Thread.PRIORITY_NORMAL
	)
	assert_eq(start_error, OK)
	var cancel_started_msec: int = Time.get_ticks_msec()
	scorer.cancel_capture()
	assert_lt(Time.get_ticks_msec() - cancel_started_msec, 100, "取消不得等待 ONNX 推理完成")
	var deadline_msec: int = Time.get_ticks_msec() + 10000
	while scorer.is_worker_running() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().create_timer(0.01).timeout
	assert_false(scorer.is_worker_running(), "取消后的 worker 最终必须 join 并释放")
	assert_signal_emit_count(scorer, "scoring_completed", 0)


func test_cancelled_worker_keeps_scorer_alive_until_non_blocking_join() -> void:
	_write_test_reference()
	var scorer := OnnxCrepeVocalScorer.new()
	var generation: int = 91
	scorer.set("_generation", generation)
	scorer.set("_state", OnnxCrepeVocalScorer.CaptureState.SCORING)
	var worker := Thread.new()
	scorer.set("_worker_thread", worker)
	scorer.set("_worker_generation", generation)
	scorer.call("_retain_until_worker_completes")
	var start_error: Error = worker.start(
		Callable(scorer, "_score_recording_worker").bind(_make_worker_work(generation)),
		Thread.PRIORITY_NORMAL
	)
	assert_eq(start_error, OK)
	var weak_scorer: WeakRef = weakref(scorer)
	scorer.cancel_capture()
	scorer = null

	var deadline_msec: int = Time.get_ticks_msec() + 10000
	while weak_scorer.get_ref() != null and Time.get_ticks_msec() < deadline_msec:
		await get_tree().create_timer(0.01).timeout
	assert_null(weak_scorer.get_ref(), "取消后应非阻塞地等 worker 收尾，然后释放评分器")


func test_old_deferred_completion_cannot_reset_a_new_capture_state() -> void:
	var scorer := OnnxCrepeVocalScorer.new()
	scorer.set("_generation", 102)
	scorer.set("_worker_generation", 102)
	scorer.set("_state", OnnxCrepeVocalScorer.CaptureState.RECORDING)
	scorer.call("_complete_worker", 101, {})
	assert_eq(
		int(scorer.get("_state")),
		OnnxCrepeVocalScorer.CaptureState.RECORDING,
		"旧 worker 的延迟回调不得破坏新的录音状态"
	)
	assert_eq(int(scorer.get("_worker_generation")), 102)


func _make_reference() -> Dictionary:
	return {
		"inter_line_gap": 0.35,
		"lines": [
			_make_line(60.0, 130, 0.01, 0.0),
			_make_line(64.0, 120, 0.01, 0.0),
		],
	}


func _write_test_reference() -> void:
	var file: FileAccess = FileAccess.open(TEST_REFERENCE_PATH, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(_make_reference()))


func _make_pcm16_recording() -> PackedByteArray:
	const sample_rate: int = 16000
	const first_duration: float = 1.30
	const gap_duration: float = 0.35
	const second_duration: float = 1.20
	var bytes := PackedByteArray()
	var phase: float = 0.0
	var total_samples: int = floori((first_duration + gap_duration + second_duration) * sample_rate)
	for sample_index: int in total_samples:
		var seconds: float = float(sample_index) / float(sample_rate)
		var amplitude: float = 0.0
		var midi_note: float = 60.0
		if seconds < first_duration:
			var progress_first: float = seconds / first_duration
			midi_note = 60.0 + 2.0 * sin(progress_first * TAU) + 0.8 * sin(progress_first * TAU * 2.0)
			amplitude = 0.32
		elif seconds >= first_duration + gap_duration:
			var progress_second: float = (seconds - first_duration - gap_duration) / second_duration
			midi_note = 64.0 + 2.0 * sin(progress_second * TAU) + 0.8 * sin(progress_second * TAU * 2.0)
			amplitude = 0.32
		var frequency: float = _pitch_hz(midi_note)
		phase += TAU * frequency / float(sample_rate)
		var sample_value: int = clampi(roundi(sin(phase) * amplitude * 32767.0), -32768, 32767)
		var unsigned_value: int = sample_value if sample_value >= 0 else sample_value + 65536
		bytes.append(unsigned_value & 0xff)
		bytes.append((unsigned_value >> 8) & 0xff)
	return bytes


func _make_worker_work(generation: int) -> Dictionary:
	return {
		"generation": generation,
		"reference_path": TEST_REFERENCE_PATH,
		"model_path": OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH,
		"pcm_bytes": _make_pcm16_recording(),
		"format": AudioStreamWAV.FORMAT_16_BITS,
		"mix_rate": 16000,
		"stereo": false,
	}


func _recording_from_reference(reference: Dictionary) -> Dictionary:
	var times := PackedFloat32Array()
	var pitches := PackedFloat32Array()
	var confidences := PackedFloat32Array()
	var offset: float = 0.0
	var raw_lines: Array = reference.get("lines", [])
	for line_index: int in raw_lines.size():
		var line: Dictionary = raw_lines[line_index]
		var line_times: Array = line.get("times", [])
		var line_pitches: Array = line.get("pitches", [])
		var line_confidences: Array = line.get("confidences", [])
		var count: int = mini(line_times.size(), mini(line_pitches.size(), line_confidences.size()))
		for index: int in count:
			times.append(offset + float(line_times[index]))
			pitches.append(float(line_pitches[index]))
			confidences.append(float(line_confidences[index]))
		offset += float(line.get("duration", 0.0))
		if line_index == 0:
			offset += float(reference.get("inter_line_gap", 0.0))
	return {"times": times, "pitches": pitches, "confidences": confidences}


func _make_recording(
		pitch_multiplier: float,
		line_gap: float,
		include_second_line: bool = true
) -> Dictionary:
	var times := PackedFloat32Array()
	var pitches := PackedFloat32Array()
	var confidences := PackedFloat32Array()
	_append_line(times, pitches, confidences, 0.0, 60.0, 130, pitch_multiplier)
	var first_last_time: float = 1.29
	var next_time: float = first_last_time + 0.01
	var second_start: float = first_last_time + line_gap
	while next_time < second_start:
		times.append(next_time)
		pitches.append(0.0)
		confidences.append(0.0)
		next_time += 0.01
	if include_second_line:
		_append_line(times, pitches, confidences, second_start, 64.0, 120, pitch_multiplier)
	return {"times": times, "pitches": pitches, "confidences": confidences}


func _make_line(base_note: float, count: int, step: float, start: float) -> Dictionary:
	var times := PackedFloat32Array()
	var pitches := PackedFloat32Array()
	var confidences := PackedFloat32Array()
	_append_line(times, pitches, confidences, start, base_note, count, 1.0, step)
	return {
		"times": times,
		"pitches": pitches,
		"confidences": confidences,
		"duration": float(count - 1) * step,
	}


func _append_line(
		times: PackedFloat32Array,
		pitches: PackedFloat32Array,
		confidences: PackedFloat32Array,
		start: float,
		base_note: float,
		count: int,
		pitch_multiplier: float,
		step: float = 0.01
) -> void:
	for index: int in count:
		var progress: float = float(index) / float(maxi(count - 1, 1))
		var relative_note: float = 2.0 * sin(progress * TAU) + 0.8 * sin(progress * TAU * 2.0)
		times.append(start + float(index) * step)
		pitches.append(_pitch_hz(base_note + relative_note) * pitch_multiplier)
		confidences.append(0.92)


func _pitch_hz(midi_note: float) -> float:
	return 440.0 * pow(2.0, (midi_note - 69.0) / 12.0)


func _assert_required_payload_keys(payload: Dictionary) -> void:
	for key: String in [
		"ok",
		"score",
		"line_scores",
		"completeness",
		"pitch",
		"rhythm",
		"feedback",
		"reason",
	]:
		assert_true(payload.has(key), "评分 payload 缺少 %s" % key)
