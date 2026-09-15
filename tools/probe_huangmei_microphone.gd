extends SceneTree

## Default: negotiate microphone format WITHOUT starting capture.
## --capture: explicit, bounded 3-second capture; print only format/level/status.
## Never save samples. Do not use --capture without the tester's knowledge.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ClassDB.class_exists(&"WindowsVocalCapture"):
		printerr("WindowsVocalCapture is missing; rebuild the native extension")
		quit(2)
		return
	var capture: RefCounted = ClassDB.instantiate(&"WindowsVocalCapture")
	var probe_only := not OS.get_cmdline_user_args().has("--capture")
	if not bool(capture.call("start", 3.0, probe_only)):
		quit(3)
		return
	var deadline := Time.get_ticks_msec() + 10000
	var status: Dictionary = {}
	var peak := 0.0
	while Time.get_ticks_msec() < deadline:
		status = capture.call("get_status")
		peak = maxf(peak, float(status.get("level", 0.0)))
		if bool(status.get("done", false)):
			break
		await process_frame
	print("HUANGMEI_MICROPHONE: ", JSON.stringify(status), " peak_rms=", peak, " probe_only=", probe_only)
	var passed := bool(status.get("done", false)) and str(status.get("error", "")).is_empty()
	if not probe_only and passed:
		var result: Dictionary = capture.call("take_result")
		var check := OnnxCrepeVocalScorer._check_recording_signal(result.get("samples", PackedFloat32Array()))
		print("HUANGMEI_SIGNAL: ", JSON.stringify(check))
		passed = bool(check.ok)
		result.clear()
	capture.call("cancel")
	quit(0 if passed else 1)
