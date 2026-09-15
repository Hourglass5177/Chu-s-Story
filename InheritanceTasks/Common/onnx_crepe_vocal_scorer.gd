class_name OnnxCrepeVocalScorer
extends VocalScorer

const HuangmeiSimilarity := preload("res://InheritanceTasks/Common/huangmei_vocal_similarity.gd")

const DEFAULT_REFERENCE_ANALYSIS_PATH: String = (
	"res://arts/非遗媒体资源/数字版/黄梅戏-女驸马-参考分析-v1.json"
)
const DEFAULT_MODEL_PATH: String = (
	"res://InheritanceTasks/AudioNative/models/crepe_tiny.onnx"
)

enum CaptureState {
	IDLE,
	RECORDING,
	SCORING,
}

enum SharedModelState {
	UNINITIALIZED,
	READY,
	FAILED,
}

static var _shared_model_mutex: Mutex = Mutex.new()
static var _shared_model_state: SharedModelState = SharedModelState.UNINITIALIZED
static var _shared_extractor: Object = null
static var _shared_model_error: String = ""
# A worker Callable may release its last external scorer reference immediately
# after posting the deferred completion. Keep the RefCounted scorer alive until
# the main thread has joined and disposed that Thread.
static var _worker_keepalive: Dictionary[int, RefCounted] = {}

var reference_analysis_path: String = DEFAULT_REFERENCE_ANALYSIS_PATH
var model_path: String = DEFAULT_MODEL_PATH

var _state: CaptureState = CaptureState.IDLE
var _generation: int = 0
var _active_reference_id: StringName = &""
var _capture_duration_seconds: float = 0.0
var _record_player: AudioStreamPlayer = null
var _record_effect: AudioEffectRecord = null
var _record_bus_name: StringName = &""
var _worker_thread: Thread = null
var _worker_generation: int = -1
var _capture_paused: bool = false
var _recording_segments: Array[Dictionary] = []
var _native_capture: RefCounted = null


func is_available() -> bool:
	return _get_availability_reason() == &""


func get_unavailable_reason() -> StringName:
	var reason: StringName = _get_availability_reason()
	return reason if reason != &"" else &"vocal_scorer_unavailable"


func begin_capture(reference_id: StringName, duration_seconds: float) -> Error:
	_join_worker_if_finished()
	if _state != CaptureState.IDLE or _worker_thread != null:
		return ERR_BUSY
	if not is_available():
		return ERR_UNAVAILABLE
	if duration_seconds <= 0.0:
		return ERR_INVALID_PARAMETER
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return ERR_UNAVAILABLE

	_generation += 1
	_active_reference_id = reference_id
	_capture_duration_seconds = duration_seconds
	_capture_paused = false
	_recording_segments.clear()
	var setup_error: Error = _create_capture_graph(tree.root)
	if setup_error != OK:
		_cleanup_capture_graph()
		_active_reference_id = &""
		_capture_duration_seconds = 0.0
		return setup_error
	_state = CaptureState.RECORDING
	return OK


