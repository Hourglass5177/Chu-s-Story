extends GutTest

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_VIEWPORT_SIZE := Vector2i(2352, 1275)

var _viewport: SubViewport
var _guide: DigitalGameGuide
var _paused_backup := false
var _game_on_backup := false
var _game_result_backup: GameResult


func before_each() -> void:
	_paused_backup = get_tree().paused
	_game_on_backup = TurnManager.GameOn
	_game_result_backup = TurnManager.get_game_result()
	get_tree().paused = false
	InteractionCoordinator.cancel_all(&"guide_pointer_test_setup")
	TurnManager.invalidate_all_modals(&"guide_pointer_test_setup")
	TurnManager.GameOn = false
	TurnManager._last_game_result = null

	# GUT 自身也有全屏 Control。必须在独立视口中验证真实 GUI 命中顺序，
	# 否则只能证明信号回调能被手工调用，不能证明玩家真的点得到按钮。
	_viewport = SubViewport.new()
	_viewport.name = "GuidePointerViewport"
	_viewport.size = TEST_VIEWPORT_SIZE
	_viewport.gui_disable_input = false
	_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child_autofree(_viewport)

	_guide = GUIDE_SCENE.instantiate() as DigitalGameGuide
	_viewport.add_child(_guide)
	await get_tree().process_frame
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _guide != null and is_instance_valid(_guide) and _guide.is_guide_open():
		_guide.close_guide(false)
	InteractionCoordinator.cancel_all(&"guide_pointer_test_teardown")
	TurnManager.invalidate_all_modals(&"guide_pointer_test_teardown")
	TurnManager.GameOn = _game_on_backup
	TurnManager._last_game_result = _game_result_backup
	get_tree().paused = _paused_backup


func test_left_navigation_and_home_entry_cards_accept_real_pointer_clicks() -> void:
	assert_eq(_guide.size, Vector2(TEST_VIEWPORT_SIZE), "指南必须按用户截图的近似分辨率布局")
	assert_true(_guide.is_guide_open())
	assert_true(_guide.is_interaction_enabled())

	var home_button := _guide.get_node("%HomeButton") as Button
	var quick_button := _guide.get_node("%QuickButton") as Button
	var rules_button := _guide.get_node("%RulesButton") as Button
	var compendium_button := _guide.get_node("%CompendiumButton") as Button
	for button: Button in [home_button, quick_button, rules_button, compendium_button]:
		assert_not_null(button)
		assert_true(button.is_visible_in_tree(), "%s 必须实际可见" % button.name)
		assert_false(button.disabled, "%s 不得被禁用" % button.name)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)

	watch_signals(quick_button)
	assert_true(await _real_pointer_click(quick_button))
	assert_signal_emitted(quick_button, "pressed")
	assert_eq(_current_topic_category(), &"quick")

	watch_signals(rules_button)
	assert_true(await _real_pointer_click(rules_button))
	assert_signal_emitted(rules_button, "pressed")
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.RULES_INDEX)

	watch_signals(compendium_button)
	assert_true(await _real_pointer_click(compendium_button))
	assert_signal_emitted(compendium_button, "pressed")
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.COMPENDIUM)

	watch_signals(home_button)
	assert_true(await _real_pointer_click(home_button))
	assert_signal_emitted(home_button, "pressed")
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.HOME)

	var entry_expectations: Array[Dictionary] = [
		{"prefix": "快速上手", "mode": DigitalGameGuide.ViewMode.TOPIC, "category": &"quick"},
		{"prefix": "规则介绍", "mode": DigitalGameGuide.ViewMode.RULES_INDEX, "category": &""},
		{"prefix": "探索图鉴", "mode": DigitalGameGuide.ViewMode.COMPENDIUM, "category": &""},
	]
	for expected: Dictionary in entry_expectations:
		var entry := _find_article_button(String(expected["prefix"]))
		assert_not_null(entry, "首页必须存在入口卡：%s" % expected["prefix"])
		if entry == null:
			continue
		assert_true(await _real_pointer_click(entry))
		# 入口卡的回调会立即重建 Article，按钮本身在点击后已被释放。
		# 因此用页面状态作为端到端结果，不对已释放的临时按钮做信号查询。
		assert_eq(int(_guide.get("_view_mode")), int(expected["mode"]))
		if not StringName(expected["category"]).is_empty():
			assert_eq(_current_topic_category(), StringName(expected["category"]))
		if String(expected["prefix"]) != "探索图鉴":
			assert_true(await _real_pointer_click(home_button))
			assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.HOME)


func test_motion_and_mouse_down_in_same_frame_still_clicks_sidebar_button() -> void:
	# Windows can deliver the final pointer motion and the following mouse-down in
	# one rendered frame.  This must be tested without an artificial frame between
	# the two events: a deferred focus clear requested by the motion can otherwise
	# run after BaseButton has started its press attempt and silently cancel it.
	var quick_button := _guide.get_node("%QuickButton") as Button
	watch_signals(quick_button)
	var click_position := quick_button.get_global_rect().get_center()

	var motion := InputEventMouseMotion.new()
	motion.position = click_position
	motion.global_position = click_position
	motion.relative = Vector2(8.0, 0.0)
	motion.button_mask = 0
	_viewport.push_input(motion, false)

	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = click_position
	pressed.global_position = click_position
	pressed.pressed = true
	_viewport.push_input(pressed, false)
	await get_tree().process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = click_position
	released.global_position = click_position
	released.pressed = false
	_viewport.push_input(released, false)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emitted(quick_button, "pressed", "同帧 motion→mouse-down 不得吞掉点击")
	assert_eq(_current_topic_category(), &"quick")


