class_name HuangmeiVocalSimilarity
extends RefCounted

## Pure, deterministic comparison for the two Huangmei-opera lines.
##
## This comparator intentionally uses only voiced duration, relative pitch contour,
## and timing. It never receives spectral/timbre features, so voice type, gender,
## accent, and absolute key cannot affect the result.

const VOICED_CONFIDENCE: float = 0.35
const MIN_PITCH_HZ: float = 55.0
const MAX_PITCH_HZ: float = 1400.0
const MIN_VOICED_FRAMES: int = 18
const MIN_LINE_GAP_SECONDS: float = 0.12
const CONTOUR_POINTS: int = 48
const RHYTHM_POINTS: int = 24


static func score(extracted: Dictionary, reference: Dictionary) -> Dictionary:
	var user_track: Dictionary = _normalize_track(extracted)
	var reference_lines: Array[Dictionary] = _normalize_reference_lines(reference)
	if user_track.is_empty():
		return _technical_payload(&"recording_analysis_invalid", "录音音高数据不完整")
	if reference_lines.size() != 2:
		return _technical_payload(&"reference_analysis_invalid", "参考唱句数据不完整")

	var user_lines: Array[Dictionary] = _split_user_track(user_track, reference_lines, reference)
	if user_lines.size() != 2:
		return _gameplay_payload(
			0.0,
			[0.0, 0.0],
			0.0,
			0.0,
			0.0,
			&"insufficient_voiced_audio",
			"两句都要完整唱出"
		)

	var expected_gap: float = _reference_gap(reference, reference_lines)
	var actual_gap: float = maxf(
		0.0,
		float(user_lines[1].get("first_time", 0.0)) - float(user_lines[0].get("last_time", 0.0))
	)
	var gap_score: float = _ratio_similarity(actual_gap + 0.05, expected_gap + 0.05, 1.35)
	var completeness_lines: Array[float] = []
	var pitch_lines: Array[float] = []
	var rhythm_lines: Array[float] = []
	var line_scores: Array[float] = []
	var enough_voice: bool = true
	var global_transposition: float = _global_pitch_transposition(user_lines, reference_lines)

	for line_index: int in 2:
		var user_line: Dictionary = user_lines[line_index]
		var reference_line: Dictionary = reference_lines[line_index]
		var reference_voiced_count: int = int(reference_line.get("voiced_count", 0))
		var user_voiced_count: int = int(user_line.get("voiced_count", 0))
		var minimum_for_line: int = maxi(
			MIN_VOICED_FRAMES,
			ceili(float(reference_voiced_count) * 0.35)
		)
		if user_voiced_count < minimum_for_line:
			enough_voice = false

		var completeness: float = clampf(
			float(user_voiced_count) / maxf(float(reference_voiced_count), 1.0) * 100.0,
			0.0,
			100.0
		)
		var pitch: float = _pitch_contour_score(
			user_line,
			reference_line,
			global_transposition
		)
		var line_rhythm: float = _line_rhythm_score(user_line, reference_line)
		var rhythm: float = line_rhythm * 0.75 + gap_score * 0.25
		var line_score: float = completeness * 0.10 + pitch * 0.55 + rhythm * 0.35
		completeness_lines.append(completeness)
		pitch_lines.append(pitch)
		rhythm_lines.append(rhythm)
		line_scores.append(line_score)

	var completeness_score: float = _average(completeness_lines)
	var pitch_score: float = _average(pitch_lines)
	var rhythm_score: float = _average(rhythm_lines)
	var raw_score: float = completeness_score * 0.10 + pitch_score * 0.55 + rhythm_score * 0.35
	var every_line_passed: bool = line_scores[0] >= 45.0 and line_scores[1] >= 45.0
	var passed: bool = enough_voice and every_line_passed and raw_score >= 60.0
	# The task controller currently decides success from score >= 60. Preserve the
	# per-line and voiced-audio gates by capping a gated failure below that mark.
	var reported_score: float = raw_score if passed else minf(raw_score, 59.0)
	var reason: StringName = &"completed"
	var feedback: String = "两句的旋律和停顿都接上了"
	if not enough_voice:
		reason = &"insufficient_voiced_audio"
		feedback = "两句都要完整唱出"
	elif not every_line_passed:
		reason = &"line_threshold_not_met"
		feedback = _feedback_for_weakest(completeness_score, pitch_score, rhythm_score)
	elif not passed:
		reason = &"vocal_similarity_low"
		feedback = _feedback_for_weakest(completeness_score, pitch_score, rhythm_score)

	return _gameplay_payload(
		reported_score,
		line_scores,
		completeness_score,
		pitch_score,
		rhythm_score,
		reason,
		feedback,
		{
			"line_completeness": completeness_lines,
			"line_pitch": pitch_lines,
			"line_rhythm": rhythm_lines,
			"inter_line_gap": actual_gap,
			"expected_inter_line_gap": expected_gap,
			"raw_score": raw_score,
			"passed": passed,
		}
	)