func finish_capture_and_score() -> Error:
	if _state != CaptureState.RECORDING or (_record_effect == null and _native_capture == null):
		return ERR_UNCONFIGURED
	if _native_capture != null and not bool(_native_capture.call("get_status").get("done", false)):
		return ERR_BUSY
	var capture_started_usec := Time.get_ticks_usec()
	_state = CaptureState.SCORING
	var scoring_generation: int = _generation
	if not _capture_paused:
		_collect_current_recording_segment()
	var merged_recording: Dictionary = _merge_recording_segments(_recording_segments)
	if _native_capture != null:
		merged_recording = _native_capture.call("take_result")
		merged_recording["reason"] = &"microphone_capture_failed"
		merged_recording["message"] = "录音中断，请检查麦克风后重试"
	_cleanup_capture_graph()
	_capture_paused = false
	_recording_segments.clear()
	_trace_scoring("capture_finished", capture_started_usec)
	if OS.is_debug_build():
		var captured_bytes: PackedByteArray = merged_recording.get("pcm_bytes", PackedByteArray())
		if merged_recording.has("samples"):
			print("HUANGMEI_SCORING: capture_samples=%d rate=%d mono=true" % [
				(merged_recording.samples as PackedFloat32Array).size(), int(merged_recording.sample_rate)])
		else:
			print("HUANGMEI_SCORING: capture_bytes=%d rate=%d stereo=%s" % [captured_bytes.size(), int(merged_recording.get("mix_rate", 0)), bool(merged_recording.get("stereo", false))])
	if not bool(merged_recording.get("ok", false)):
		_defer_technical_result(
			scoring_generation,
			StringName(merged_recording.get("reason", "recording_empty")),
			str(merged_recording.get(
				"message",
				"没有录到有效声音，请检查麦克风权限与设备"
			))
		)
		return OK

	var work: Dictionary = {
		"generation": scoring_generation,
		"reference_id": _active_reference_id,
		"reference_path": reference_analysis_path,
		"model_path": model_path,
		"pcm_bytes": merged_recording.get("pcm_bytes", PackedByteArray()),
		"format": int(merged_recording.get("format", -1)),
		"mix_rate": int(merged_recording.get("mix_rate", 0)),
		"stereo": bool(merged_recording.get("stereo", false)),
	}
	if merged_recording.has("samples"):
		work["decoded"] = merged_recording
	_active_reference_id = &""
	_capture_duration_seconds = 0.0
	_worker_thread = Thread.new()
	_worker_generation = scoring_generation
	var start_error: Error = _worker_thread.start(
		_score_recording_worker.bind(work),
		Thread.PRIORITY_NORMAL
	)
	if start_error != OK:
		_worker_thread = null
		_worker_generation = -1
		_defer_technical_result(
			scoring_generation,
			&"scoring_thread_start_failed",
			"无法启动本地演唱评分"
		)
	else:
		_retain_until_worker_completes()
	return OK


func set_capture_paused(paused: bool) -> void:
	if _native_capture != null:
		_native_capture.call("set_paused", paused)
		_capture_paused = paused
		return
	if _state != CaptureState.RECORDING or _record_effect == null:
		return
	if paused == _capture_paused:
		return
	if paused:
		_collect_current_recording_segment()
		_capture_paused = true
	else:
		# AudioEffectRecord starts a fresh in-memory sample whenever recording is
		# re-enabled. Previously captured bytes already live in _recording_segments.
		_record_effect.set_recording_active(true)
		_capture_paused = false


func cancel_capture() -> void:
	_generation += 1
	_cleanup_capture_graph()
	_active_reference_id = &""
	_capture_duration_seconds = 0.0
	_capture_paused = false
	_recording_segments.clear()
	if _worker_thread != null:
		if _worker_thread.is_started() and not _worker_thread.is_alive():
			_worker_thread.wait_to_finish()
			_worker_thread = null
			_worker_generation = -1
			_release_worker_keepalive()
		_state = CaptureState.SCORING if _worker_thread != null else CaptureState.IDLE
	else:
		_state = CaptureState.IDLE


func is_worker_running() -> bool:
	return _worker_thread != null and _worker_thread.is_started()


func get_capture_status() -> Dictionary:
	return _native_capture.call("get_status") if _native_capture != null else {}


func _get_availability_reason() -> StringName:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return &"microphone_unavailable_headless"
	if OS.get_name() != "Windows" or not ClassDB.class_exists(&"WindowsVocalCapture"):
		return &"microphone_adapter_unavailable"
	if not ClassDB.class_exists(&"CrepePitchExtractor"):
		return &"crepe_extension_unavailable"
	if not FileAccess.file_exists(model_path):
		return &"crepe_model_missing"
	if not FileAccess.file_exists(reference_analysis_path):
		return &"reference_analysis_missing"
	return &""


func _create_capture_graph(_root: Window) -> Error:
	_native_capture = ClassDB.instantiate(&"WindowsVocalCapture") as RefCounted
	if _native_capture == null:
		return ERR_UNAVAILABLE
	return OK if bool(_native_capture.call("start", _capture_duration_seconds, false)) else ERR_CANT_CREATE


func _cleanup_capture_graph() -> void:
	if _native_capture != null:
		_native_capture.call("cancel")
		_native_capture = null
	if _record_effect != null and _record_effect.is_recording_active():
		_record_effect.set_recording_active(false)
	if is_instance_valid(_record_player):
		_record_player.stop()
		_record_player.queue_free()
	_record_player = null
	_record_effect = null
	if _record_bus_name != &"":
		var bus_index: int = AudioServer.get_bus_index(_record_bus_name)
		if bus_index >= 0:
			AudioServer.remove_bus(bus_index)
	_record_bus_name = &""


