extends GutTest

## Synthetic contours: these test the comparator, not microphone/model accuracy.
const STEP := 0.01
const NOTES := [0.0, 7.0, 4.0, 9.0, 2.0, 5.0, -2.0, 3.0]


func test_small_intonation_wobble_has_a_half_semitone_deadband() -> void:
	var track := _recording(-12.0)
	for i in track.pitches.size():
		track.pitches[i] *= pow(2.0, 0.45 * sin(i * 0.14) / 12.0)
	var result := _score(track)
	assert_gte(float(result.pitch), 99.0, str(result))
	assert_true(bool(result.get("passed", false)))


func test_contour_guard_is_soft_and_diagnostics_explain_the_score() -> void:
	var result := _score(_recording(-7.0, 0.35))
	assert_eq(result.details.comparison_version, 3)
	assert_true(result.details.has("line_error_pitch"))
	assert_true(result.details.has("line_contour_factor"))
	if not result.details.has("line_error_pitch"): return
	for i in 2:
		assert_almost_eq(float(result.details.line_pitch[i]),
			float(result.details.line_error_pitch[i]) * float(result.details.line_contour_factor[i]), 0.001)


func test_global_lower_key_does_not_reduce_score() -> void:
	var baseline := _score(_recording())
	for key in [-12.0, -7.0, 5.0]:
		var result := _score(_recording(key))
		assert_almost_eq(float(result.pitch), float(baseline.pitch), 0.2)
		assert_gte(float(result.score), 60.0)


func test_local_rubato_preserves_melody_in_a_lower_key() -> void:
	for amount in [-0.35, 0.35]:
		var result := _score(_recording(-12.0, amount))
		assert_gte(float(result.pitch), 85.0, "拖腔不应被当成错音：%s" % result)
		assert_gte(float(result.score), 60.0)


func test_short_octave_detection_islands_do_not_count_as_wrong_notes() -> void:
	var track := _recording(-7.0)
	var pitches: PackedFloat32Array = track.pitches
	for start in [24, 144, 264, 384, 584, 824, 1004]:
		for i in range(start, start + 9): pitches[i] *= 2.0
	var result := _score(track)
	assert_gte(float(result.pitch), 95.0, str(result))
	assert_gte(int(result.details.get("octave_corrected_frames", 0)), 50)


func test_octave_tolerance_does_not_erase_a_sustained_wrong_octave() -> void:
	var track := _recording()
	for i in range(535, 1235): track.pitches[i] *= 2.0
	assert_lt(float(_score(track).score), 60.0, str(_score(track)))


func test_late_phrase_boundary_uses_the_nearby_breath() -> void:
	var result := _score(_recording(-7.0, 0.0, 0.35))
	assert_gte(float(result.pitch), 90.0, str(result))
	assert_gte(float(result.score), 60.0)


func test_flat_humming_is_not_a_matching_melody() -> void:
	var track := _recording()
	for i in track.pitches.size():
		if track.confidences[i] > 0.35: track.pitches[i] = _hz(65.0)
	assert_lt(float(_score(track).score), 60.0)


func test_reversed_melody_cannot_be_rescued_by_alignment() -> void:
	var track := _recording()
	for bounds in [Vector2i(0, 500), Vector2i(535, 1235)]:
		var original: PackedFloat32Array = track.pitches.slice(bounds.x, bounds.y)
		original.reverse()
		for i in original.size(): track.pitches[bounds.x + i] = original[i]
	assert_lt(float(_score(track).score), 60.0, str(_score(track)))


func test_missing_line_and_silence_still_fail() -> void:
	var track := _recording()
	for i in range(535, track.pitches.size()): track.confidences[i] = 0.0
	assert_lt(float(_score(track).score), 60.0)
	track.confidences.fill(0.0)
	assert_eq(_score(track).reason, &"insufficient_voiced_audio")


func test_comparison_is_deterministic_and_does_not_mutate_inputs() -> void:
	var track := _recording(-12.0, 0.35)
	track.pitches[25] *= 2.0
	var copy := track.duplicate(true)
	var reference := _reference()
	var reference_copy := reference.duplicate(true)
	var first := HuangmeiVocalSimilarity.score(track, reference)
	assert_eq(HuangmeiVocalSimilarity.score(track, reference), first)
	assert_eq(track, copy)
	assert_eq(reference, reference_copy)


