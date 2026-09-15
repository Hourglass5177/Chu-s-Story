extends RefCounted

## Bounded, order-preserving pitch alignment. No audio, model or scene ownership.
## DTW steps (1,1), (1,2), (2,1) cover every sample, including intermediate pairs.
## Reference: audiolabs-erlangen.de/resources/MIR/FMP/C3/C3S2_DTWvariants.html
const POINTS := 96
const MAX_WARP_SECONDS := 0.40
const MAX_WARP_FRACTION := 0.15
const MAX_OCTAVE_ISLAND_SECONDS := 0.12
const OCTAVE_TOLERANCE := 1.5
const MAX_INTERPOLATED_GAP := 0.22
const INTONATION_DEADBAND := 0.5
const CONTOUR_FULL_CREDIT := 0.40


static func compare(user_lines: Array[Dictionary], reference_lines: Array[Dictionary]) -> Dictionary:
	var users: Array[Dictionary] = []
	var references: Array[Dictionary] = []
	var offsets: Array[float] = []
	var corrected := 0
	var reference_corrected := 0
	for i in user_lines.size():
		var user := _prepare(user_lines[i])
		var reference := _prepare(reference_lines[i])
		users.append(user)
		references.append(reference)
		corrected += int(user.corrected)
		reference_corrected += int(reference.corrected)
		for j in POINTS:
			if user.valid[j] and reference.valid[j]:
				offsets.append(float(user.values[j]) - float(reference.values[j]))
	var shift := _median(offsets)
	# Refine ONE shared key from corresponding notes, never choose a key per line.
	var matches: Array[Dictionary] = []
	for iteration in 2:
		matches.clear()
		offsets.clear()
		for i in users.size():
			var match_result := _align(users[i], references[i], shift)
			matches.append(match_result)
			for pair: Vector2i in match_result.pairs:
				if users[i].valid[pair.x] and references[i].valid[pair.y]:
					offsets.append(float(users[i].values[pair.x]) - float(references[i].values[pair.y]))
		if iteration == 0 and not offsets.is_empty(): shift = _median(offsets)
	var scores: Array[float] = []
	var warps: Array[float] = []
	var coverages: Array[float] = []
	var correlations: Array[float] = []
	var error_scores: Array[float] = []
	var contour_factors: Array[float] = []
	for i in users.size():
		var errors: Array[float] = []
		var matched_user: Array[float] = []
		var matched_reference: Array[float] = []
		var covered := {}
		var max_warp := 0.0
		for pair: Vector2i in matches[i].pairs:
			max_warp = maxf(max_warp, absf(pair.x - pair.y) * float(references[i].duration) / (POINTS - 1))
			if users[i].valid[pair.x] and references[i].valid[pair.y]:
				errors.append(absf(float(users[i].values[pair.x]) - shift - float(references[i].values[pair.y])))
				matched_user.append(users[i].values[pair.x])
				matched_reference.append(references[i].values[pair.y])
				covered[pair.y] = true
		var reference_count := (references[i].valid as Array).count(true)
		var coverage := float(covered.size()) / maxi(reference_count, 1)
		var error_sum := 0.0
		for error in errors: error_sum += maxf(error - INTONATION_DEADBAND, 0.0)
		var pitch_score := 0.0
		var contour_factor := 1.0
		if not errors.is_empty() and coverage >= 0.35:
			# Small intonation/model wobble is free; larger errors retain the scale.
			pitch_score = clampf(100.0 - 18.0 * error_sum / errors.size(), 0.0, 100.0)
			# Correlation guards against flat/unrelated notes, not a percentage grade.
			# Constant reference phrases are exempt (correlation is undefined there).
			var expected_range := _range(references[i])
			if expected_range >= 3.0:
				contour_factor = clampf(_correlation(matched_user, matched_reference) / CONTOUR_FULL_CREDIT, 0.0, 1.0)
		error_scores.append(pitch_score)
		contour_factors.append(contour_factor)
		scores.append(pitch_score * contour_factor)
		warps.append(max_warp)
		coverages.append(coverage)
		correlations.append(_correlation(matched_user, matched_reference))
	return {"scores": scores, "transposition_semitones": shift,
		"max_alignment_seconds": warps, "matched_reference_fraction": coverages,
		"octave_corrected_frames": corrected, "reference_octave_corrected_frames": reference_corrected,
		"correlations": correlations, "error_scores": error_scores, "contour_factors": contour_factors}


static func _correlation(a: Array[float], b: Array[float]) -> float:
	if a.is_empty(): return 0.0
	var mean_a := 0.0
	var mean_b := 0.0
	for i in a.size():
		mean_a += a[i] / a.size()
		mean_b += b[i] / b.size()
	var covariance := 0.0
	var variance_a := 0.0
	var variance_b := 0.0
	for i in a.size():
		covariance += (a[i] - mean_a) * (b[i] - mean_b)
		variance_a += pow(a[i] - mean_a, 2)
		variance_b += pow(b[i] - mean_b, 2)
	return covariance / sqrt(variance_a * variance_b) if variance_a * variance_b > 0.000001 else 0.0