static func _normalize_track(source: Dictionary) -> Dictionary:
	var times: PackedFloat32Array = _to_float_array(
		source.get("times", source.get("pitch_times", PackedFloat32Array()))
	)
	var pitches: PackedFloat32Array = _to_float_array(
		source.get("pitches", source.get("pitch_hz", PackedFloat32Array()))
	)
	var confidences: PackedFloat32Array = _to_float_array(
		source.get("confidences", source.get("confidence", PackedFloat32Array()))
	)
	var count: int = mini(times.size(), pitches.size())
	if count <= 0:
		return {}
	if confidences.is_empty():
		confidences.resize(count)
		confidences.fill(1.0)
	else:
		count = mini(count, confidences.size())
	if count <= 0:
		return {}
	times.resize(count)
	pitches.resize(count)
	confidences.resize(count)
	return {
		"times": times,
		"pitches": pitches,
		"confidences": confidences,
	}


static func _normalize_reference_lines(reference: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_lines_variant: Variant = reference.get("lines", [])
	if typeof(raw_lines_variant) != TYPE_ARRAY:
		return result
	var raw_lines: Array = raw_lines_variant
	if raw_lines.size() != 2:
		return result
	for raw_line_variant: Variant in raw_lines:
		if typeof(raw_line_variant) != TYPE_DICTIONARY:
			return []
		var raw_line: Dictionary = raw_line_variant
		var normalized: Dictionary = _normalize_track(raw_line)
		if normalized.is_empty() and raw_line.has("frames"):
			normalized = _normalize_frame_objects(raw_line.get("frames", []))
		if normalized.is_empty():
			return []
		var line: Dictionary = _slice_line(
			normalized,
			0,
			(normalized.get("times", PackedFloat32Array()) as PackedFloat32Array).size() - 1
		)
		line["declared_duration"] = _declared_duration(raw_line, line)
		result.append(line)
	return result


static func _normalize_frame_objects(raw_frames_variant: Variant) -> Dictionary:
	if typeof(raw_frames_variant) != TYPE_ARRAY:
		return {}
	var times := PackedFloat32Array()
	var pitches := PackedFloat32Array()
	var confidences := PackedFloat32Array()
	for raw_frame_variant: Variant in raw_frames_variant as Array:
		if typeof(raw_frame_variant) != TYPE_DICTIONARY:
			continue
		var raw_frame: Dictionary = raw_frame_variant
		times.append(float(raw_frame.get("time", raw_frame.get("seconds", 0.0))))
		pitches.append(float(raw_frame.get("pitch", raw_frame.get("pitch_hz", 0.0))))
		confidences.append(float(raw_frame.get("confidence", 1.0)))
	return _normalize_track({"times": times, "pitches": pitches, "confidences": confidences})


static func _split_user_track(
		track: Dictionary,
		reference_lines: Array[Dictionary],
		reference: Dictionary
) -> Array[Dictionary]:
	var times: PackedFloat32Array = track.get("times", PackedFloat32Array())
	var pitches: PackedFloat32Array = track.get("pitches", PackedFloat32Array())
	var confidences: PackedFloat32Array = track.get("confidences", PackedFloat32Array())
	var voiced_indices: Array[int] = []
	for index: int in times.size():
		if _is_voiced(pitches[index], confidences[index]):
			voiced_indices.append(index)
	if voiced_indices.size() < 2:
		return []

	# The reference analysis defines where the two lyric lines divide. Anchor the
	# split to that timing instead of taking the largest silence: Huangmei phrases
	# contain intentional breaths inside a line, and those must not be mistaken
	# for the boundary between the two required lines.
	var first_start: float = times[voiced_indices[0]]
	var first_duration: float = float(reference_lines[0].get("declared_duration", 0.0))
	var expected_gap: float = _reference_gap(reference, reference_lines)
	var split_time: float = first_start + first_duration + expected_gap * 0.5
	var first_end: int = -1
	var second_start: int = -1
	for voiced_index: int in voiced_indices:
		if times[voiced_index] <= split_time:
			first_end = voiced_index
		elif second_start < 0:
			second_start = voiced_index
	if first_end < 0 or second_start < 0:
		# Legacy/custom analysis without a usable duration may still be split at a
		# clear breath, but this path is never used by the shipped Huangmei data.
		var best_split_position: int = -1
		var best_gap: float = -1.0
		for position: int in voiced_indices.size() - 1:
			var gap: float = times[voiced_indices[position + 1]] - times[voiced_indices[position]]
			if gap > best_gap:
				best_gap = gap
				best_split_position = position
		if best_split_position < 0 or best_gap < MIN_LINE_GAP_SECONDS:
			return []
		first_end = voiced_indices[best_split_position]
		second_start = voiced_indices[best_split_position + 1]
	return [
		_slice_line(track, voiced_indices[0], first_end),
		_slice_line(track, second_start, voiced_indices[voiced_indices.size() - 1]),
	]


static func _slice_line(track: Dictionary, first_index: int, last_index: int) -> Dictionary:
	var all_times: PackedFloat32Array = track.get("times", PackedFloat32Array())
	var all_pitches: PackedFloat32Array = track.get("pitches", PackedFloat32Array())
	var all_confidences: PackedFloat32Array = track.get("confidences", PackedFloat32Array())
	if first_index < 0 or last_index < first_index or last_index >= all_times.size():
		return {}
	var first_time: float = all_times[first_index]
	var times := PackedFloat32Array()
	var pitches := PackedFloat32Array()
	var confidences := PackedFloat32Array()
	var voiced_times := PackedFloat32Array()
	var voiced_pitches := PackedFloat32Array()
	for index: int in range(first_index, last_index + 1):
		var relative_time: float = all_times[index] - first_time
		times.append(relative_time)
		pitches.append(all_pitches[index])
		confidences.append(all_confidences[index])
		if _is_voiced(all_pitches[index], all_confidences[index]):
			voiced_times.append(relative_time)
			voiced_pitches.append(all_pitches[index])
	return {
		"times": times,
		"pitches": pitches,
		"confidences": confidences,
		"voiced_times": voiced_times,
		"voiced_pitches": voiced_pitches,
		"voiced_count": voiced_pitches.size(),
		"first_time": all_times[first_index],
		"last_time": all_times[last_index],
		"duration": maxf(all_times[last_index] - all_times[first_index], _median_step(all_times)),
	}


static func _pitch_contour_score(
		user_line: Dictionary,
		reference_line: Dictionary,
		transposition: float
) -> float:
	var user_pitches: PackedFloat32Array = user_line.get("voiced_pitches", PackedFloat32Array())
	var reference_pitches: PackedFloat32Array = reference_line.get(
		"voiced_pitches", PackedFloat32Array()
	)
	if user_pitches.size() < 2 or reference_pitches.size() < 2:
		return 0.0
	var user_contour: Array[float] = _resample_pitch_contour(user_pitches, CONTOUR_POINTS)
	var reference_contour: Array[float] = _resample_pitch_contour(reference_pitches, CONTOUR_POINTS)
	var total_error: float = 0.0
	for index: int in CONTOUR_POINTS:
		total_error += absf((user_contour[index] - transposition) - reference_contour[index])
	var mean_semitone_error: float = total_error / float(CONTOUR_POINTS)
	return clampf(100.0 - mean_semitone_error * 18.0, 0.0, 100.0)


static func _global_pitch_transposition(
		user_lines: Array[Dictionary],
		reference_lines: Array[Dictionary]
) -> float:
	var offsets: Array[float] = []
	for line_index: int in mini(user_lines.size(), reference_lines.size()):
		var user_pitches: PackedFloat32Array = user_lines[line_index].get(
			"voiced_pitches", PackedFloat32Array()
		)
		var reference_pitches: PackedFloat32Array = reference_lines[line_index].get(
			"voiced_pitches", PackedFloat32Array()
		)
		if user_pitches.size() < 2 or reference_pitches.size() < 2:
			continue
		var user_contour: Array[float] = _resample_pitch_contour(user_pitches, CONTOUR_POINTS)
		var reference_contour: Array[float] = _resample_pitch_contour(
			reference_pitches,
			CONTOUR_POINTS
		)
		for point: int in CONTOUR_POINTS:
			offsets.append(user_contour[point] - reference_contour[point])
	return _median(offsets)


static func _line_rhythm_score(user_line: Dictionary, reference_line: Dictionary) -> float:
	var user_duration: float = float(user_line.get("duration", 0.0))
	var reference_duration: float = float(
		reference_line.get("declared_duration", reference_line.get("duration", 0.0))
	)
	var duration_score: float = _ratio_similarity(user_duration, reference_duration, 1.65)
	var user_pattern: Array[float] = _voiced_pattern(user_line, RHYTHM_POINTS)
	var reference_pattern: Array[float] = _voiced_pattern(reference_line, RHYTHM_POINTS)
	if user_pattern.is_empty() or reference_pattern.is_empty():
		return duration_score * 0.6
	var difference: float = 0.0
	for index: int in mini(user_pattern.size(), reference_pattern.size()):
		difference += absf(user_pattern[index] - reference_pattern[index])
	var pattern_score: float = clampf(
		100.0 - difference / float(mini(user_pattern.size(), reference_pattern.size())) * 100.0,
		0.0,
		100.0
	)
	return duration_score * 0.60 + pattern_score * 0.40


static func _voiced_pattern(line: Dictionary, point_count: int) -> Array[float]:
	var times: PackedFloat32Array = line.get("times", PackedFloat32Array())
	var pitches: PackedFloat32Array = line.get("pitches", PackedFloat32Array())
	var confidences: PackedFloat32Array = line.get("confidences", PackedFloat32Array())
	var result: Array[float] = []
	result.resize(point_count)
	result.fill(0.0)
	if times.is_empty() or point_count <= 0:
		return []
	var duration: float = maxf(float(line.get("duration", 0.0)), 0.001)
	var totals: Array[int] = []
	totals.resize(point_count)
	totals.fill(0)
	for index: int in times.size():
		var bucket: int = clampi(floori(times[index] / duration * float(point_count)), 0, point_count - 1)
		totals[bucket] += 1
		if _is_voiced(pitches[index], confidences[index]):
			result[bucket] += 1.0
	for bucket: int in point_count:
		if totals[bucket] > 0:
			result[bucket] /= float(totals[bucket])
	return result


static func _resample_pitch_contour(pitches: PackedFloat32Array, point_count: int) -> Array[float]:
	var result: Array[float] = []
	if pitches.is_empty() or point_count <= 0:
		return result
	for point: int in point_count:
		var position: float = (
			float(point) / float(maxi(point_count - 1, 1)) * float(maxi(pitches.size() - 1, 0))
		)
		var left: int = clampi(floori(position), 0, pitches.size() - 1)
		var right: int = mini(left + 1, pitches.size() - 1)
		var fraction: float = position - float(left)
		var left_value: float = _pitch_to_semitones(pitches[left])
		var right_value: float = _pitch_to_semitones(pitches[right])
		result.append(lerpf(left_value, right_value, fraction))
	return result


static func _reference_gap(reference: Dictionary, lines: Array[Dictionary]) -> float:
	for key: String in ["inter_line_gap", "inter_line_gap_seconds", "line_gap"]:
		if reference.has(key):
			return maxf(float(reference[key]), 0.0)
	var raw_lines_variant: Variant = reference.get("lines", [])
	if typeof(raw_lines_variant) == TYPE_ARRAY:
		var raw_lines: Array = raw_lines_variant
		if raw_lines.size() == 2 and typeof(raw_lines[0]) == TYPE_DICTIONARY and typeof(raw_lines[1]) == TYPE_DICTIONARY:
			var first: Dictionary = raw_lines[0]
			var second: Dictionary = raw_lines[1]
			var first_end: float = float(first.get("end", first.get("end_seconds", -1.0)))
			var second_start: float = float(second.get("start", second.get("start_seconds", -1.0)))
			if first_end >= 0.0 and second_start >= first_end:
				return second_start - first_end
	if lines.size() == 2:
		return 0.35
	return 0.0


static func _declared_duration(raw_line: Dictionary, normalized: Dictionary) -> float:
	for key: String in ["duration", "duration_seconds", "voiced_duration"]:
		if raw_line.has(key) and float(raw_line[key]) > 0.0:
			return float(raw_line[key])
	var start: float = float(raw_line.get("start", raw_line.get("start_seconds", -1.0)))
	var end: float = float(raw_line.get("end", raw_line.get("end_seconds", -1.0)))
	if start >= 0.0 and end > start:
		return end - start
	return maxf(float(normalized.get("duration", 0.0)), 0.01)


static func _is_voiced(pitch: float, confidence: float) -> bool:
	return (
		confidence >= VOICED_CONFIDENCE
		and pitch >= MIN_PITCH_HZ
		and pitch <= MAX_PITCH_HZ
		and is_finite(pitch)
	)


static func _to_float_array(source: Variant) -> PackedFloat32Array:
	if source is PackedFloat32Array:
		return (source as PackedFloat32Array).duplicate()
	var result := PackedFloat32Array()
	if source is PackedFloat64Array or source is Array or source is PackedInt32Array or source is PackedInt64Array:
		for value: Variant in source:
			result.append(float(value))
	return result


static func _pitch_to_semitones(pitch_hz: float) -> float:
	return 12.0 * log(maxf(pitch_hz, 0.001)) / log(2.0)


static func _ratio_similarity(actual: float, expected: float, steepness: float) -> float:
	if actual <= 0.0 or expected <= 0.0:
		return 0.0
	return clampf(100.0 * exp(-absf(log(actual / expected)) * steepness), 0.0, 100.0)


static func _median_step(times: PackedFloat32Array) -> float:
	if times.size() < 2:
		return 0.01
	var steps: Array[float] = []
	for index: int in times.size() - 1:
		var step: float = times[index + 1] - times[index]
		if step > 0.0:
			steps.append(step)
	return _median(steps) if not steps.is_empty() else 0.01


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle: int = sorted_values.size() / 2
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) * 0.5


