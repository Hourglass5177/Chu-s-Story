extends SceneTree

const MODEL_PATH := "res://InheritanceTasks/AudioNative/models/crepe_tiny.onnx"


func _initialize() -> void:
	if not ClassDB.class_exists(&"CrepePitchExtractor"):
		push_error("CREPE_NATIVE_SMOKE: native class unavailable")
		quit(2)
		return
	var extractor: Object = ClassDB.instantiate(&"CrepePitchExtractor")
	var model_bytes := FileAccess.get_file_as_bytes(MODEL_PATH)
	if not bool(extractor.call(&"initialize_model", model_bytes)):
		push_error("CREPE_NATIVE_SMOKE: model init failed: %s" % extractor.call(&"get_last_error"))
		quit(3)
		return

	const sample_rate := 16000
	var samples := PackedFloat32Array()
	samples.resize(sample_rate)
	for index in sample_rate:
		samples[index] = sin(TAU * 220.0 * float(index) / float(sample_rate)) * 0.35
	var result: Dictionary = extractor.call(&"extract_pitch", samples, sample_rate)
	if not bool(result.get("ok", false)):
		push_error("CREPE_NATIVE_SMOKE: inference failed: %s" % result.get("error", "unknown"))
		quit(4)
		return
	var pitches := result.get("pitches", PackedFloat32Array()) as PackedFloat32Array
	var confidences := result.get("confidences", PackedFloat32Array()) as PackedFloat32Array
	if pitches.is_empty() or pitches.size() != confidences.size():
		push_error("CREPE_NATIVE_SMOKE: invalid output arrays")
		quit(5)
		return
	var voiced := PackedFloat32Array()
	for index in pitches.size():
		if confidences[index] >= 0.5:
			voiced.append(pitches[index])
	voiced.sort()
	if voiced.is_empty():
		push_error("CREPE_NATIVE_SMOKE: sine wave produced no voiced frames")
		quit(6)
		return
	var median_pitch := voiced[voiced.size() / 2]
	if absf(median_pitch - 220.0) > 12.0:
		push_error("CREPE_NATIVE_SMOKE: expected about 220 Hz, got %.2f Hz" % median_pitch)
		quit(7)
		return
	print("CREPE_NATIVE_SMOKE: PASS %.2f Hz (%d voiced frames)" % [median_pitch, voiced.size()])
	quit(0)
