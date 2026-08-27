extends GutTest

const GUIDE_SOURCE_PATH := "res://docs/游戏规则与引导（重写稿）.md"
const GENERATED_CATALOG_PATH := "res://UI/GameGuide/generated/manual_catalog.json"
const EXPECTED_SCHEMA_VERSION := 3
const EXPECTED_QUICK_TOPICS := 6
const EXPECTED_RULE_TOPICS := 15
const CAREER_NAMES: PackedStringArray = [
	"美食博主",
	"魔术博主",
	"探险博主",
	"商业博主",
	"旅行博主",
	"生活博主",
]
const CAREER_EFFECT_MARKERS: PackedStringArray = [
	"每个自己的回合最多享用",
	"查看对应牌堆顶最多三张",
	"免费相邻移动",
	"免费刷新货架一次",
	"普通移动每次进入风景格",
	"打工不消耗精力",
]
const REQUIRED_SECTION_TYPES: PackedStringArray = [
	"heading",
	"paragraph",
	"bullets",
	"numbered",
	"table",
	"quote",
	"media",
]
const ALLOWED_SECTION_TYPES: PackedStringArray = [
	"heading",
	"paragraph",
	"bullets",
	"numbered",
	"table",
	"quote",
	"media",
	"divider",
]
const FORBIDDEN_STATIC_MEDIA: PackedStringArray = [
	"res://arts/地图/地块.png",
	"res://arts/成就卡/成就卡（牌面）6.png",
]
const SUPPORTED_DYNAMIC_MEDIA_KINDS: PackedStringArray = [
	"guide_capture",
	"compendium_preview",
	"food_levels",
	"retained_events",
	"achievements",
]
const CORRUPT_CATALOG_PATH := "user://manual-catalog-corrupt-test.json"


func test_generated_catalog_is_schema_v3_and_comes_from_the_rewritten_markdown() -> void:
	var raw := _load_raw_catalog()
	assert_eq(int(raw.get("schema_version", -1)), EXPECTED_SCHEMA_VERSION)
	assert_eq(String(raw.get("source_path", "")), GUIDE_SOURCE_PATH)
	assert_eq(String(raw.get("source_sha256", "")), _sha256_file(GUIDE_SOURCE_PATH))
	var media_source_path := String(raw.get("media_source_path", ""))
	assert_false(media_source_path.is_empty(), "配图清单必须有独立、可校验的源文件")
	assert_true(FileAccess.file_exists(media_source_path), "配图清单不存在：%s" % media_source_path)
	if FileAccess.file_exists(media_source_path):
		assert_eq(String(raw.get("media_source_sha256", "")), _sha256_file(media_source_path))

	var catalog := ManualCatalog.load_generated()
	assert_true(_has_property(catalog, &"schema_version"), "ManualCatalog 必须公开 schema_version")
	assert_true(_has_property(catalog, &"source_path"), "ManualCatalog 必须公开 source_path")
	assert_true(_has_property(catalog, &"load_error"), "ManualCatalog 必须公开 load_error")
	if not _has_property(catalog, &"schema_version") or not _has_property(catalog, &"source_path") or not _has_property(catalog, &"load_error"):
		return
	assert_eq(int(catalog.get(&"schema_version")), EXPECTED_SCHEMA_VERSION)
	assert_eq(String(catalog.get(&"source_path")), GUIDE_SOURCE_PATH)
	assert_eq(String(catalog.get(&"load_error")), "")
	assert_true(catalog.validate().is_empty())


func test_guide_home_keeps_the_three_player_facing_preface_paragraphs_only() -> void:
	var raw := _load_raw_catalog()
	var home := raw.get("home", {}) as Dictionary
	assert_eq(String(home.get("id", "")), "home")
	assert_eq(String(home.get("title", "")), "《楚物志》游戏指南")
	var expected: Array[Dictionary] = [
		{"id": "home.intro.paragraph.01", "text": "荆楚大地，山水相连，技艺相传。"},
		{"id": "home.intro.paragraph.02", "text": "在《楚物志》中，你将扮演一名非遗博主，从湖北的一座城市启程。骰子决定这一回合能走多远，精力决定这条路是否走得动；沿途的非遗、风景、食物与事件，又会悄悄改变下一段旅程。你可以专心收藏，也可以经营积分点、抢先完成成就，或等一个合适的时机打出手里的牌。"},
		{"id": "home.intro.paragraph.03", "text": "旅程结束时，所有人的收藏与成就都会化为分数。即使有人早早离场，冠军也要等最后一次计分之后才能确定。"},
	]
	var actual_paragraphs: Array[Dictionary] = []
	for value: Variant in home.get("sections", []):
		if value is Dictionary and String((value as Dictionary).get("type", "")) == "paragraph":
			actual_paragraphs.append(value as Dictionary)
	assert_eq(actual_paragraphs.size(), expected.size())
	for index: int in range(mini(actual_paragraphs.size(), expected.size())):
		assert_eq(String(actual_paragraphs[index].get("id", "")), String(expected[index].id))
		assert_eq(String(actual_paragraphs[index].get("text", "")), String(expected[index].text))

	var visible_home_copy := "\n".join(_collect_visible_copy(home))
	assert_false("唯一正文源" in visible_home_copy, "源稿元数据引用不得作为玩家正文")
	assert_false("【卷首主图" in visible_home_copy, "卷首配图制作指令不得显示")
	var catalog := ManualCatalog.load_generated()
	assert_eq(catalog.home_data, home)