func test_correction_requires_a_short_island_and_observed_neighbors() -> void:
	for bounds in [Vector2i(24, 44), Vector2i(0, 9), Vector2i(490, 500)]:
		var track := _recording()
		for i in range(bounds.x, bounds.y): track.pitches[i] *= 2.0
		assert_eq(int(_score(track).details.octave_corrected_frames), 0,
			"持续200ms、句首或句尾都不能自动折回八度")


func test_downward_octave_islands_and_short_unvoiced_gaps_are_tolerated() -> void:
	var track := _recording()
	for i in range(24, 33): track.pitches[i] *= 0.5
	for i in range(144, 151): track.confidences[i] = 0.0
	var result := _score(track)
	assert_gte(float(result.pitch), 90.0)
	assert_eq(int(result.details.octave_corrected_frames), 9)


func test_alignment_is_bounded_and_does_not_rewrite_rhythm() -> void:
	var baseline := _score(_recording())
	var result := _score(_recording(-7.0, 0.35))
	for warp: float in result.details.max_alignment_seconds:
		assert_lte(warp, 0.40)
	assert_almost_eq(float(result.rhythm), float(baseline.rhythm), 0.1)
	assert_lte(float(_score(_recording(-7.0, 0.0, 0.35)).rhythm), float(baseline.rhythm))


func test_native_model_handles_synthetic_harmonic_voice_one_octave_lower() -> void:
	# Known waveform, not a human recording. Exercises real CREPE rather than
	# merely multiplying already-extracted pitches (which bypasses recognition).
	var model := OnnxCrepeVocalScorer._get_shared_extractor(OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH)
	assert_true(bool(model.ok))
	if not bool(model.ok): return
	var track := _recording(-12.0, 0.25)
	var samples := PackedFloat32Array()
	var phase := 0.0
	for i in track.times.size() * 160:
		var frame := mini(i / 160, track.pitches.size() - 1)
		phase += TAU * float(track.pitches[frame]) / 16000.0
		var sound := sin(phase) + 0.35 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)
		samples.append(sound * 0.08 if track.confidences[frame] > 0.35 else 0.0)
	var extracted: Dictionary = model.extractor.call("extract_pitch", samples, 16000)
	assert_true(bool(extracted.ok))
	if not bool(extracted.ok): return
	var result := _score(extracted)
	print("HUANGMEI_SYNTHETIC_LOWER_VOICE: ", JSON.stringify(result))
	assert_gte(float(result.pitch), 80.0)
	assert_gte(float(result.score), 60.0)
	assert_almost_eq(float(result.details.transposition_semitones), -12.0, 0.6)


func _score(track: Dictionary) -> Dictionary:
	return HuangmeiVocalSimilarity.score(track, _reference())


func _reference() -> Dictionary:
	return {"inter_line_gap": 0.36, "lines": [_line(0, 5.0), _line(1, 7.0)]}


func _line(index: int, duration: float) -> Dictionary:
	var line := {"times": PackedFloat32Array(), "pitches": PackedFloat32Array(),
		"confidences": PackedFloat32Array(), "duration": duration - STEP}
	for i in roundi(duration / STEP):
		line.times.append(i * STEP)
		line.pitches.append(_hz(_note(index, i * STEP / duration)))
		line.confidences.append(0.95)
	return line


func _recording(key: float = 0.0, rubato: float = 0.0, first_delay: float = 0.0) -> Dictionary:
	var track := {"times": PackedFloat32Array(), "pitches": PackedFloat32Array(),
		"confidences": PackedFloat32Array()}
	var first_duration := 5.0 + first_delay
	var second_start := first_duration + 0.35
	for i in roundi((second_start + 7.0) / STEP):
		var time := i * STEP
		var line := 0 if time < first_duration else 1
		var local := time if line == 0 else time - second_start
		var duration := first_duration if line == 0 else 7.0
		var progress := clampf(local / duration, 0.0, 1.0)
		progress = clampf(progress + rubato / duration * sin(progress * TAU), 0.0, 1.0)
		track.times.append(time)
		track.pitches.append(_hz(_note(line, progress) + key))
		track.confidences.append(0.95 if local >= 0 else 0.0)
	return track


func _note(line: int, progress: float) -> float:
	var note := float(NOTES[mini(int(progress * NOTES.size()), NOTES.size() - 1)])
	return 64.0 + (note if line == 0 else -note + 3.0)


func _hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)
