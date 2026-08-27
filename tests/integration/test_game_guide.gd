extends GutTest

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_DISCOVERY_PATH := "user://guide-discovery-test.cfg"
const GENERATED_CATALOG_PATH := "res://UI/GameGuide/generated/manual_catalog.json"
const LOCKED_KINDS: Array[StringName] = [
	DiscoveryManager.KIND_FOOD,
	DiscoveryManager.KIND_EVENT,
	DiscoveryManager.KIND_ACHIEVEMENT,
]

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


func test_home_shows_the_rewritten_preface_without_source_or_art_directives() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	var visible_text := _collect_visible_text(_guide)
	for expected: String in [
		"荆楚大地，山水相连，技艺相传。",
		"在《楚物志》中，你将扮演一名非遗博主，从湖北的一座城市启程。骰子决定这一回合能走多远，精力决定这条路是否走得动；沿途的非遗、风景、食物与事件，又会悄悄改变下一段旅程。你可以专心收藏，也可以经营积分点、抢先完成成就，或等一个合适的时机打出手里的牌。",
		"旅程结束时，所有人的收藏与成就都会化为分数。即使有人早早离场，冠军也要等最后一次计分之后才能确定。",
	]:
		assert_true(expected in visible_text, "指南首页缺少卷首正文：%s" % expected)
	assert_false("唯一正文源" in visible_text)
	assert_false("【卷首主图" in visible_text)


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


func test_locked_food_event_and_achievement_copy_search_and_media_do_not_leak() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var references := _discovery_references()
	assert_false(references.is_empty(), "新规则中的具体食物、事件和成就必须声明发现条件")
	var locked_entries := _all_locked_entries()
	assert_gt(locked_entries.size(), 0, "必须审计全部隐藏条目，而不只审计已经正确标条件的段落")
	var locked_front_paths: Dictionary = {}
	for entry: Dictionary in locked_entries:
		var texture := entry.get("texture") as Texture2D
		if texture != null and not texture.resource_path.is_empty():
			locked_front_paths[texture.resource_path] = true
	var catalog := _guide.get("_catalog") as ManualCatalog
	for topic: ManualTopic in catalog.get_topics(&"rules"):
		for group: Dictionary in topic.groups:
			var group_id := StringName(group.get("id", &""))
			_guide.call(&"_render_topic", topic.topic_id, group_id)
			await get_tree().process_frame
			var visible_text := _collect_visible_text(_guide)
			for entry: Dictionary in locked_entries:
				assert_false(String(entry.title) in visible_text, "未发现的规则正文不得泄露：%s" % entry.title)
			for media: Control in _guide_media_nodes(_guide):
				var media_kind := StringName(media.get_meta(&"guide_media_kind", &""))
				var media_id := StringName(media.get_meta(&"guide_media_id", &""))
				var media_path := String(media.get_meta(&"guide_media_path", ""))
				assert_false(locked_front_paths.has(media_path), "未发现牌面不得通过静态媒体泄露：%s" % media_path)
				for entry: Dictionary in locked_entries:
					assert_false(String(entry.title) in media.tooltip_text, "媒体替代文字不得泄露未发现条目：%s" % entry.title)
				if media_kind in LOCKED_KINDS and not media_id.is_empty():
					assert_true(DiscoveryManager.is_discovered(media_kind, media_id), "未发现牌面不得通过规则媒体泄露：%s:%s" % [media_kind, media_id])

	var requirements_filter := Callable(_guide, &"_requirements_met")
	for entry: Dictionary in locked_entries:
		var title := String(entry.title)
		assert_true(catalog.search(title, &"rules", requirements_filter).is_empty(), "搜索索引不得泄露未发现条目：%s" % title)
	for kind: StringName in LOCKED_KINDS:
		var representative := _first_single_requirement_reference(references, kind)
		if representative.is_empty():
			continue
		var representative_title := _entry_title(kind, StringName(representative.id))
		_guide.call(&"_render_rules_index", representative_title)
		await get_tree().process_frame
		assert_false(representative_title in _collect_visible_text(_guide), "规则搜索界面不得泄露未发现条目：%s" % representative_title)