func test_catalog_has_six_quick_topics_and_fifteen_rules_topics_with_stable_ids() -> void:
	var catalog := ManualCatalog.load_generated()
	assert_eq(catalog.get_topics(&"quick").size(), EXPECTED_QUICK_TOPICS)
	assert_eq(catalog.get_topics(&"rules").size(), EXPECTED_RULE_TOPICS)
	assert_eq(catalog.get_topics().size(), EXPECTED_QUICK_TOPICS + EXPECTED_RULE_TOPICS)
	var rule_topics := catalog.get_topics(&"rules")
	assert_eq(rule_topics[0].title, "一、开始一局")
	assert_eq(rule_topics[-1].title, "十五、操作与探索图鉴")

	var topic_ids: Dictionary = {}
	var section_keys: Dictionary = {}
	for topic: ManualTopic in catalog.get_topics():
		assert_false(topic.topic_id.is_empty())
		assert_false(topic_ids.has(topic.topic_id), "主题 ID 必须唯一：%s" % topic.topic_id)
		topic_ids[topic.topic_id] = true
		assert_false(topic.sections.is_empty(), "%s 不得是空章节" % topic.topic_id)
		for section: ManualSection in topic.sections:
			assert_false(section.section_id.is_empty(), "%s 存在缺少稳定 ID 的内容块" % topic.topic_id)
			var key := "%s/%s" % [topic.topic_id, section.section_id]
			assert_false(section_keys.has(key), "章节内内容块 ID 必须唯一：%s" % key)
			section_keys[key] = true

	for forbidden_title: String in ["目录", "结语", "附录：配图制作与审校要求"]:
		assert_false(catalog.get_topics().any(
			func(topic: ManualTopic) -> bool: return topic.title == forbidden_title
		), "%s 不得进入玩家目录" % forbidden_title)


func test_schema_v3_preserves_every_required_markdown_block_type() -> void:
	var raw := _load_raw_catalog()
	var found_types: Dictionary = {}
	var found_h4 := false
	var found_table := false
	for topic_value: Variant in raw.get("topics", []):
		if not topic_value is Dictionary:
			continue
		for section_value: Variant in (topic_value as Dictionary).get("sections", []):
			if not section_value is Dictionary:
				continue
			var section := section_value as Dictionary
			var section_type := String(section.get("type", "")).to_lower()
			found_types[section_type] = true
			if section_type == "heading" and int(section.get("level", 0)) == 4:
				found_h4 = true
			if section_type == "table":
				found_table = true
				assert_false((section.get("table_headers", []) as Array).is_empty(), "表格必须保留表头")
				assert_false((section.get("table_rows", []) as Array).is_empty(), "表格必须保留数据行")
	for required_type: String in REQUIRED_SECTION_TYPES:
		assert_true(found_types.has(required_type), "schema v3 必须保留 Markdown 内容类型：%s" % required_type)
	for found_type: String in found_types:
		assert_true(ALLOWED_SECTION_TYPES.has(found_type), "生成了未知内容类型：%s" % found_type)
	assert_true(found_h4, "四级标题必须作为 level=4 的 heading 保留")
	assert_true(found_table)


func test_editorial_notes_and_media_instructions_never_enter_player_copy() -> void:
	var visible_copy := "\n".join(_collect_player_copy(_load_raw_catalog()))
	for forbidden: String in [
		"【配图",
		"【卷首主图",
		"配图制作与审校要求",
		"本附录供后续指南界面与美术制作使用",
		"暂不接入游戏内指南",
		"正文宽度",
		"像素",
		"tmp/",
	]:
		assert_false(forbidden in visible_copy, "制作说明不得显示给玩家：%s" % forbidden)


