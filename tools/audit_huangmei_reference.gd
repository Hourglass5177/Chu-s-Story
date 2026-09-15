extends SceneTree

## Offline audit of the AUTHORIZED reference only. Never opens a microphone.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stream := load("res://arts/非遗媒体资源/数字版/黄梅戏-女驸马-参考唱段-v1.ogg") as AudioStream
	var playback := stream.instantiate_playback()
	playback.start()
	var samples := PackedFloat32Array()
	var rate := int(AudioServer.get_mix_rate())
	var limit := ceili((stream.get_length() + 0.1) * rate)
	while playback.is_playing() and samples.size() < limit:
		var frames := playback.mix_audio(1.0, 4096)
		if frames.is_empty(): break
		for frame in frames: samples.append((frame.x + frame.y) * 0.5)
	playback.stop()
	var extractor: Object = ClassDB.instantiate(&"CrepePitchExtractor")
	if not extractor.call("initialize_model", FileAccess.get_file_as_bytes(OnnxCrepeVocalScorer.DEFAULT_MODEL_PATH)):
		quit(2)
		return
	var track: Dictionary = extractor.call("extract_pitch", samples, rate)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OnnxCrepeVocalScorer.DEFAULT_REFERENCE_ANALYSIS_PATH))
	print("REFERENCE_AUDIT: ", JSON.stringify(HuangmeiVocalSimilarity.score(track, reference)))
	var times: PackedFloat32Array = track.times
	var pitches: PackedFloat32Array = track.pitches
	var confidences: PackedFloat32Array = track.confidences
	var mismatch := 0
	var compared := 0
	for line: Dictionary in reference.lines:
		for i in line.times.size():
			var t := float(line.start) + float(line.times[i])
			var idx := clampi(roundi(t / 0.01), 0, pitches.size() - 1)
			if confidences[idx] < 0.35 or float(line.confidences[i]) < 0.35: continue
			compared += 1
			if absf(12.0 * log(pitches[idx] / float(line.pitches[i])) / log(2.0)) > 1.0: mismatch += 1
	print("REFERENCE_AUDIT: >1 semitone mismatch=", mismatch, "/", compared)
	var normalized := HuangmeiVocalSimilarity._normalize_reference_lines(reference)
	var split := HuangmeiVocalSimilarity._split_user_track(track, normalized, reference)
	for i in split.size():
		print("LINE ", i, " user=", split[i].first_time, "..", split[i].last_time,
			" ref=", normalized[i].first_time, "..", normalized[i].last_time)
	quit(0)
