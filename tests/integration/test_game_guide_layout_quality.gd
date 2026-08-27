extends GutTest

## Player-facing layout contracts for the digital guide.  These assertions are
## intentionally semantic (Control geometry, declared media identity and focus)
## rather than screenshot-pixel comparisons, so art can be replaced safely.

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_DISCOVERY_PATH := "user://guide-layout-quality-test.cfg"
const GENERATED_CATALOG_PATH := "res://UI/GameGuide/generated/manual_catalog.json"

const MIN_BODY_FONT_SIZE := 26
const MIN_SUPPORTING_FONT_SIZE := 22
const MIN_BUTTON_WIDTH := 96.0
const MIN_BUTTON_HEIGHT := 54.0
const MIN_PORTRAIT_MEDIA_WIDTH := 320.0
const MAX_EMPTY_BLOCK_VIEWPORT_RATIO := 0.20
const MAX_TRAILING_BLANK_VIEWPORT_RATIO := 0.32
const TARGET_VIEWPORTS: Array[Vector2] = [
	Vector2(1280, 720),
	Vector2(1920, 1080),
	Vector2(2560, 1600),
	Vector2(2048, 1536),
	Vector2(3440, 1440),
]

var _guide: DigitalGameGuide
var _paused_backup: bool
var _storage_backup: String
var _test_storage_enabled_backup: bool
var _discovered_backup: Dictionary
var _game_on_backup: bool


func before_each() -> void:
	_paused_backup = get_tree().paused
	get_tree().paused = false
	_storage_backup = DiscoveryManager._storage_path
	_test_storage_enabled_backup = DiscoveryManager._test_storage_enabled
	_discovered_backup = DiscoveryManager._discovered.duplicate(true)
	_game_on_backup = TurnManager.GameOn
	TurnManager.GameOn = false
	_remove_discovery_file()
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)
	_discover_every_known_entry()
	_guide = GUIDE_SCENE.instantiate() as DigitalGameGuide
	add_child_autofree(_guide)
	await get_tree().process_frame


func after_each() -> void:
	if _guide != null and _guide.is_guide_open():
		_guide.close_guide(false)
	_remove_discovery_file()
	DiscoveryManager._storage_path = _storage_backup
	DiscoveryManager._test_storage_enabled = _test_storage_enabled_backup
	DiscoveryManager._discovered = _discovered_backup.duplicate(true)
	TurnManager.GameOn = _game_on_backup
	get_tree().paused = _paused_backup


func test_all_rule_pages_keep_player_facing_copy_above_the_readability_floor() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_set_guide_size(Vector2(1920, 1080))
	for destination: Dictionary in _all_content_destinations():
		_render_destination(destination)
		await _settle_layout()
		var article := _guide.get_node("%Article") as Control
		for node: Node in _descendants(article):
			if not node is Control or not (node as Control).is_visible_in_tree():
				continue
			if node is RichTextLabel:
				var rich := node as RichTextLabel
				if rich.get_parsed_text().strip_edges().is_empty():
					continue
				assert_gte(
					rich.get_theme_font_size("normal_font_size"),
					MIN_BODY_FONT_SIZE,
					"%s 的正文不能小于 %dpx：%s" % [destination.label, MIN_BODY_FONT_SIZE, rich.get_parsed_text().left(32)]
				)
			elif node is Label:
				var label := node as Label
				if label.text.strip_edges().is_empty():
					continue
				assert_gte(
					label.get_theme_font_size("font_size"),
					MIN_SUPPORTING_FONT_SIZE,
					"%s 的辅助文字不能小于 %dpx：%s" % [destination.label, MIN_SUPPORTING_FONT_SIZE, label.text.left(32)]
				)


func test_visible_guide_buttons_keep_a_comfortable_click_target_at_supported_sizes() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	for viewport_size: Vector2 in TARGET_VIEWPORTS:
		_set_guide_size(viewport_size)
		for destination: Dictionary in _representative_interaction_destinations():
			_render_destination(destination)
			await _settle_layout()
			for node: Node in _descendants(_guide):
				if not node is Button:
					continue
				var button := node as Button
				if not button.is_visible_in_tree():
					continue
				assert_gte(button.size.x, MIN_BUTTON_WIDTH, "%s @ %s 的按钮过窄：%s" % [destination.label, viewport_size, button.name])
				assert_gte(button.size.y, MIN_BUTTON_HEIGHT, "%s @ %s 的按钮过矮：%s" % [destination.label, viewport_size, button.name])
				if not button.disabled:
					assert_eq(button.focus_mode, Control.FOCUS_ALL, "%s 必须可由键盘/手柄聚焦" % button.name)


