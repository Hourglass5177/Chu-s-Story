extends GutTest

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_DISCOVERY_PATH := "user://guide-discovery-test.cfg"

var _guide: DigitalGameGuide
var _paused_backup: bool
var _storage_backup: String
var _discovered_backup: Dictionary
var _game_on_backup: bool
var _decision_provider_backup: Callable
var _game_result_backup: GameResult


func before_each() -> void:
	_paused_backup = get_tree().paused
	get_tree().paused = false
	_storage_backup = DiscoveryManager._storage_path
	_discovered_backup = DiscoveryManager._discovered.duplicate(true)
	_game_on_backup = TurnManager.GameOn
	_game_result_backup = TurnManager.get_game_result()
	_decision_provider_backup = InteractionCoordinator.decision_provider
	TurnManager.GameOn = false
	InteractionCoordinator.cancel_all(&"guide_test_setup")
	InteractionCoordinator.decision_provider = Callable()
	_remove_discovery_file()
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)
	_guide = GUIDE_SCENE.instantiate() as DigitalGameGuide
	add_child_autofree(_guide)
	await get_tree().process_frame


func after_each() -> void:
	if _guide != null and _guide.is_guide_open():
		_guide.close_guide(false)
	_remove_discovery_file()
	DiscoveryManager._storage_path = _storage_backup
	DiscoveryManager._test_storage_enabled = false
	DiscoveryManager._discovered = _discovered_backup.duplicate(true)
	InteractionCoordinator.cancel_all(&"guide_test_teardown")
	InteractionCoordinator.decision_provider = _decision_provider_backup
	TurnManager.GameOn = _game_on_backup
	TurnManager._last_game_result = _game_result_backup
	get_tree().paused = _paused_backup


func test_locked_compendium_cards_do_not_leak_hidden_food_information() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.call(&"_render_compendium", DiscoveryManager.KIND_FOOD, 0)
	var locked_cards := _nodes_named_with_prefix(_guide, "LockedEntry")
	assert_eq(locked_cards.size(), DigitalGameGuide.PAGE_SIZE)
	var visible_text := _collect_visible_text(_guide)
	assert_true("未发现" in visible_text)
	for entry_id: StringName in DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD):
		var data: Dictionary = _guide.call(&"_get_entry_data", DiscoveryManager.KIND_FOOD, entry_id)
		var food_name := String(data.get("title", ""))
		if not food_name.is_empty():
			assert_false(food_name in visible_text, "锁定图鉴不得显示食物名：%s" % food_name)
	for node: Node in locked_cards:
		for descendant: Node in _descendants(node):
			if descendant is Button:
				var button := descendant as Button
				assert_eq(button.text, "未发现")
				assert_eq(button.tooltip_text, "")
				assert_true(button.disabled)


func test_discovered_card_flips_in_place_and_becomes_searchable() -> void:
	var food_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD)[0]
	var data: Dictionary = _guide.call(&"_get_entry_data", DiscoveryManager.KIND_FOOD, food_id)
	var food_name := String(data.get("title", ""))
	assert_true(DiscoveryManager.record_discovery(DiscoveryManager.KIND_FOOD, food_id))
	_guide.open_guide(GuideOpenContext.new(), false)
	_guide.call(&"_render_compendium", DiscoveryManager.KIND_FOOD, 0)
	assert_true(food_name in _collect_visible_text(_guide))
	_guide.call(&"_render_rules_index", food_name)
	assert_true(food_name in _collect_visible_text(_guide), "已发现条目应进入中文搜索结果")


func test_public_rules_and_search_do_not_leak_any_locked_card_name() -> void:
	var catalog := _guide.get("_catalog") as ManualCatalog
	for kind: StringName in [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT]:
		for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
			assert_false(DiscoveryManager.is_discovered(kind, entry_id))
			var data: Dictionary = _guide.call(&"_get_entry_data", kind, entry_id)
			var title := String(data.get("title", ""))
			if not title.is_empty():
				assert_true(catalog.search(title, &"rules").is_empty(), "公开规则不得泄露未发现条目：%s" % title)


func test_rule_search_keeps_keyboard_focus_and_accepts_continuous_input() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.call(&"_render_rules_index")
	await get_tree().process_frame
	var search := _guide.get_node("%Search") as LineEdit
	search.grab_focus()
	search.insert_text_at_caret("江")
	await get_tree().process_frame
	assert_same(get_viewport().gui_get_focus_owner(), search)
	search.insert_text_at_caret("汉")
	await get_tree().process_frame
	assert_eq(search.text, "江汉")
	assert_same(get_viewport().gui_get_focus_owner(), search)


func test_reopening_during_an_exit_keeps_the_existing_modal_and_skips_closed_signal() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var closed_count := {"value": 0}
	_guide.guide_closed.connect(func(_context: GuideOpenContext) -> void: closed_count.value += 1)
	_guide.set("_closing", true)
	_guide.exit_screen(true)
	assert_true(_guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.HUD, &"map_movement"), false))
	await _wait_always(0.25)
	assert_true(_guide.is_guide_open())
	assert_eq(closed_count.value, 0, "取消退场重开不得短暂发出关闭信号")
	assert_eq(StringName(_guide.get("_current_topic_id")), &"map_movement")