func _collect_current_recording_segment() -> void:
	if _record_effect == null:
		return
	if _record_effect.is_recording_active():
		_record_effect.set_recording_active(false)
	var recording: AudioStreamWAV = _record_effect.get_recording()
	if recording == null or recording.data.is_empty():
		return
	_recording_segments.append({
		"pcm_bytes": recording.data.duplicate(),
		"format": int(recording.format),
		"mix_rate": int(recording.mix_rate),
		"stereo": bool(recording.stereo),
	})


func _score_recording_worker(work: Dictionary) -> void:
	var generation: int = int(work.get("generation", -1))
	var phase_started_usec := Time.get_ticks_usec()
	_trace_scoring("decode_started", phase_started_usec)
	var decoded: Dictionary = _decode_recording(
		work.get("pcm_bytes", PackedByteArray()) as PackedByteArray,
		int(work.get("format", -1)),
		int(work.get("mix_rate", 0)),
		bool(work.get("stereo", false))
	)
	if work.has("decoded"):
		decoded = work.decoded
	if not bool(decoded.get("ok", false)):
		call_deferred(
			"_complete_worker",
			generation,
			_technical_payload(
				StringName(decoded.get("reason", "recording_decode_failed")),
				str(decoded.get("message", "录音格式无法读取"))
			)
		)
		return

	_trace_scoring("decode_finished", phase_started_usec)
	var signal_check := _check_recording_signal(decoded.get("samples", PackedFloat32Array()))
	if not bool(signal_check.ok):
		call_deferred("_complete_worker", generation, signal_check)
		return
	phase_started_usec = Time.get_ticks_usec()
	var extractor_result: Dictionary = _get_shared_extractor(str(work.get("model_path", "")))
	if not bool(extractor_result.get("ok", false)):
		call_deferred(
			"_complete_worker",
			generation,
			_technical_payload(
				StringName(extractor_result.get("reason", "crepe_model_init_failed")),
				str(extractor_result.get("message", "本地音高模型无法初始化"))
			)
		)
		return
	var extractor: Object = extractor_result.get("extractor") as Object
	_trace_scoring("model_ready", phase_started_usec)
	phase_started_usec = Time.get_ticks_usec()
	var extracted_variant: Variant = extractor.call(
		&"extract_pitch",
		decoded.get("samples", PackedFloat32Array()),
		int(decoded.get("sample_rate", 0))
	)
	if typeof(extracted_variant) != TYPE_DICTIONARY:
		call_deferred(
			"_complete_worker",
			generation,
			_technical_payload(&"crepe_inference_invalid", "本地音高模型返回了无效结果")
		)
		return
	var extracted: Dictionary = extracted_variant
	if not bool(extracted.get("ok", false)):
		call_deferred(
			"_complete_worker",
			generation,
			_technical_payload(
				&"crepe_inference_failed",
				str(extracted.get("error", "本地音高分析失败"))
			)
		)
		return

	_trace_scoring("inference_finished", phase_started_usec)
	phase_started_usec = Time.get_ticks_usec()
	var reference_result: Dictionary = _read_reference_analysis(
		str(work.get("reference_path", DEFAULT_REFERENCE_ANALYSIS_PATH))
	)
	if not bool(reference_result.get("ok", false)):
		call_deferred(
			"_complete_worker",
			generation,
			_technical_payload(
				StringName(reference_result.get("reason", "reference_analysis_invalid")),
				str(reference_result.get("message", "参考唱句数据无法读取"))
			)
		)
		return
	var payload: Dictionary = HuangmeiSimilarity.score(
		extracted,
		reference_result.get("analysis", {}) as Dictionary
	)
	_trace_scoring("comparison_finished", phase_started_usec)
	if OS.is_debug_build():
		# Bounded diagnostic numbers, never samples, lyrics or recognized speech.
		print("HUANGMEI_RESULT: reason=%s score=%.1f lines=%s pitch=%.1f rhythm=%.1f" % [
			payload.reason, payload.score, str(payload.line_scores), payload.pitch, payload.rhythm])
		print("HUANGMEI_ALIGNMENT: ", JSON.stringify(payload.get("details", {})))
	call_deferred("_complete_worker", generation, payload)


static func _check_recording_signal(samples: PackedFloat32Array) -> Dictionary:
	if samples.is_empty():
		return _technical_payload(&"recording_empty", "没有录到声音，请检查麦克风")
	var sum: float = 0.0
	var squared: float = 0.0
	for sample: float in samples:
		if not is_finite(sample):
			return _technical_payload(&"recording_invalid", "录音数据异常，请重试")
		sum += sample
		squared += sample * sample
	var mean := sum / samples.size()
	# Digital silence / DC is not evidence of a badly sung phrase. Do not run
	# pitch inference on an empty signal (including WASAPI's zero-filled input).
	var variance := maxf(0.0, squared / samples.size() - mean * mean)
	if variance < 0.000000000001:
		return _technical_payload(&"recording_no_signal", "没有录到有效声音，请检查麦克风是否静音")
	return {"ok": true}


static func _trace_scoring(stage: String, started_usec: int) -> void:
	# Timings only; never log PCM, recognized lyrics, or any player recording.
	if OS.is_debug_build():
		print("HUANGMEI_SCORING: %s %.1fms" % [stage, (Time.get_ticks_usec() - started_usec) / 1000.0])


func _complete_worker(generation: int, payload: Dictionary) -> void:
	# A cancelled, already-joined worker can still have a deferred callback in the
	# queue. It must never join or reset a newer capture/worker.
	if generation != _worker_generation:
		return
	if _worker_thread != null and _worker_thread.is_started():
		_worker_thread.wait_to_finish()
	_worker_thread = null
	_worker_generation = -1
	var should_emit: bool = generation == _generation and _state == CaptureState.SCORING
	_state = CaptureState.IDLE
	if should_emit:
		scoring_completed.emit(payload)
	_release_worker_keepalive()


func _defer_technical_result(generation: int, reason: StringName, message: String) -> void:
	call_deferred("_complete_deferred_result", generation, _technical_payload(reason, message))


func _complete_deferred_result(generation: int, payload: Dictionary) -> void:
	if generation != _generation or _state != CaptureState.SCORING:
		return
	_state = CaptureState.IDLE
	scoring_completed.emit(payload)


func _join_worker_if_finished() -> void:
	if _worker_thread == null:
		return
	if _worker_thread.is_started() and not _worker_thread.is_alive():
		_worker_thread.wait_to_finish()
		_worker_thread = null
		_worker_generation = -1
		_state = CaptureState.IDLE
		_release_worker_keepalive()


func _retain_until_worker_completes() -> void:
	_worker_keepalive[get_instance_id()] = self


func _release_worker_keepalive() -> void:
	_worker_keepalive.erase(get_instance_id())


static func _get_shared_extractor(requested_model_path: String) -> Dictionary:
	_shared_model_mutex.lock()
	var result: Dictionary = {}
	if _shared_model_state == SharedModelState.READY and _shared_extractor != null:
		result = {"ok": true, "extractor": _shared_extractor}
	elif _shared_model_state == SharedModelState.FAILED:
		result = {
			"ok": false,
			"reason": &"crepe_model_init_failed",
			"message": _shared_model_error,
		}
	elif not ClassDB.class_exists(&"CrepePitchExtractor"):
		_shared_model_state = SharedModelState.FAILED
		_shared_model_error = "CrepePitchExtractor 扩展未加载"
		result = {
			"ok": false,
			"reason": &"crepe_extension_unavailable",
			"message": _shared_model_error,
		}
	elif not FileAccess.file_exists(requested_model_path):
		_shared_model_state = SharedModelState.FAILED
		_shared_model_error = "CREPE 模型文件不存在"
		result = {
			"ok": false,
			"reason": &"crepe_model_missing",
			"message": _shared_model_error,
		}
	else:
		var extractor: Object = ClassDB.instantiate(&"CrepePitchExtractor")
		var model_bytes: PackedByteArray = FileAccess.get_file_as_bytes(requested_model_path)
		var initialized: bool = (
			extractor != null and bool(extractor.call(&"initialize_model", model_bytes))
		)
		if initialized:
			_shared_extractor = extractor
			_shared_model_state = SharedModelState.READY
			_shared_model_error = ""
			result = {"ok": true, "extractor": _shared_extractor}
		else:
			_shared_model_state = SharedModelState.FAILED
			_shared_model_error = (
				str(extractor.call(&"get_last_error"))
				if extractor != null
				else "无法创建 CrepePitchExtractor"
			)
			result = {
				"ok": false,
				"reason": &"crepe_model_init_failed",
				"message": _shared_model_error,
			}
	_shared_model_mutex.unlock()
	return result