func test_declared_media_fills_a_meaningful_share_of_the_article_in_wide_and_narrow_layouts() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var declarations := _media_declarations()
	assert_gt(declarations.size(), 0)
	for viewport_size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720)]:
		_set_guide_size(viewport_size)
		var narrow := bool(_guide.get("_narrow_layout"))
		for declaration: Dictionary in declarations:
			_render_media_declaration(declaration)
			await _settle_layout()
			var article := _guide.get_node("%Article") as Control
			var article_width := maxf(article.size.x, 1.0)
			var media_nodes := _media_nodes_for_id(StringName(declaration.id))
			assert_false(media_nodes.is_empty(), "媒体声明必须生成版面内容：%s/%s" % [declaration.topic_id, declaration.id])
			var layout := _normalize_media_layout(String(declaration.layout))
			var combined_width := 0.0
			for media: Control in media_nodes:
				var visible_media_width := _displayed_texture_width(media)
				combined_width += visible_media_width
				match layout:
					"full":
						assert_gte(media.size.x / article_width, 0.70, "%s 的主图宽度至少应占正文 70%%" % declaration.id)
						assert_gte(visible_media_width / article_width, 0.58 if not narrow else 0.70, "%s 的实际图像过小，不能用宽而矮的空槽冒充大图" % declaration.id)
					"pair":
						var minimum_ratio := 0.78 if narrow else 0.36
						# A pair declaration may currently contain only one authored path;
						# in that case it behaves as a full-width visual.
						if media_nodes.size() == 1:
							minimum_ratio = 0.70
						assert_gte(media.size.x / article_width, minimum_ratio, "%s 的对照图过小" % declaration.id)
						if media_nodes.size() == 1:
							assert_gte(visible_media_width / article_width, 0.58 if not narrow else 0.70, "%s 的单张对照图实际显示过小" % declaration.id)
					"sequence", "gallery":
						var minimum_ratio := 0.78 if narrow else 0.24
						if media_nodes.size() == 1:
							minimum_ratio = 0.70
						# Container gaps can leave the mathematically exact 24% column a
						# fraction of a pixel below the ratio after integer layout.
						assert_gte(media.size.x / article_width + 0.002, minimum_ratio, "%s 的步骤图过小" % declaration.id)
						if media_nodes.size() == 1:
							assert_gte(visible_media_width / article_width, 0.58 if not narrow else 0.70, "%s 的单张步骤图实际显示过小" % declaration.id)
					"portrait":
						assert_gte(media.size.x, minf(MIN_PORTRAIT_MEDIA_WIDTH, article_width), "%s 的竖版牌图不得小于 %.0fpx" % [declaration.id, MIN_PORTRAIT_MEDIA_WIDTH])
			if not narrow and media_nodes.size() > 1 and layout in ["pair", "sequence", "gallery"]:
				assert_gte(combined_width / article_width, 0.70, "%s 的整组配图没有充分利用正文宽度" % declaration.id)


func test_every_declared_media_path_exists_and_is_consumed_exactly_once() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	_set_guide_size(Vector2(1920, 1080))
	for declaration: Dictionary in _media_declarations():
		_render_media_declaration(declaration)
		await _settle_layout()
		var path_counts: Dictionary = {}
		for media: Control in _media_nodes_for_id(StringName(declaration.id)):
			var rendered_path := String(media.get_meta(&"guide_media_path", ""))
			if not rendered_path.is_empty():
				path_counts[rendered_path] = int(path_counts.get(rendered_path, 0)) + 1
		var requires_declared_paths := (
			String(declaration.get("provider", "static")) == "static"
			or StringName(declaration.get("dynamic_kind", &"")) == &"guide_capture"
		)
		if not requires_declared_paths:
			continue
		for declared_path: String in declaration.paths:
			assert_true(ResourceLoader.exists(declared_path), "指南声明的配图必须真实存在：%s" % declared_path)
			if ResourceLoader.exists(declared_path):
				assert_eq(int(path_counts.get(declared_path, 0)), 1, "每张配图必须恰好进入版面一次：%s" % declared_path)


func test_supported_layouts_have_no_blank_spacer_blocks_and_always_offer_valid_focus() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	for viewport_size: Vector2 in TARGET_VIEWPORTS:
		_set_guide_size(viewport_size)
		for destination: Dictionary in _representative_interaction_destinations():
			_render_destination(destination)
			await _settle_layout()
			var scroll := _guide.get_node("%ArticleScroll") as ScrollContainer
			var article := _guide.get_node("%Article") as Control
			assert_gte(article.size.x, scroll.size.x * 0.94, "%s @ %s 的正文栏没有利用可用宽度" % [destination.label, viewport_size])
			for child: Node in article.get_children():
				if not child is Control or not (child as Control).is_visible_in_tree():
					continue
				var control := child as Control
				var suspicious_height := scroll.size.y * MAX_EMPTY_BLOCK_VIEWPORT_RATIO
				if control.size.y < suspicious_height or control is HSeparator:
					continue
				assert_true(_has_visible_payload(control), "%s 出现占据大片空间但没有文字、图片或交互的空白块：%s" % [destination.label, control.name])
			# A deliberately text-only short rule (for example “准备阶段”) may
			# naturally be shorter than the viewport. Only flag trailing space when
			# the article actually overflows and therefore could hide a phantom
			# spacer below real content.
			if article.size.y > scroll.size.y + 1.0:
				var payload_bottom := _visible_payload_bottom(article)
				var trailing_blank := maxf(article.size.y - payload_bottom, 0.0)
				assert_lte(
					trailing_blank / maxf(scroll.size.y, 1.0),
					MAX_TRAILING_BLANK_VIEWPORT_RATIO,
					"%s @ %s 的滚动正文末尾空白超过可视区 %.0f%%" % [destination.label, viewport_size, MAX_TRAILING_BLANK_VIEWPORT_RATIO * 100.0]
				)
			_guide.call(&"_focus_current_view")
			await get_tree().process_frame
			var focused := get_viewport().gui_get_focus_owner() as Control
			assert_not_null(focused, "%s @ %s 必须有明确初始焦点" % [destination.label, viewport_size])
			if focused != null:
				assert_true(_guide.is_ancestor_of(focused), "焦点不得落到指南之外")
				assert_true(focused.is_visible_in_tree(), "焦点不得落在隐藏控件")
				assert_eq(focused.focus_mode, Control.FOCUS_ALL)
				if focused is BaseButton:
					assert_false((focused as BaseButton).disabled, "焦点不得落到禁用按钮")


func _all_content_destinations() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"kind": &"home", "label": "指南首页"},
		{"kind": &"rules_index", "label": "规则介绍"},
		{"kind": &"compendium", "label": "探索图鉴"},
	]
	var catalog := _guide.get("_catalog") as ManualCatalog
	for topic: ManualTopic in catalog.get_topics():
		if topic.category == &"quick":
			result.append({"kind": &"topic", "topic_id": topic.topic_id, "group_id": &"", "label": String(topic.topic_id)})
		else:
			for group: Dictionary in topic.groups:
				result.append({
					"kind": &"topic",
					"topic_id": topic.topic_id,
					"group_id": StringName(group.get("id", &"")),
					"label": "%s/%s" % [topic.topic_id, group.get("id", "")],
				})
	return result


func _representative_interaction_destinations() -> Array[Dictionary]:
	return [
		{"kind": &"home", "label": "指南首页"},
		{"kind": &"rules_index", "label": "规则介绍"},
		{"kind": &"topic", "topic_id": &"quick_move", "group_id": &"", "label": "快速上手"},
		{"kind": &"topic", "topic_id": &"goal_resources", "group_id": &"player_setup", "label": "详细规则"},
		{"kind": &"topic", "topic_id": &"goal_resources", "group_id": &"mode_selection", "label": "模式与人数"},
		{"kind": &"topic", "topic_id": &"turn_phases", "group_id": &"begin_phase", "label": "准备阶段"},
		{"kind": &"topic", "topic_id": &"functional_tiles", "group_id": &"plain_and_start", "label": "普通格与起点"},
		{"kind": &"topic", "topic_id": &"digital_rulings", "group_id": &"tied_extremes", "label": "并列裁定"},
		{"kind": &"compendium", "label": "探索图鉴"},
	]


func _render_destination(destination: Dictionary) -> void:
	match StringName(destination.get("kind", &"")):
		&"home":
			_guide.call(&"_render_home")
		&"rules_index":
			_guide.call(&"_render_rules_index", "", false)
		&"compendium":
			_guide.call(&"_render_compendium", DiscoveryManager.KIND_FOOD, 0)
		&"topic":
			_guide.call(&"_render_topic", StringName(destination.get("topic_id", &"")), StringName(destination.get("group_id", &"")))


func _render_media_declaration(declaration: Dictionary) -> void:
	if bool(declaration.get("is_home", false)):
		_guide.call(&"_render_home")
	else:
		_guide.call(&"_render_topic", StringName(declaration.topic_id), StringName(declaration.group_id))


func _set_guide_size(viewport_size: Vector2) -> void:
	_guide.size = viewport_size
	_guide.call(&"_update_responsive_layout")


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _media_nodes_for_id(media_id: StringName) -> Array[Control]:
	var result: Array[Control] = []
	for node: Node in _descendants(_guide.get_node("%Article")):
		if node is Control and (node as Control).is_visible_in_tree() and node.has_meta(&"guide_media_path"):
			if StringName(node.get_meta(&"guide_media_id", &"")) == media_id:
				result.append(node as Control)
	return result


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
					"layout": String(entry.get("layout", "full")),
					"paths": paths,
					"provider": String(entry.get("provider", "static")).to_lower(),
					"dynamic_kind": StringName(String(entry.get("dynamic_kind", ""))),
					"is_home": topic_id == &"home",
				})
	return result


func _normalize_media_layout(value: String) -> String:
	match value.to_lower():
		"wide":
			return "full"
		"split":
			return "pair"
		"stack":
			return "sequence"
		"grid":
			return "gallery"
		"full", "pair", "sequence", "gallery", "portrait":
			return value.to_lower()
		_:
			return "full"


func _displayed_texture_width(media: Control) -> float:
	if not media is TextureRect:
		return media.size.x
	var texture_rect := media as TextureRect
	if texture_rect.texture == null or media.size.x <= 0.0:
		return 0.0
	# FIT_WIDTH_PROPORTIONAL derives its rendered height from the available width.
	# Depending on where the assertion lands in the container sort cycle, Godot may
	# still report a zero control height even though the texture already consumes the
	# full width.  Treat this mode as width-driven instead of manufacturing a false
	# "0 px image" failure.
	if texture_rect.expand_mode == TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL:
		return media.size.x
	if texture_rect.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		return media.size.x
	if media.size.y <= 0.0:
		return media.size.x
	var texture_size := texture_rect.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return 0.0
	var texture_aspect := texture_size.x / texture_size.y
	var control_aspect := media.size.x / media.size.y
	return media.size.x if texture_aspect >= control_aspect else media.size.y * texture_aspect


func _has_visible_payload(root: Control) -> bool:
	var nodes: Array[Node] = [root]
	nodes.append_array(_descendants(root))
	for node: Node in nodes:
		if not node is Control or not (node as Control).is_visible_in_tree():
			continue
		if node is Label and not (node as Label).text.strip_edges().is_empty():
			return true
		if node is RichTextLabel and not (node as RichTextLabel).get_parsed_text().strip_edges().is_empty():
			return true
		if node is TextureRect and (node as TextureRect).texture != null:
			return true
		if node is BaseButton and not (node as BaseButton).text.strip_edges().is_empty():
			return true
	return false


func _visible_payload_bottom(article: Control) -> float:
	var bottom := 0.0
	for node: Node in _descendants(article):
		if not node is Control:
			continue
		var control := node as Control
		if not control.is_visible_in_tree() or not _is_direct_payload(control):
			continue
		bottom = maxf(bottom, control.global_position.y - article.global_position.y + control.size.y)
	return bottom


func _is_direct_payload(control: Control) -> bool:
	if control is Label:
		return not (control as Label).text.strip_edges().is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).get_parsed_text().strip_edges().is_empty()
	if control is TextureRect:
		return (control as TextureRect).texture != null
	if control is BaseButton:
		var button := control as BaseButton
		return not button.text.strip_edges().is_empty() or button.icon != null
	return false


func _discover_every_known_entry() -> void:
	for kind: StringName in [
		DiscoveryManager.KIND_FOOD,
		DiscoveryManager.KIND_EVENT,
		DiscoveryManager.KIND_ACHIEVEMENT,
	]:
		for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
			DiscoveryManager.record_discovery(kind, entry_id)


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child: Node in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node := pending.pop_front() as Node
		result.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return result


func _remove_discovery_file() -> void:
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DISCOVERY_PATH))