func test_rewritten_player_copy_is_preserved_without_detail_duplication() -> void:
	var raw := _load_raw_catalog()
	var visible_copy := "\n".join(_collect_player_copy(raw))
	for expected: String in [
		"作为非遗传承人，探索湖北地图，收集非遗、经营资源、提高分数，最终总分最高者获胜。",
		"非遗牌是《楚物志》的核心资源，也是总分最主要的来源。",
		"精力在移动途中降到0不会立刻出局。",
		"目标分数只是让对局进入结算的条件。",
	]:
		assert_true(expected in visible_copy, "用户重写的关键文案必须原样进入目录：%s" % expected)
	assert_true("**地区：**" in visible_copy, "用户已有的 Markdown 重点标记不得在构建时丢失")

	for topic_value: Variant in raw.get("topics", []):
		if not topic_value is Dictionary:
			continue
		for section_value: Variant in (topic_value as Dictionary).get("sections", []):
			if section_value is Dictionary:
				assert_ne(String((section_value as Dictionary).get("type", "")).to_lower(), "detail")


func test_specific_career_effects_only_appear_in_player_setup_and_professions() -> void:
	var raw := _load_raw_catalog()
	var seen: Dictionary = {}
	var seen_effects: Dictionary = {}
	for topic_value: Variant in raw.get("topics", []):
		if not topic_value is Dictionary:
			continue
		var topic := topic_value as Dictionary
		var topic_id := String(topic.get("id", ""))
		for section_value: Variant in topic.get("sections", []):
			if not section_value is Dictionary:
				continue
			var section := section_value as Dictionary
			var section_id := String(section.get("id", ""))
			var group_id := String(section.get("group_id", ""))
			var section_text := JSON.stringify(section)
			for career_name: String in CAREER_NAMES:
				if career_name not in section_text:
					continue
				seen[career_name] = true
				var allowed := topic_id == "professions" or (topic_id == "goal_resources" and group_id == "player_setup")
				assert_true(allowed, "%s 的具体效果不得散落在 %s/%s" % [career_name, topic_id, section_id])
			for marker: String in CAREER_EFFECT_MARKERS:
				if marker not in section_text:
					continue
				seen_effects[marker] = true
				var allowed := topic_id == "professions" or (topic_id == "goal_resources" and group_id == "player_setup")
				assert_true(allowed, "即使省略职业名，职业效果也不得散落在通用规则中：%s（%s/%s）" % [marker, topic_id, section_id])
	for career_name: String in CAREER_NAMES:
		assert_true(seen.has(career_name), "职业选择或职业章节缺少：%s" % career_name)
	for marker: String in CAREER_EFFECT_MARKERS:
		assert_true(seen_effects.has(marker), "职业章节缺少效果特征：%s" % marker)


func test_groups_and_requirements_only_reference_existing_sections_and_known_discoveries() -> void:
	var raw := _load_raw_catalog()
	for topic_value: Variant in raw.get("topics", []):
		if not topic_value is Dictionary:
			continue
		var topic := topic_value as Dictionary
		var section_ids: Dictionary = {}
		for section_value: Variant in topic.get("sections", []):
			if section_value is Dictionary:
				section_ids[String((section_value as Dictionary).get("id", ""))] = true
				_assert_requirements_are_known((section_value as Dictionary).get("requirements", []), "%s/%s" % [topic.get("id", ""), (section_value as Dictionary).get("id", "")])
		for group_value: Variant in topic.get("groups", []):
			assert_true(group_value is Dictionary)
			if not group_value is Dictionary:
				continue
			var group := group_value as Dictionary
			assert_false(String(group.get("id", "")).is_empty())
			for section_id: Variant in group.get("section_ids", []):
				assert_true(section_ids.has(String(section_id)), "组引用了不存在的内容块：%s/%s" % [topic.get("id", ""), section_id])
			_assert_requirements_are_known(group.get("requirements", []), "%s/%s" % [topic.get("id", ""), group.get("id", "")])