static func _decode_recording(
		bytes: PackedByteArray,
		format: int,
		mix_rate: int,
		stereo: bool
) -> Dictionary:
	if bytes.is_empty() or mix_rate <= 0:
		return {
			"ok": false,
			"reason": &"recording_empty",
			"message": "没有录到有效声音",
		}
	var channels: int = 2 if stereo else 1
	var bytes_per_sample: int = 0
	if format == AudioStreamWAV.FORMAT_16_BITS:
		bytes_per_sample = 2
	elif format == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_sample = 1
	else:
		return {
			"ok": false,
			"reason": &"recording_format_unsupported",
			"message": "录音格式不受支持",
		}
	var frame_size: int = channels * bytes_per_sample
	var frame_count: int = bytes.size() / frame_size
	if frame_count <= 0:
		return {
			"ok": false,
			"reason": &"recording_empty",
			"message": "没有录到有效声音",
		}
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for frame: int in frame_count:
		var sum: float = 0.0
		for channel: int in channels:
			var sample_offset: int = (frame * channels + channel) * bytes_per_sample
			if format == AudioStreamWAV.FORMAT_16_BITS:
				var raw: int = int(bytes[sample_offset]) | (int(bytes[sample_offset + 1]) << 8)
				if raw >= 32768:
					raw -= 65536
				sum += float(raw) / 32768.0
			else:
				sum += (float(bytes[sample_offset]) - 128.0) / 128.0
		samples[frame] = sum / float(channels)
	return {"ok": true, "samples": samples, "sample_rate": mix_rate}


static func _merge_recording_segments(segments: Array[Dictionary]) -> Dictionary:
	if segments.is_empty():
		return {
			"ok": false,
			"reason": &"recording_empty",
			"message": "没有录到有效声音",
		}
	var first: Dictionary = segments[0]
	var expected_format: int = int(first.get("format", -1))
	var expected_mix_rate: int = int(first.get("mix_rate", 0))
	var expected_stereo: bool = bool(first.get("stereo", false))
	var merged := PackedByteArray()
	for segment: Dictionary in segments:
		if (
			int(segment.get("format", -1)) != expected_format
			or int(segment.get("mix_rate", 0)) != expected_mix_rate
			or bool(segment.get("stereo", false)) != expected_stereo
		):
			return {
				"ok": false,
				"reason": &"recording_segment_mismatch",
				"message": "录音设备在暂停期间发生变化",
			}
		var segment_bytes: PackedByteArray = segment.get("pcm_bytes", PackedByteArray())
		merged.append_array(segment_bytes)
	if merged.is_empty():
		return {
			"ok": false,
			"reason": &"recording_empty",
			"message": "没有录到有效声音",
		}
	return {
		"ok": true,
		"pcm_bytes": merged,
		"format": expected_format,
		"mix_rate": expected_mix_rate,
		"stereo": expected_stereo,
	}


static func _read_reference_analysis(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": &"reference_analysis_missing",
			"message": "参考唱句数据不存在",
		}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"reason": &"reference_analysis_unreadable",
			"message": "参考唱句数据无法读取",
		}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"reason": &"reference_analysis_invalid",
			"message": "参考唱句数据格式错误",
		}
	return {"ok": true, "analysis": parsed as Dictionary}


static func _technical_payload(reason: StringName, message: String) -> Dictionary:
	return {
		"ok": false,
		"score": 0.0,
		"line_scores": [] as Array[float],
		"completeness": 0.0,
		"pitch": 0.0,
		"rhythm": 0.0,
		"feedback": message,
		"reason": reason,
		"message": message,
	}