static func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _feedback_for_weakest(completeness: float, pitch: float, rhythm: float) -> String:
	if completeness <= pitch and completeness <= rhythm:
		return "把两句唱完整，再试一次"
	if pitch <= rhythm:
		return "旋律走向还可以更贴近示范"
	return "留意每句收束和两句之间的停顿"


static func _rounded(value: float) -> float:
	return roundf(clampf(value, 0.0, 100.0) * 10.0) / 10.0


static func _gameplay_payload(
		score_value: float,
		line_score_values: Array,
		completeness_value: float,
		pitch_value: float,
		rhythm_value: float,
		reason_value: StringName,
		feedback_value: String,
		details: Dictionary = {}
) -> Dictionary:
	var rounded_lines: Array[float] = []
	for value: Variant in line_score_values:
		var raw_line_score: float = clampf(float(value), 0.0, 100.0)
		# Do not display a gated 44.96 as 45.0: that would contradict the
		# per-line threshold even though the internal comparison is correct.
		var displayed_line_score: float = _rounded(raw_line_score)
		if raw_line_score < 45.0 and displayed_line_score >= 45.0:
			displayed_line_score = 44.9
		rounded_lines.append(displayed_line_score)
	return {
		"ok": true,
		"score": _rounded(score_value),
		"line_scores": rounded_lines,
		"completeness": _rounded(completeness_value),
		"pitch": _rounded(pitch_value),
		"rhythm": _rounded(rhythm_value),
		"feedback": feedback_value,
		"reason": reason_value,
		"details": details,
	}


static func _technical_payload(reason_value: StringName, message: String) -> Dictionary:
	return {
		"ok": false,
		"score": 0.0,
		"line_scores": [] as Array[float],
		"completeness": 0.0,
		"pitch": 0.0,
		"rhythm": 0.0,
		"feedback": message,
		"reason": reason_value,
		"message": message,
	}