static func _prepare(line: Dictionary) -> Dictionary:
	var times: PackedFloat32Array = line.get("voiced_times", PackedFloat32Array())
	var hz: PackedFloat32Array = line.get("voiced_pitches", PackedFloat32Array())
	var pitches: Array[float] = []
	for pitch in hz: pitches.append(12.0 * log(maxf(pitch, 0.001)) / log(2.0))
	var original: Array[float] = pitches.duplicate()
	var corrected := 0
	var i := 1
	while i + 1 < pitches.size():
		var jump: float = original[i] - original[i - 1]
		if absf(absf(jump) - 12.0) > OCTAVE_TOLERANCE or times[i] - times[i - 1] > 0.04:
			i += 1
			continue
		var end := i
		var shift := 12.0 * signf(jump)
		while end < pitches.size() and times[end] - times[i] < MAX_OCTAVE_ISLAND_SECONDS:
			if absf(original[end] - original[i - 1]) <= OCTAVE_TOLERANCE: break
			if absf(original[end] - shift - original[i - 1]) > OCTAVE_TOLERANCE: break
			if end > i and times[end] - times[end - 1] > 0.04: break
			end += 1
		# Only short islands bracketed by agreeing real observations are corrected.
		# Never fold sustained notes, phrase starts/ends or an entire line by octaves.
		if end < pitches.size() and times[end] - times[i] <= MAX_OCTAVE_ISLAND_SECONDS \
				and times[end] - times[end - 1] <= 0.04 \
				and absf(original[end] - original[i - 1]) <= OCTAVE_TOLERANCE:
			for frame in range(i, end):
				pitches[frame] -= shift
				corrected += 1
			i = maxi(end, i + 1)
		else:
			i += 1
	var values: Array[float] = []
	var valid: Array[bool] = []
	var duration := float(line.get("duration", 0.0))
	var left := 0
	for point in POINTS:
		var time := duration * point / (POINTS - 1)
		if times.is_empty():
			values.append(0.0)
			valid.append(false)
			continue
		while left + 1 < times.size() and times[left + 1] <= time: left += 1
		var right := mini(left + 1, times.size() - 1)
		var gap := float(times[right] - times[left])
		var fraction := clampf((time - times[left]) / maxf(gap, 0.00001), 0.0, 1.0)
		values.append(lerpf(pitches[left], pitches[right], fraction))
		valid.append(time >= times[0] - 0.03 and time <= times[-1] + 0.03 and
			(gap <= MAX_INTERPOLATED_GAP or absf(time - times[left]) <= 0.03 or absf(time - times[right]) <= 0.03))
	return {"values": values, "valid": valid, "duration": duration, "corrected": corrected}


static func _cost(user: Dictionary, reference: Dictionary, i: int, j: int, shift: float) -> float:
	if not user.valid[i] or not reference.valid[j]:
		return 0.0 if user.valid[i] == reference.valid[j] else 1.5
	return absf(float(user.values[i]) - shift - float(reference.values[j]))


static func _align(user: Dictionary, reference: Dictionary, shift: float) -> Dictionary:
	var duration := maxf(float(reference.duration), float(user.duration))
	var band := maxi(1, floori(minf(MAX_WARP_FRACTION, MAX_WARP_SECONDS / maxf(duration, 0.01)) * (POINTS - 1)))
	var costs := PackedFloat64Array()
	var steps := PackedInt32Array()
	costs.resize(POINTS * POINTS)
	costs.fill(INF)
	steps.resize(costs.size())
	costs[0] = 2.0 * _cost(user, reference, 0, 0, shift)
	for i in range(1, POINTS):
		for j in range(maxi(1, i - band), mini(POINTS, i + band + 1)):
			var index := i * POINTS + j
			var local := _cost(user, reference, i, j, shift)
			var best := costs[(i - 1) * POINTS + j - 1] + 2.0 * local
			var step := 1
			if j >= 2 and abs(i - (j - 1)) <= band:
				var candidate := costs[(i - 1) * POINTS + j - 2] + 1.5 * (local + _cost(user, reference, i, j - 1, shift)) + 0.1
				if candidate < best:
					best = candidate
					step = 2
			if i >= 2 and abs((i - 1) - j) <= band:
				var candidate := costs[(i - 2) * POINTS + j - 1] + 1.5 * (local + _cost(user, reference, i - 1, j, shift)) + 0.1
				if candidate < best:
					best = candidate
					step = 3
			costs[index] = best
			steps[index] = step
	var pairs: Array[Vector2i] = []
	var i := POINTS - 1
	var j := POINTS - 1
	while i > 0 and j > 0:
		pairs.append(Vector2i(i, j))
		var step := steps[i * POINTS + j]
		if step == 2:
			pairs.append(Vector2i(i, j - 1))
			j -= 1
		elif step == 3:
			pairs.append(Vector2i(i - 1, j))
			i -= 1
		i -= 1
		j -= 1
	pairs.append(Vector2i(0, 0))
	pairs.reverse()
	return {"pairs": pairs}


static func _range(contour: Dictionary) -> float:
	var values: Array[float] = []
	for i in POINTS:
		if contour.valid[i]: values.append(contour.values[i])
	if values.is_empty(): return 0.0
	values.sort()
	return values[floori((values.size() - 1) * 0.9)] - values[floori((values.size() - 1) * 0.1)]


static func _median(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 else (sorted[middle - 1] + sorted[middle]) * 0.5