func test_repeated_pointer_navigation_does_not_need_retry_clicks() -> void:
	var home_button := _guide.get_node("%HomeButton") as Button
	var quick_button := _guide.get_node("%QuickButton") as Button
	var rules_button := _guide.get_node("%RulesButton") as Button
	var compendium_button := _guide.get_node("%CompendiumButton") as Button
	for cycle: int in range(4):
		await _batched_pointer_click(quick_button, cycle % 2 == 0)
		assert_eq(_current_topic_category(), &"quick", "第 %d 轮快速上手须一次点击生效" % (cycle + 1))

		await _batched_pointer_click(rules_button, cycle % 2 != 0)
		assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.RULES_INDEX, "第 %d 轮规则介绍须一次点击生效" % (cycle + 1))

		await _batched_pointer_click(compendium_button, true)
		assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.COMPENDIUM, "第 %d 轮探索图鉴须一次点击生效" % (cycle + 1))

		await _batched_pointer_click(home_button, false)
		assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.HOME, "第 %d 轮返回首页须一次点击生效" % (cycle + 1))

		# 首页内容由点击回调当场重建。下一帧画面已可见时，入口卡的首次
		# 点击也必须直接生效，不能把第一次输入浪费在焦点或过渡状态上。
		var rules_card := _find_article_button("规则介绍")
		assert_not_null(rules_card)
		if rules_card != null:
			await _batched_pointer_click(rules_card, cycle % 2 == 0)
			assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.RULES_INDEX, "首页入口卡须一次点击生效")
			await _batched_pointer_click(home_button, true)
			assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.HOME)


func _real_pointer_click(control: Control) -> bool:
	var article_scroll := _guide.get_node("%ArticleScroll") as ScrollContainer
	if article_scroll != null and article_scroll.is_ancestor_of(control):
		article_scroll.ensure_control_visible(control)
		await get_tree().process_frame
		await get_tree().process_frame
	var click_position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click_position
	motion.global_position = click_position
	motion.relative = Vector2.ONE
	_viewport.push_input(motion, false)
	await get_tree().process_frame
	var hovered := _viewport.gui_get_hovered_control()
	assert_same(
		hovered,
		control,
		"真实鼠标命中被截获：目标=%s，实际=%s，坐标=%s" % [
			_describe_control(control),
			_describe_control(hovered),
			click_position,
		]
	)
	if hovered != control:
		return false

	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = click_position
	pressed.global_position = click_position
	pressed.pressed = true
	_viewport.push_input(pressed, false)
	# 必须让 mouse-down 单独经过一帧。旧实现会在这一帧 deferred
	# release_focus()，从而取消 BaseButton 的 press_attempt；若按下和松开
	# 同帧注入，测试会假通过，无法复现玩家实际遇到的“按钮没反应”。
	await get_tree().process_frame

	# 模拟手持鼠标时不可避免的轻微位移。按住期间的 motion 也不能释放焦点，
	# 否则一次正常点击仍会被当作取消。
	var held_motion := InputEventMouseMotion.new()
	held_motion.position = click_position + Vector2(1.0, 1.0)
	held_motion.global_position = held_motion.position
	held_motion.relative = Vector2(1.0, 1.0)
	held_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_viewport.push_input(held_motion, false)
	await get_tree().process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = held_motion.position
	released.global_position = held_motion.global_position
	released.pressed = false
	_viewport.push_input(released, false)
	await get_tree().process_frame
	await get_tree().process_frame
	return true


func _batched_pointer_click(control: Control, include_held_motion: bool) -> void:
	var article_scroll := _guide.get_node("%ArticleScroll") as ScrollContainer
	if article_scroll != null and article_scroll.is_ancestor_of(control):
		article_scroll.ensure_control_visible(control)
		await get_tree().process_frame
	var click_position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click_position
	motion.global_position = click_position
	motion.relative = Vector2(5.0, 2.0)
	motion.button_mask = 0
	_viewport.push_input(motion, false)

	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = click_position
	pressed.global_position = click_position
	pressed.pressed = true
	_viewport.push_input(pressed, false)
	await get_tree().process_frame

	var release_position := click_position
	if include_held_motion:
		release_position += Vector2(1.0, 1.0)
		var held_motion := InputEventMouseMotion.new()
		held_motion.position = release_position
		held_motion.global_position = release_position
		held_motion.relative = Vector2.ONE
		held_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		_viewport.push_input(held_motion, false)
		await get_tree().process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = release_position
	released.global_position = release_position
	released.pressed = false
	_viewport.push_input(released, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_article_button(prefix: String) -> Button:
	for node: Node in _descendants(_guide.get_node("%Article")):
		if node is Button and (node as Button).text.begins_with(prefix):
			return node as Button
	return null


func _current_topic_category() -> StringName:
	var catalog := _guide.get("_catalog") as ManualCatalog
	var topic := catalog.get_topic(StringName(_guide.get("_current_topic_id"))) if catalog != null else null
	return topic.category if topic != null else &""


func _describe_control(control: Control) -> String:
	if control == null:
		return "<null>"
	var label := control.name
	if control is Button:
		label += " text=%s" % (control as Button).text.replace("\n", " / ")
	return "%s [%s]<%s> rect=%s mouse_filter=%d visible=%s" % [
		control.get_path(),
		label,
		control.get_class(),
		control.get_global_rect(),
		control.mouse_filter,
		control.is_visible_in_tree(),
	]


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