func test_every_media_declaration_has_a_supported_renderable_source() -> void:
	var raw := _load_raw_catalog()
	var media_count := 0
	var containers: Array = (raw.get("topics", []) as Array).duplicate()
	containers.append(raw.get("home", {}))
	for topic_value: Variant in containers:
		if not topic_value is Dictionary:
			continue
		for section_value: Variant in (topic_value as Dictionary).get("sections", []):
			if not section_value is Dictionary:
				continue
			var section := section_value as Dictionary
			if String(section.get("type", "")).to_lower() != "media":
				continue
			for entry_value: Variant in section.get("media_entries", []):
				assert_true(entry_value is Dictionary)
				if not entry_value is Dictionary:
					continue
				var entry := entry_value as Dictionary
				media_count += 1
				assert_false(String(entry.get("id", "")).is_empty())
				_assert_requirements_are_known(entry.get("requirements", []), "媒体 %s" % entry.get("id", ""))
				var provider := String(entry.get("provider", "static")).to_lower()
				assert_true(provider in ["static", "dynamic"], "媒体使用了未知 provider：%s" % provider)
				if provider == "dynamic":
					var dynamic_kind := String(entry.get("dynamic_kind", ""))
					assert_true(SUPPORTED_DYNAMIC_MEDIA_KINDS.has(dynamic_kind), "动态媒体没有运行时渲染器：%s" % dynamic_kind)
					assert_false(String(entry.get("dynamic_id", "")).is_empty(), "动态媒体必须提供稳定 dynamic_id")
					continue
				var paths := entry.get("paths", []) as Array
				assert_false(paths.is_empty(), "静态媒体至少需要一个明确资源路径：%s" % entry.get("id", ""))
				for path_value: Variant in paths:
					var path := String(path_value)
					assert_true(path.begins_with("res://"), "静态媒体必须使用明确的 res:// 文件：%s" % path)
					assert_false(path.begins_with("res://tmp/"), "测试截图不能进入正式指南：%s" % path)
					assert_false("*" in path, "媒体路径不能使用 glob：%s" % path)
					assert_false(FORBIDDEN_STATIC_MEDIA.has(path), "禁止作为规则正文媒体：%s" % path)
					assert_true(ResourceLoader.exists(path), "媒体资源不存在：%s" % path)
	assert_gt(media_count, 0)


func test_catalog_search_indexes_rewritten_copy_and_table_cells_but_not_editorial_notes() -> void:
	var catalog := ManualCatalog.load_generated()
	assert_true(catalog.search("最大合法数量", &"rules").any(
		func(topic: ManualTopic) -> bool: return topic.topic_id == &"digital_rulings"
	))
	assert_true(catalog.search("至少10张", &"rules").any(
		func(topic: ManualTopic) -> bool: return topic.topic_id == &"scoring_victory"
	), "表格单元格必须进入搜索索引")
	assert_true(catalog.search("精力为0时先把回合走完", &"rules").any(
		func(topic: ManualTopic) -> bool: return topic.topic_id == &"game_end"
	))
	assert_true(catalog.search("正文宽度", &"rules").is_empty())
	assert_true(catalog.search("配图制作", &"rules").is_empty())


func test_corrupt_catalog_reports_a_load_error_instead_of_exposing_an_empty_success_state() -> void:
	var file := FileAccess.open(CORRUPT_CATALOG_PATH, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string("{not valid json")
	file.close()
	var catalog := ManualCatalog.load_generated(CORRUPT_CATALOG_PATH)
	assert_push_error("游戏指南目录格式无效")
	assert_false(catalog.load_error.is_empty())
	assert_true(catalog.get_topics().is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CORRUPT_CATALOG_PATH))


func _load_raw_catalog() -> Dictionary:
	var file := FileAccess.open(GENERATED_CATALOG_PATH, FileAccess.READ)
	assert_not_null(file, "必须能读取运行时指南目录")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "运行时指南目录必须是 JSON 对象")
	return parsed as Dictionary if parsed is Dictionary else {}


func _sha256_file(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _collect_player_copy(raw: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	_collect_visible_strings(raw.get("topics", []), &"topics", output)
	return output


func _collect_visible_copy(value: Variant) -> PackedStringArray:
	var output := PackedStringArray()
	_collect_visible_strings(value, &"home", output)
	return output


func _collect_visible_strings(value: Variant, key: StringName, output: PackedStringArray) -> void:
	if value is String:
		if key in [&"title", &"summary", &"text", &"body", &"alt"]:
			output.append(String(value))
		return
	if value is Array:
		for item: Variant in value:
			_collect_visible_strings(item, key, output)
		return
	if not value is Dictionary:
		return
	for child_key: Variant in (value as Dictionary).keys():
		var normalized := StringName(str(child_key))
		if normalized in [&"media_entries", &"paths", &"source_path", &"media_source_path"]:
			continue
		_collect_visible_strings((value as Dictionary)[child_key], normalized, output)


func _assert_requirements_are_known(requirements_value: Variant, context: String) -> void:
	if not requirements_value is Array:
		return
	for requirement_value: Variant in requirements_value:
		assert_true(requirement_value is Dictionary, "%s 的发现条件格式无效" % context)
		if not requirement_value is Dictionary:
			continue
		var requirement := requirement_value as Dictionary
		var kind := StringName(String(requirement.get("kind", "")))
		var entry_id := StringName(String(requirement.get("id", "")))
		assert_true(kind in [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT])
		assert_true(DiscoveryManager.get_known_ids(kind).has(entry_id), "%s 引用了未知发现项 %s:%s" % [context, kind, entry_id])