func test_narrow_drawer_focus_skips_the_disabled_current_section() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.size = Vector2(1280, 720)
	_guide.call(&"_update_responsive_layout")
	_guide.call(&"_render_home")
	_guide.call(&"_toggle_drawer")
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner() as Button
	assert_same(focused, _guide.get_node("%QuickButton"))
	assert_false(focused.disabled)


func test_guide_uses_drawer_layout_for_narrow_and_four_three_viewports() -> void:
	for viewport_size: Vector2 in [Vector2(1280, 720), Vector2(2048, 1536)]:
		_guide.size = viewport_size
		_guide.call(&"_update_responsive_layout")
		assert_true(bool(_guide.get("_narrow_layout")), "%s 应使用目录抽屉" % viewport_size)
		var scroll := _guide.get_node("%ArticleScroll") as ScrollContainer
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	for viewport_size: Vector2 in [Vector2(1920, 1080), Vector2(2560, 1600), Vector2(3440, 1440)]:
		_guide.size = viewport_size
		_guide.call(&"_update_responsive_layout")
		assert_false(bool(_guide.get("_narrow_layout")), "%s 应使用宽屏三栏层级" % viewport_size)


func test_guide_suspends_active_interaction_and_resumes_its_exact_remaining_time() -> void:
	var ticket := InteractionCoordinator.begin_interaction(
		&"guide_countdown_contract",
		0.8,
		func(_ticket: InteractionTicket): return &"timed_out"
	)
	assert_not_null(ticket)
	var before_open := InteractionCoordinator.get_time_left(ticket.interaction_id)
	assert_gt(before_open, 0.7)

	assert_true(_guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.HUD), false))
	assert_true(InteractionCoordinator.is_active_suspended())
	var frozen_time := InteractionCoordinator.get_time_left(ticket.interaction_id)
	await _wait_always(0.18)
	assert_almost_eq(
		InteractionCoordinator.get_time_left(ticket.interaction_id),
		frozen_time,
		0.035,
		"指南打开期间必须精确冻结活动选择的剩余时间"
	)
	assert_false(InteractionCoordinator.submit(ticket.interaction_id, &"background_submit"), "后台提交不得穿透指南")
	assert_false(InteractionCoordinator.resolve_timeout(ticket.interaction_id), "后台超时不得穿透指南")
	assert_true(ticket.is_waiting())

	_guide.close_guide(false)
	assert_false(InteractionCoordinator.is_active_suspended())
	var resumed_time := InteractionCoordinator.get_time_left(ticket.interaction_id)
	assert_almost_eq(resumed_time, frozen_time, 0.05, "关闭指南后应从原剩余时间继续")
	await _wait_always(0.12)
	assert_lt(InteractionCoordinator.get_time_left(ticket.interaction_id), resumed_time - 0.06)
	assert_true(InteractionCoordinator.submit(ticket.interaction_id, &"confirmed"))
	var result := await InteractionCoordinator.await_result(ticket)
	assert_eq(result.state, InteractionTicket.State.RESOLVED)
	assert_eq(result.value, &"confirmed")
	assert_true(InteractionCoordinator.assert_quiescent("指南关闭后正常结束"))


func test_closing_guide_restores_the_callers_focus_and_scroll_position() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 220)
	add_child_autofree(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(380, 1200)
	scroll.add_child(content)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 700)
	content.add_child(spacer)
	var origin := Button.new()
	origin.text = "原入口"
	content.add_child(origin)
	await get_tree().process_frame
	scroll.scroll_vertical = 520
	await get_tree().process_frame
	var expected_scroll := scroll.scroll_vertical
	var context := GuideOpenContext.new(GuideOpenContext.Source.CARD, &"food_system", &"", &"", origin)
	assert_true(_guide.open_guide(context, false))
	scroll.scroll_vertical = 0
	_guide.close_guide(false)
	await get_tree().process_frame
	assert_eq(scroll.scroll_vertical, expected_scroll)
	assert_same(get_viewport().gui_get_focus_owner(), origin)


func test_closing_an_old_guide_cannot_release_the_terminal_pause() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.HUD), false))
	assert_true(get_tree().paused)
	TurnManager.GameOn = false
	TurnManager._last_game_result = GameResult.new(GameResult.EndReason.SOLO_DEFEAT)
	get_tree().paused = true
	_guide.close_guide(false)
	assert_true(get_tree().paused, "终局接管暂停后，旧指南关闭不得重新放行场景树")


func _collect_visible_text(root: Node) -> String:
	var values: Array[String] = []
	for node: Node in _descendants(root):
		if node is Label and (node as Label).is_visible_in_tree():
			values.append((node as Label).text)
		elif node is Button and (node as Button).is_visible_in_tree():
			values.append((node as Button).text)
	return "\n".join(values)


func _nodes_named_with_prefix(root: Node, prefix: String) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in _descendants(root):
		if String(node.name).begins_with(prefix):
			result.append(node)
	return result


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child: Node in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_front() as Node
		result.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return result


func _remove_discovery_file() -> void:
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DISCOVERY_PATH))


func _wait_always(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout
