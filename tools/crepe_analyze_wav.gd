extends SceneTree


func _initialize() -> void:
	var wav_path := _get_arg("--wav")
	if wav_path.is_empty():
		printerr("用法：--wav=<16-bit PCM WAV>")
		quit(2)
		return
	var parsed := _read_pcm16_wav(wav_path)
	if parsed.is_empty():
		quit(3)
		return
	if not ClassDB.class_exists("CrepePitchExtractor"):
		printerr("CrepePitchExtractor 未加载")
		quit(4)
		return
	var extractor = ClassDB.instantiate("CrepePitchExtractor")
	var model_bytes := FileAccess.get_file_as_bytes("res://InheritanceTasks/AudioNative/models/crepe_tiny.onnx")
	if not extractor.initialize_model(model_bytes):
		printerr(extractor.get_last_error())
		quit(5)
		return
	var result: Dictionary = extractor.extract_pitch(parsed.samples, parsed.sample_rate)
	if not bool(result.get("ok", false)):
		printerr(result.get("error", "音高分析失败"))
		quit(6)
		return
	var times: PackedFloat32Array = result.get("times", PackedFloat32Array())
	var pitches: PackedFloat32Array = result.get("pitches", PackedFloat32Array())
	var confidence: PackedFloat32Array = result.get("confidences", PackedFloat32Array())
	if times.size() != pitches.size() or times.size() != confidence.size():
		printerr("音高分析返回长度不一致")
		quit(7)
		return
	var json_path := _get_arg("--json")
	if not json_path.is_empty():
		var line_break := float(_get_arg("--line-break")) if not _get_arg("--line-break").is_empty() else 5.0
		var output := _build_reference_json(times, pitches, confidence, line_break)
		var absolute_path := ProjectSettings.globalize_path(json_path) if json_path.begins_with("res://") else json_path
		var output_file := FileAccess.open(absolute_path, FileAccess.WRITE)
		if output_file == null:
			printerr("无法写入参考分析：", absolute_path)
			quit(8)
			return
		output_file.store_string(JSON.stringify(output, "\t", false))
		print("已生成参考分析：", json_path)
	else:
		for index in range(times.size()):
			if confidence[index] >= 0.35:
				print("%.3f,%.2f,%.4f" % [times[index], pitches[index], confidence[index]])
	quit(0)


func _get_arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix + "="):
			return arg.trim_prefix(prefix + "=")
	return ""


func _read_pcm16_wav(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("无法读取：", path)
		return {}
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		printerr("不是 RIFF WAV")
		return {}
	file.get_32()
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		printerr("不是 WAVE")
		return {}
	var channels := 0
	var sample_rate := 0
	var bits := 0
	var pcm := PackedByteArray()
	while file.get_position() + 8 <= file.get_length():
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		var chunk_start := file.get_position()
		if chunk_id == "fmt ":
			var format := file.get_16()
			channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()
			file.get_16()
			bits = file.get_16()
			if format != 1:
				printerr("仅支持 PCM WAV")
				return {}
		elif chunk_id == "data":
			pcm = file.get_buffer(chunk_size)
		file.seek(chunk_start + chunk_size + (chunk_size & 1))
	if channels <= 0 or sample_rate <= 0 or bits != 16 or pcm.is_empty():
		printerr("WAV 格式不完整或不是 16-bit PCM")
		return {}
	var frame_count := pcm.size() / (channels * 2)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for frame in range(frame_count):
		var sum := 0.0
		for channel in range(channels):
			var offset := (frame * channels + channel) * 2
			var raw := int(pcm[offset]) | (int(pcm[offset + 1]) << 8)
			if raw >= 32768:
				raw -= 65536
			sum += float(raw) / 32768.0
		samples[frame] = sum / float(channels)
	return {"samples": samples, "sample_rate": sample_rate}


func _build_reference_json(
		times: PackedFloat32Array,
		pitches: PackedFloat32Array,
		confidences: PackedFloat32Array,
		line_break: float
) -> Dictionary:
	var duration := times[-1] if not times.is_empty() else 0.0
	var line_specs := [
		{"lyric": "为救李郎离家园", "start": 0.0, "end": line_break},
		{"lyric": "谁料皇榜中状元", "start": line_break, "end": duration},
	]
	var lines: Array[Dictionary] = []
	for spec: Dictionary in line_specs:
		var line_times: Array[float] = []
		var line_pitches: Array[float] = []
		var line_confidences: Array[float] = []
		for index in range(0, times.size(), 2):
			if times[index] < float(spec.start) or times[index] >= float(spec.end):
				continue
			line_times.append(snappedf(times[index] - float(spec.start), 0.001))
			line_pitches.append(snappedf(pitches[index], 0.01))
			line_confidences.append(snappedf(confidences[index], 0.0001))
		lines.append({
			"lyric": spec.lyric,
			"start": spec.start,
			"end": spec.end,
			"duration": float(spec.end) - float(spec.start),
			"times": line_times,
			"pitches": line_pitches,
			"confidences": line_confidences,
		})
	return {
		"schema_version": 1,
		"task_id": "huangmei_xi",
		"source_file": "arts/非遗媒体资源/黄梅戏-女驸马.mp4",
		"source_sha256": "8BA2BD3FD0B0A2514B2314EE897914EADBD66F97C7F4CF655B37991163CDE741",
		"source_vocal_start": 7.2,
		"source_line_break": 12.2,
		"source_vocal_end": 20.85,
		"reference_sample_rate": 16000,
		"inter_line_gap": 0.0,
		"lines": lines,
	}
