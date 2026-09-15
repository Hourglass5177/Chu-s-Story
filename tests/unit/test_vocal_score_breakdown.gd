extends GutTest

const HostScene = preload("res://InheritanceTasks/UI/heritage_task_host.tscn")


func _host(practice: bool = false) -> HeritageTaskHost:
	var host: HeritageTaskHost = HostScene.instantiate()
	add_child_autofree(host)
	host.context = HeritageTaskRunContext.new()
	host.context.practice_mode = practice
	return host


func _result() -> HeritageTaskResult:
	return HeritageTaskResult.new(HeritageTaskResult.Status.FAILURE, &"huangmei_xi",
		&"line_threshold_not_met", "留意第二句", {"ok": true, "score": 65.0,
		"line_scores": [85.5, 44.5], "completeness": 95.0, "pitch": 50.0, "rhythm": 80.0,
		"details": {"line_completeness": [100.0, 90.0], "line_pitch": [80.0, 20.0],
			"line_rhythm": [90.0, 70.0]}})


func test_failed_result_shows_real_total_and_both_line_breakdowns() -> void:
	var host := _host()
	host._show_result(_result())
	var panel := host.get_node("%VocalBreakdown")
	assert_true(panel.visible)
	var labels := _texts(panel)
	for expected in ["综合得分  65.0", "为救李郎离家园", "谁料皇榜中状元", "第二句未达到45分"]:
		assert_string_contains(labels, expected)
	for heading in ["发声完整度", "旋律", "节奏"]: assert_string_contains(labels, heading)
	assert_true(host.return_button.has_focus())
	watch_signals(host)
	host.return_button.pressed.emit()
	assert_signal_emit_count(host, "return_requested", 1)


func test_technical_failure_replaces_scores_with_unscored_and_practice_has_no_refund_claim() -> void:
	var host := _host(true)
	host._show_result(_result())
	host._show_result(HeritageTaskResult.technical_error(&"huangmei_xi", &"no_microphone", "麦克风不可用"))
	assert_string_contains(_texts(host.get_node("%VocalBreakdown")), "未评分")
	assert_false(_texts(host.get_node("%VocalBreakdown")).contains("65.0"))
	assert_false(host.result_message.text.contains("返还"))
	assert_false(host.result_message.text.contains("行动阶段"))


func test_other_tasks_do_not_show_vocal_scores() -> void:
	var host := _host()
	host._show_result(HeritageTaskResult.success(&"alchemy", {"score": 99}))
	assert_false(host.get_node("%VocalBreakdown").visible)


func test_practice_failure_does_not_claim_next_turn_lockout() -> void:
	var host := _host(true)
	host._show_result(_result())
	assert_false(host.result_message.text.contains("行动阶段"))


func test_results_fit_five_viewports_and_return_accepts_one_mouse_click() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)
	var host: HeritageTaskHost = HostScene.instantiate()
	viewport.add_child(host)
	host._show_result(_result())
	watch_signals(host)
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600),
			Vector2i(2048, 1536), Vector2i(3440, 1440)]:
		viewport.size = dimensions
		for frame in 4: await get_tree().process_frame
		var button_rect := host.return_button.get_global_rect()
		assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(button_rect), str(dimensions))
		var scroll: ScrollContainer = host.get_node("%ResultScroll")
		assert_lte(scroll.get_h_scroll_bar().max_value, scroll.get_h_scroll_bar().page + 1.0)
		assert_gt(scroll.size.y, 200.0)
		if dimensions == Vector2i(1280, 720):
			scroll.grab_focus()
			var down := InputEventKey.new()
			down.keycode = KEY_DOWN
			down.pressed = true
			viewport.push_input(down, true)
			assert_gt(scroll.scroll_vertical, 0, "小屏分项必须能用方向键阅读")
	var point := host.return_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		viewport.push_input(click, true)
	assert_signal_emit_count(host, "return_requested", 1)


func _texts(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += _texts(child)
	return text