func test_discovering_one_conditional_rule_reveals_only_that_entry() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var references := _discovery_references()
	for kind: StringName in LOCKED_KINDS:
		var chosen := _first_single_requirement_reference(references, kind)
		assert_false(chosen.is_empty(), "%s 必须至少有一项可独立解锁的规则内容" % kind)
		if chosen.is_empty():
			continue
		var chosen_id := StringName(chosen.id)
		var chosen_title := _entry_title(kind, chosen_id)
		assert_false(chosen_title.is_empty(), "条件规则必须能解析到真实资源：%s:%s" % [kind, chosen_id])
		if chosen_title.is_empty():
			continue
		assert_true(DiscoveryManager.record_discovery(kind, chosen_id))
		_guide.call(&"_render_topic", StringName(chosen.topic_id), StringName(chosen.group_id))
		await get_tree().process_frame
		var visible_text := _collect_visible_text(_guide)
		assert_true(chosen_title in visible_text, "发现后应揭示对应规则：%s" % chosen_title)
		for other: Dictionary in _all_locked_entries():
			if StringName(other.kind) != kind or StringName(other.id) == chosen_id:
				continue
			var other_title := String(other.title)
			if not other_title.is_empty():
				assert_false(other_title in visible_text, "发现一项不得连带泄露：%s" % other_title)
		_guide.call(&"_render_rules_index", chosen_title)
		await get_tree().process_frame
		assert_true(chosen_title in _collect_visible_text(_guide), "发现项必须进入规则搜索：%s" % chosen_title)


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


func test_rules_index_buttons_show_titles_without_embedded_summaries() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.call(&"_render_rules_index")
	await get_tree().process_frame
	var catalog := _guide.get("_catalog") as ManualCatalog
	var expected_titles: Array[String] = []
	for topic: ManualTopic in catalog.search("", &"rules", Callable(_guide, &"_requirements_met")):
		expected_titles.append(topic.title)
	var buttons: Array[Button] = []
	for node: Node in _descendants(_guide.get_node("%Article")):
		if node is Button:
			buttons.append(node as Button)
	assert_eq(buttons.size(), expected_titles.size())
	for button: Button in buttons:
		assert_has(expected_titles, button.text)
		assert_false("\n" in button.text, "目录标题按钮不得混入规则摘要：%s" % button.text)
		assert_lte(button.custom_minimum_size.y, 88.0, "纯标题按钮不应继续占用摘要卡片的高度")


