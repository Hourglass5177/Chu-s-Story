extends VBoxContainer

## Presentation only: never recompute pass/fail from rounded display values.
const INK := Color("4e2c21")
const MUTED := Color("79543d")
const LYRICS := ["为救李郎离家园", "谁料皇榜中状元"]


func display_result(result: HeritageTaskResult) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visible = result.task_id == &"huangmei_xi"
	if not visible: return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	var scored := result.status in [HeritageTaskResult.Status.SUCCESS, HeritageTaskResult.Status.FAILURE] \
		and bool(result.metrics.get("ok", false)) and result.metrics.has("line_scores")
	if not scored:
		var box := _card()
		_label(box, "未评分", 32)
		return
	var metrics := result.metrics
	var overview := _card()
	_label(overview, "综合得分  %.1f" % float(metrics.get("score", 0.0)), 38)
	_label(overview, "综合60分 · 每句45分 · 两句均须有效发声", 23, MUTED)
	_bar(overview, "发声完整度", float(metrics.get("completeness", 0.0)), "10%")
	_bar(overview, "旋律", float(metrics.get("pitch", 0.0)), "55%")
	_bar(overview, "节奏", float(metrics.get("rhythm", 0.0)), "35%")
	var lines: Array = metrics.get("line_scores", [])
	var details: Dictionary = metrics.get("details", {})
	for i in mini(lines.size(), 2):
		var box := _card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		var lyric := _label(row, LYRICS[i], 28)
		lyric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(row, "%.1f 分" % float(lines[i]), 30)
		var values: Array[String] = []
		for field in [["完整度", "line_completeness"], ["旋律", "line_pitch"], ["节奏", "line_rhythm"]]:
			var scores: Array = details.get(field[1], [])
			values.append("%s  %.1f" % [field[0], scores[i]] if scores.size() > i else "%s  —" % field[0])
		_label(box, "    ·    ".join(values), 23, MUTED)
	var reasons: Array[String] = []
	if result.status == HeritageTaskResult.Status.FAILURE:
		if result.reason == &"insufficient_voiced_audio": reasons.append("未识别到两句足够的发声")
		if float(metrics.get("score", 0.0)) < 60.0: reasons.append("综合分未达到60分")
		for i in mini(lines.size(), 2):
			if float(lines[i]) < 45.0: reasons.append("%s未达到45分" % ["第一句", "第二句"][i])
	if not reasons.is_empty():
		var box := _card()
		_label(box, "；".join(reasons), 24)


func _card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8e9c6")
	style.border_color = Color("c69658")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


func _label(parent: Node, text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent is HBoxContainer: label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _bar(parent: Node, title: String, value: float, weight: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var title_label := _label(row, title, 25)
	title_label.custom_minimum_size.x = 155
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(40, 16)
	bar.show_percentage = false
	bar.value = value
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("d8c39d") if part == "background" else Color("bd652b")
		style.set_corner_radius_all(8)
		bar.add_theme_stylebox_override(part, style)
	row.add_child(bar)
	var score := _label(row, "%.1f" % value, 26)
	score.custom_minimum_size.x = 78
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var weight_label := _label(row, "占%s" % weight, 21, MUTED)
	weight_label.custom_minimum_size.x = 76
