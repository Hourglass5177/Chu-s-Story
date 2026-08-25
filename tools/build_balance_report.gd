extends SceneTree

func _initialize() -> void:
	var input_path := ""
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			input_path = argument.get_slice("=", 1)
		elif argument.begins_with("--output="):
			output_path = argument.get_slice("=", 1)
	if input_path.is_empty() or output_path.is_empty():
		push_error("缺少 --input 或 --output")
		quit(1)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not parsed is Array:
		push_error("平衡报告输入不是 JSON 数组：%s" % input_path)
		quit(1)
		return
	var reports: Array[Dictionary] = []
	for value in parsed as Array:
		if value is Dictionary:
			reports.append(value)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入平衡报告：%s" % output_path)
		quit(1)
		return
	file.store_string(BalanceReportBuilder.build_markdown(reports))
	file.close()
	print("BALANCE_REPORT matches=%d output=%s" % [reports.size(), output_path])
	quit(0)