func test_primary_navigation_buttons_are_connected_and_change_view_once() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var required_buttons: Array[Button] = [
		_guide.get_node("%HomeButton") as Button,
		_guide.get_node("%QuickButton") as Button,
		_guide.get_node("%RulesButton") as Button,
		_guide.get_node("%CompendiumButton") as Button,
		_guide.get_node("%CloseButton") as Button,
	]
	for button: Button in required_buttons:
		assert_not_null(button)
		assert_gt(button.pressed.get_connections().size(), 0, "%s 必须连接点击处理" % button.name)

	var quick_button := _guide.get_node("%QuickButton") as Button
	quick_button.pressed.emit()
	await get_tree().process_frame
	var current_topic := (_guide.get("_catalog") as ManualCatalog).get_topic(StringName(_guide.get("_current_topic_id")))
	assert_not_null(current_topic)
	if current_topic == null:
		return
	assert_eq(current_topic.category, &"quick")

	(_guide.get_node("%RulesButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.RULES_INDEX)
	assert_true((_guide.get_node("%Search") as LineEdit).visible)

	(_guide.get_node("%CompendiumButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.COMPENDIUM)

	(_guide.get_node("%HomeButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.HOME)


func test_context_kinds_resolve_to_the_exact_topic_and_section() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var expected: Dictionary = {
		DiscoveryManager.KIND_FEIYI: {"topic_id": &"feiyi_cards", "section_id": &"categories"},
		DiscoveryManager.KIND_FOOD: {"topic_id": &"food_system", "section_id": &"consume_timing"},
		DiscoveryManager.KIND_EVENT: {"topic_id": &"event_response", "section_id": &"draw_discard"},
		DiscoveryManager.KIND_ACHIEVEMENT: {"topic_id": &"achievements", "section_id": &"claiming"},
		DiscoveryManager.KIND_PROFESSION: {"topic_id": &"professions", "section_id": &"food_blogger"},
		DiscoveryManager.KIND_SCENERY: {"topic_id": &"functional_tiles", "section_id": &"scenery_tile"},
		&"map_section": {"topic_id": &"map_movement", "section_id": &"hex_regions"},
		&"market": {"topic_id": &"market_economy", "section_id": &"market_prices"},
		&"score": {"topic_id": &"scoring_victory", "section_id": &"base_score"},
		&"phase": {"topic_id": &"turn_phases", "section_id": &"action_phase"},
	}
	assert_true(_guide.has_method(&"_target_for_kind"))
	for kind: StringName in expected:
		var target: Dictionary = _guide.call(&"_target_for_kind", kind)
		var expected_target := expected[kind] as Dictionary
		assert_eq(StringName(target.get("topic_id", &"")), StringName(expected_target.get("topic_id", &"")), "%s 的情境主题错误" % kind)
		assert_eq(StringName(target.get("section_id", &"")), StringName(expected_target.get("section_id", &"")), "%s 的情境小节错误" % kind)
		assert_true(_guide.navigate_to(StringName(target.topic_id), StringName(target.section_id)))
		await get_tree().process_frame
		assert_eq(StringName(_guide.get("_current_topic_id")), StringName(target.topic_id))
		assert_eq(_guide.get_current_section_id(), StringName(target.section_id))


func test_invalid_catalog_shows_a_closeable_error_instead_of_dead_navigation() -> void:
	var broken := ManualCatalog.new()
	broken.schema_version = 3
	broken.source_path = "res://broken-guide.md"
	broken.load_error = "测试目录损坏"
	assert_true(_guide.has_method(&"set_catalog_for_test"))
	_guide.set_catalog_for_test(broken)
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	var visible_text := _collect_visible_text(_guide)
	assert_true("指南内容读取失败" in visible_text)
	assert_true(broken.load_error in visible_text)
	for path: String in ["%HomeButton", "%QuickButton", "%RulesButton", "%CompendiumButton", "%ContinueButton", "%ContextButton"]:
		assert_true((_guide.get_node(path) as Button).disabled, "错误状态下不得留下能进入空白页的按钮：%s" % path)
	var close_button := _guide.get_node("%CloseButton") as Button
	assert_false(close_button.disabled)
	close_button.pressed.emit()
	await get_tree().process_frame
	assert_false(_guide.is_guide_open())


func test_animated_and_reduced_motion_open_do_not_show_focus_before_directional_navigation() -> void:
	assert_true(_guide.has_method(&"set_force_animations_for_test"))
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	await get_tree().process_frame
	var without_animation := get_viewport().gui_get_focus_owner()
	assert_true(without_animation == null or not _guide.is_ancestor_of(without_animation), "鼠标浏览指南时不应预先出现手柄焦点框")
	_guide.close_guide(false)
	await get_tree().process_frame

	_guide.set_force_animations_for_test(true)
	assert_true(_guide.open_guide(GuideOpenContext.new(), true))
	assert_true(await _wait_until(func() -> bool: return _guide.screen_state == FrontendScreen.ScreenState.ACTIVE, 2.0))
	await _wait_always(0.3)
	var with_animation := get_viewport().gui_get_focus_owner()
	assert_true(with_animation == null or not _guide.is_ancestor_of(with_animation), "入场动画也不得抢先显示手柄焦点框")


func test_first_directional_input_enables_visible_guide_focus_navigation() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	await get_tree().process_frame
	var before_direction := get_viewport().gui_get_focus_owner()
	assert_true(before_direction == null or not _guide.is_ancestor_of(before_direction))
	var direction := InputEventAction.new()
	direction.action = &"ui_down"
	direction.pressed = true
	_guide.call(&"_input", direction)
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner() as Control
	assert_not_null(focused, "第一次方向输入应立即启用选框")
	if focused != null:
		assert_true(_guide.is_ancestor_of(focused))
		assert_true(focused.is_visible_in_tree())
		assert_eq(focused.focus_mode, Control.FOCUS_ALL)


func test_switching_back_to_mouse_hides_the_directional_focus_frame() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	_engage_directional_navigation()
	assert_true(_guide.is_ancestor_of(get_viewport().gui_get_focus_owner()))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(4.0, 0.0)
	_guide.call(&"_input", motion)
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner()
	assert_true(focused == null or not _guide.is_ancestor_of(focused), "改用鼠标后不应残留手柄选框")


func test_topic_pages_show_complete_rules_without_detail_or_related_rules_controls() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var catalog := _guide.get("_catalog") as ManualCatalog
	for topic: ManualTopic in catalog.get_topics():
		var destinations: Array[StringName] = []
		if topic.category == &"quick":
			destinations.append(&"")
		else:
			destinations = _group_ids(topic)
		for group_id: StringName in destinations:
			_guide.call(&"_render_topic", topic.topic_id, group_id)
			await get_tree().process_frame
			for forbidden: String in ["相关规则", "详细规则", "收起详细规则"]:
				assert_false(_has_visible_exact_text(_guide, forbidden), "%s 不应出现旧折叠层：%s" % [topic.topic_id, forbidden])
			var visible_text := _collect_visible_text(_guide)
			assert_false(visible_text.is_empty(), "%s 必须直接显示完整正文" % topic.topic_id)
			var visible_summary := topic.get_visible_summary(Callable(_guide, &"_requirements_met"))
			if not visible_summary.is_empty():
				assert_eq(visible_text.count(visible_summary), 1, "%s 的卷首正文必须完整显示且不得重复" % topic.topic_id)


func test_every_declared_media_entry_renders_with_identity_layout_and_a_real_texture() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var declarations := _media_declarations()
	assert_gt(declarations.size(), 0)
	var heights: Dictionary = {}
	var rendered_count := 0
	for declaration: Dictionary in declarations:
		for requirement: Dictionary in declaration.requirements:
			var requirement_kind := StringName(requirement.get("kind", &""))
			var requirement_id := StringName(requirement.get("id", &""))
			DiscoveryManager.record_discovery(
				requirement_kind,
				requirement_id
			)
			assert_true(DiscoveryManager.is_discovered(requirement_kind, requirement_id))
		if bool(declaration.get("is_home", false)):
			_guide.call(&"_render_home")
		else:
			assert_true(_guide.navigate_to(
				StringName(declaration.topic_id),
				StringName(declaration.group_id)
			))
		await get_tree().process_frame
		await get_tree().process_frame
		var media_nodes: Array[Control] = []
		for candidate: Control in _guide_media_nodes(_guide):
			if StringName(candidate.get_meta(&"guide_media_id", &"")) == StringName(declaration.id):
				media_nodes.append(candidate)
		assert_false(media_nodes.is_empty(), "媒体声明必须生成可见内容：%s/%s" % [declaration.topic_id, declaration.id])
		var rendered_path_counts: Dictionary = {}
		for media: Control in media_nodes:
			rendered_count += 1
			assert_true(media.has_meta(&"guide_media_path"))
			assert_true(media.has_meta(&"guide_media_layout"))
			assert_true(media.has_meta(&"guide_media_kind"))
			assert_true(media.has_meta(&"guide_media_id"))
			assert_false(String(media.get_meta(&"guide_media_layout", "")).is_empty())
			var rendered_path := String(media.get_meta(&"guide_media_path", ""))
			if not rendered_path.is_empty():
				rendered_path_counts[rendered_path] = int(rendered_path_counts.get(rendered_path, 0)) + 1
			heights[roundi(media.custom_minimum_size.y)] = true
			if media is TextureRect:
				assert_not_null((media as TextureRect).texture)
				assert_eq((media as TextureRect).expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
			assert_eq(media.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		var requires_declared_paths := (
			String(declaration.get("provider", "static")) == "static"
			or StringName(declaration.get("dynamic_kind", &"")) == &"guide_capture"
		)
		if requires_declared_paths:
			for declared_path: String in declaration.get("paths", []):
				if ResourceLoader.exists(declared_path):
					assert_eq(int(rendered_path_counts.get(declared_path, 0)), 1, "每张正式配图必须恰好渲染一次：%s" % declared_path)
	assert_gt(rendered_count, 0)
	assert_true(heights.size() > 1 or not heights.has(310), "所有媒体不得继续被固定成同一个310像素高槽")


func test_rule_groups_without_an_authored_image_do_not_receive_generic_filler() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	assert_true(_guide.navigate_to(&"turn_phases", &"begin_phase"))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		_guide_media_nodes(_guide).is_empty(),
		"准备阶段明确不配图时，不能自动塞入整张地图、牌背或其他无关截图"
	)


func test_rule_media_opens_a_focus_safe_preview_and_cancel_only_closes_the_preview() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.call(&"_render_home")
	await get_tree().process_frame
	await get_tree().process_frame
	_engage_directional_navigation()
	var preview_button := _first_media_preview_button(_guide)
	assert_not_null(preview_button, "指南中的实机配图必须可以打开大图")
	if preview_button == null:
		return
	assert_eq(preview_button.accessibility_name, "查看大图")
	assert_false(preview_button.accessibility_description.is_empty())
	preview_button.grab_focus()
	preview_button.pressed.emit()
	await get_tree().process_frame
	var preview := _guide.get_node("%MediaPreview") as Control
	var preview_image := _guide.get_node("%MediaPreviewImage") as TextureRect
	var preview_close := _guide.get_node("%MediaPreviewClose") as Button
	var frame := _guide.get_node("%Frame") as Control
	assert_true(preview.visible)
	assert_not_null(preview_image.texture)
	assert_eq(frame.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_DISABLED, "大图打开时底层指南控件必须退出焦点链")
	assert_same(get_viewport().gui_get_focus_owner(), preview_close)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	_guide.call(&"_unhandled_input", cancel)
	await get_tree().process_frame
	assert_false(preview.visible, "取消键应只关闭大图，而不是退出整本指南")
	assert_eq(frame.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_INHERITED)
	assert_true(_guide.is_guide_open())
	assert_same(get_viewport().gui_get_focus_owner(), preview_button)


func test_discovered_entry_media_uses_the_same_preview_and_backdrop_close_contract() -> void:
	var food_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD)[0]
	assert_true(DiscoveryManager.record_discovery(DiscoveryManager.KIND_FOOD, food_id))
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	assert_true(bool(_guide.call(&"_render_entry_detail", DiscoveryManager.KIND_FOOD, food_id)))
	await get_tree().process_frame
	var preview_button := _first_node_named(_guide, "ManualMediaPreviewButton") as Button
	assert_not_null(preview_button, "探索图鉴详情中的正面牌图也必须能查看大图")
	if preview_button == null:
		return
	preview_button.pressed.emit()
	await get_tree().process_frame
	var preview := _guide.get_node("%MediaPreview") as Control
	assert_true(preview.visible)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	preview.gui_input.emit(click)
	await get_tree().process_frame
	assert_false(preview.visible, "点击大图外的暗色区域应关闭预览")
	assert_true(_guide.is_guide_open())


func test_feiyi_entry_reuses_the_collected_card_detail_content() -> void:
	var feiyi_ids := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FEIYI)
	assert_false(feiyi_ids.is_empty())
	if feiyi_ids.is_empty():
		return
	var entry_id := feiyi_ids[0]
	var card := load(String(entry_id)) as 非遗牌
	assert_not_null(card)
	if card == null:
		return
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	assert_true(bool(_guide.call(&"_render_entry_detail", DiscoveryManager.KIND_FEIYI, entry_id)))
	await get_tree().process_frame
	var visible_text := _collect_visible_text(_guide)
	for expected: String in [
		"湖北省非物质文化遗产",
		"【名称】%s" % card.card_name,
		"【类别】%s" % String(非遗牌.CardCategory.find_key(card.category)),
		"【分数】%d 分" % card.base_score,
		"【描述】%s" % card.description,
		"【效果】%s" % card.effect_description,
	]:
		assert_true(expected in visible_text, "图鉴非遗详情必须复用获得非遗时的字段：%s" % expected)
	assert_not_null(_first_node_named(_guide, "FeiyiCollectedDetail"))
	var card_image := _first_node_named(_guide, "FeiyiCollectedCardImage") as TextureRect
	assert_not_null(card_image)
	if card_image != null:
		assert_same(card_image.texture, card.image_of_front)
	assert_not_null(_first_node_named(_guide, "ManualMediaPreviewButton"), "非遗牌面仍应支持点击查看大图")
	assert_false(_has_visible_exact_text(_guide, "指南"), "指南内部不应递归显示获得弹窗的指南按钮")


func test_feiyi_entry_keeps_a_large_card_and_does_not_overflow_supported_layouts() -> void:
	var entry_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FEIYI)[0]
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	for viewport_size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720)]:
		_guide.size = viewport_size
		_guide.call(&"_update_responsive_layout")
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(bool(_guide.call(&"_render_entry_detail", DiscoveryManager.KIND_FEIYI, entry_id)))
		await get_tree().process_frame
		await get_tree().process_frame
		var detail := _first_node_named(_guide, "FeiyiCollectedDetail") as Control
		var holder := _first_node_named(_guide, "FeiyiCardHolder") as Control
		assert_not_null(detail)
		assert_not_null(holder)
		if detail != null:
			assert_lte(detail.size.x, (_guide.get_node("%Article") as Control).size.x + 1.0, "%s 非遗详情不得横向越界" % viewport_size)
		if holder != null:
			assert_gte(holder.size.x, 450.0, "%s 非遗牌面不得缩成难以阅读的小图" % viewport_size)
			assert_gte(holder.size.y, 650.0, "%s 非遗牌面必须保留可读高度" % viewport_size)


func test_home_focus_starts_on_the_quick_guide_only_after_directional_input() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_focus := get_viewport().gui_get_focus_owner()
	assert_true(initial_focus == null or not _guide.is_ancestor_of(initial_focus))
	var direction := InputEventAction.new()
	direction.action = &"ui_down"
	direction.pressed = true
	_guide.call(&"_input", direction)
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner() as Button
	assert_not_null(focused)
	if focused != null:
		assert_true(focused.text.begins_with("快速上手"))


func test_media_preview_survives_a_breakpoint_rebuild_and_falls_back_to_current_view_focus() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	await get_tree().process_frame
	_engage_directional_navigation()
	var preview_button := _first_media_preview_button(_guide)
	assert_not_null(preview_button)
	if preview_button == null:
		return
	preview_button.grab_focus()
	preview_button.pressed.emit()
	await get_tree().process_frame
	_guide.size = Vector2(1280, 720)
	_guide.call(&"_update_responsive_layout")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true((_guide.get_node("%MediaPreview") as Control).visible)
	_guide.call(&"_close_media_preview")
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner() as Button
	assert_not_null(focused, "原配图节点被响应式重建后仍须回到当前页面的有效焦点")
	if focused != null:
		assert_true(focused.text.begins_with("快速上手"))


func test_authored_markdown_emphasis_is_rendered_as_safe_bbcode() -> void:
	var rendered := String(_guide.call(&"_restricted_markdown_to_bbcode", "**地区：** 决定这张牌从哪里获得。"))
	assert_true("[b]地区：[/b]" in rendered)
	assert_false("**" in rendered)
	var escaped := String(_guide.call(&"_restricted_markdown_to_bbcode", "[b]不能注入[/b]"))
	assert_false("[b]" in escaped)
	assert_true("［b］不能注入［/b］" in escaped)


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


func test_narrow_drawer_keeps_the_selected_section_focusable() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.size = Vector2(1280, 720)
	_guide.call(&"_update_responsive_layout")
	_guide.call(&"_render_home")
	_guide.call(&"_toggle_drawer")
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner() as Button
	assert_same(focused, _guide.get_node("%HomeButton"))
	if focused == null:
		return
	assert_false(focused.disabled)
	assert_true(focused.button_pressed)


func test_selecting_a_destination_from_the_narrow_drawer_closes_it() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.size = Vector2(1280, 720)
	_guide.call(&"_update_responsive_layout")
	_guide.call(&"_render_home")
	_guide.call(&"_toggle_drawer")
	assert_true(bool(_guide.get("_drawer_open")))
	assert_true((_guide.get_node("%Sidebar") as Control).visible)

	(_guide.get_node("%RulesButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_false(bool(_guide.get("_drawer_open")), "选择目录项后必须自动收起抽屉")
	assert_false((_guide.get_node("%Sidebar") as Control).visible)
	assert_true((_guide.get_node("%ContentPanel") as Control).visible)
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.RULES_INDEX)


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


func test_current_topic_reflows_when_crossing_the_responsive_breakpoint() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_guide.size = Vector2(1920, 1080)
	_guide.call(&"_update_responsive_layout")
	var topic_id := _first_topic_with_visible_media()
	assert_false(topic_id.is_empty(), "至少需要一个带可见媒体的规则主题")
	if topic_id.is_empty():
		return
	assert_true(_guide.navigate_to(topic_id))
	await get_tree().process_frame
	await get_tree().process_frame
	var before_nodes := _guide_media_nodes(_guide)
	var before_ids: Array[int] = []
	var before_heights: Array[float] = []
	for media: Control in before_nodes:
		before_ids.append(media.get_instance_id())
		before_heights.append(media.custom_minimum_size.y)

	_guide.size = Vector2(1280, 720)
	_guide.call(&"_update_responsive_layout")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(bool(_guide.get("_narrow_layout")))
	assert_eq(StringName(_guide.get("_current_topic_id")), topic_id)
	var after_nodes := _guide_media_nodes(_guide)
	assert_eq(after_nodes.size(), before_nodes.size())
	var changed := false
	for index: int in range(after_nodes.size()):
		var media := after_nodes[index]
		changed = changed or media.get_instance_id() != before_ids[index] or not is_equal_approx(media.custom_minimum_size.y, before_heights[index])
		assert_lte(media.size.x, (_guide.get_node("%Article") as Control).size.x + 1.0, "窄屏媒体不得横向越界")
	assert_true(changed, "跨过宽窄断点后必须重排当前文章，而不只是隐藏侧栏")
	assert_eq((_guide.get_node("%ArticleScroll") as ScrollContainer).horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)


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
		elif node is RichTextLabel and (node as RichTextLabel).is_visible_in_tree():
			values.append((node as RichTextLabel).get_parsed_text())
		elif node is Button and (node as Button).is_visible_in_tree():
			values.append((node as Button).text)
	return "\n".join(values)


func _has_visible_exact_text(root: Node, expected: String) -> bool:
	for node: Node in _descendants(root):
		if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text == expected:
			return true
		if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == expected:
			return true
	return false


func _guide_media_nodes(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	for node: Node in _descendants(root):
		if node is Control and node.is_visible_in_tree() and node.has_meta(&"guide_media_path"):
			result.append(node as Control)
	return result


func _first_node_named(root: Node, expected_name: String) -> Node:
	for node: Node in _descendants(root):
		if node.name == expected_name:
			return node
	return null


func _first_media_preview_button(root: Node) -> Button:
	for expected_name: String in ["GuideMediaPreviewButton", "ManualMediaPreviewButton"]:
		var button := _first_node_named(root, expected_name) as Button
		if button != null and button.is_visible_in_tree():
			return button
	return null


func _media_declarations() -> Array[Dictionary]:
	var file := FileAccess.open(GENERATED_CATALOG_PATH, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return []
	var raw: Variant = JSON.parse_string(file.get_as_text())
	assert_true(raw is Dictionary)
	if not raw is Dictionary:
		return []
	var result: Array[Dictionary] = []
	var containers: Array = ((raw as Dictionary).get("topics", []) as Array).duplicate()
	containers.append((raw as Dictionary).get("home", {}))
	for topic_value: Variant in containers:
		if not topic_value is Dictionary:
			continue
		var topic := topic_value as Dictionary
		var topic_id := StringName(String(topic.get("id", "")))
		for section_value: Variant in topic.get("sections", []):
			if not section_value is Dictionary:
				continue
			var section := section_value as Dictionary
			for entry_value: Variant in section.get("media_entries", []):
				if not entry_value is Dictionary:
					continue
				var entry := entry_value as Dictionary
				var paths: Array[String] = []
				var single_path := String(entry.get("path", ""))
				if not single_path.is_empty():
					paths.append(single_path)
				for raw_path: Variant in entry.get("paths", []):
					var path := String(raw_path)
					if not path.is_empty() and not paths.has(path):
						paths.append(path)
				result.append({
					"topic_id": topic_id,
					"group_id": StringName(String(section.get("group_id", ""))),
					"id": StringName(String(entry.get("id", ""))),
					"requirements": (entry.get("requirements", []) as Array).duplicate(true),
					"paths": paths,
					"provider": String(entry.get("provider", "static")),
					"dynamic_kind": StringName(String(entry.get("dynamic_kind", ""))),
					"is_home": topic_id == &"home",
				})
	return result


func _discovery_references() -> Array[Dictionary]:
	var file := FileAccess.open(GENERATED_CATALOG_PATH, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return []
	var raw: Variant = JSON.parse_string(file.get_as_text())
	assert_true(raw is Dictionary)
	if not raw is Dictionary:
		return []
	var output: Array[Dictionary] = []
	for topic_value: Variant in (raw as Dictionary).get("topics", []):
		if not topic_value is Dictionary:
			continue
		var topic := topic_value as Dictionary
		var topic_id := StringName(String(topic.get("id", "")))
		_collect_discovery_references(topic.get("summary_requirements", []), topic_id, &"", output)
		for group_value: Variant in topic.get("groups", []):
			if not group_value is Dictionary:
				continue
			var group := group_value as Dictionary
			_collect_discovery_references(
				group.get("requirements", []),
				topic_id,
				StringName(String(group.get("id", ""))),
				output
			)
		for section_value: Variant in topic.get("sections", []):
			if not section_value is Dictionary:
				continue
			var section := section_value as Dictionary
			_collect_discovery_references(
				section,
				topic_id,
				StringName(String(section.get("group_id", ""))),
				output
			)
	var unique: Dictionary = {}
	var result: Array[Dictionary] = []
	for reference: Dictionary in output:
		var key := "%s:%s:%s:%s:%s" % [reference.topic_id, reference.group_id, reference.kind, reference.id, reference.requirement_count]
		if unique.has(key):
			continue
		unique[key] = true
		result.append(reference)
	return result


func _collect_discovery_references(value: Variant, topic_id: StringName, group_id: StringName, output: Array[Dictionary]) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_discovery_references(item, topic_id, group_id, output)
		return
	if not value is Dictionary:
		return
	var dictionary := value as Dictionary
	var requirements: Variant = dictionary.get("requirements", [])
	if requirements is Array:
		for requirement_value: Variant in requirements:
			if not requirement_value is Dictionary:
				continue
			var requirement := requirement_value as Dictionary
			var kind := StringName(String(requirement.get("kind", "")))
			var entry_id := StringName(String(requirement.get("id", "")))
			if kind in LOCKED_KINDS and not entry_id.is_empty():
				output.append({
					"topic_id": topic_id,
					"group_id": group_id,
					"kind": kind,
					"id": entry_id,
					"requirement_count": (requirements as Array).size(),
				})
	for child_key: Variant in dictionary.keys():
		if String(child_key) == "requirements":
			continue
		_collect_discovery_references(dictionary[child_key], topic_id, group_id, output)


func _first_single_requirement_reference(references: Array[Dictionary], kind: StringName) -> Dictionary:
	for reference: Dictionary in references:
		if StringName(reference.get("kind", &"")) == kind and int(reference.get("requirement_count", 0)) == 1:
			return reference
	return {}


func _entry_title(kind: StringName, entry_id: StringName) -> String:
	var data: Dictionary = _guide.call(&"_get_entry_data", kind, entry_id)
	return String(data.get("title", ""))


func _all_locked_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: StringName in LOCKED_KINDS:
		for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
			var data: Dictionary = _guide.call(&"_get_entry_data", kind, entry_id)
			var title := String(data.get("title", ""))
			if title.is_empty():
				continue
			result.append({
				"kind": kind,
				"id": entry_id,
				"title": title,
				"texture": data.get("texture") as Texture2D,
			})
	return result


func _focus_signature(control: Control) -> String:
	if control == null:
		return ""
	if control is Button:
		return "button:%s" % (control as Button).text
	if control is LineEdit:
		return "line_edit:%s" % control.name
	return "%s:%s" % [control.get_class(), control.name]


func _engage_directional_navigation() -> void:
	var direction := InputEventAction.new()
	direction.action = &"ui_down"
	direction.pressed = true
	_guide.call(&"_input", direction)


func _first_topic_with_visible_media() -> StringName:
	var catalog := _guide.get("_catalog") as ManualCatalog
	for topic: ManualTopic in catalog.get_topics():
		_guide.call(&"_render_topic", topic.topic_id)
		if not _guide_media_nodes(_guide).is_empty():
			return topic.topic_id
	return &""


func _group_ids(topic: ManualTopic) -> Array[StringName]:
	var result: Array[StringName] = []
	for group: Dictionary in topic.groups:
		result.append(StringName(group.get("id", &"")))
	return result


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


func _wait_until(predicate: Callable, timeout_seconds: float = 1.0) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())
