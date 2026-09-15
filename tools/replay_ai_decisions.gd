extends SceneTree

func _initialize() -> void:
	var path := ""
	var last := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--trace="): path = arg.trim_prefix("--trace=")
		if arg.begins_with("--last="): last = int(arg.trim_prefix("--last="))
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Use --trace=<developer .trace file>")
		quit(1)
		return
	var data: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("format") != 1:
		quit(1)
		return
	var failures: Array = []
	if last > 0: data.records = data.records.slice(maxi(0, data.records.size() - last))
	for record: Dictionary in data.records:
		if "--summary" in OS.get_cmdline_user_args():
			print("AI_TRACE_STEP ", JSON.stringify({"actor": record.observation.state.self.id, "energy": record.observation.state.self.energy, "position": record.observation.state.self.position, "selected": record.selected, "goal": record.goal_after.current, "candidates": record.candidates}))
			print("AI_TRACE_CONTEXT ", JSON.stringify({"memory": record.observation.memory, "section": record.observation.state.section, "self": record.observation.state.self, "phase": record.observation.state.phase}))
		var result := AIDecisionTrace.replay(record)
		if not result.matches: failures.append(result)
	print("AI_REPLAY ", JSON.stringify({"decisions": data.records.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
