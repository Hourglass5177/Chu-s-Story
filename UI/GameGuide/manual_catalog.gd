extends RefCounted
class_name ManualCatalog

const GENERATED_CATALOG_PATH := "res://UI/GameGuide/generated/manual_catalog.json"
const SUPPORTED_SCHEMA_VERSION := 3

var schema_version: int = 0
var source_path: String = ""
var source_sha256: String = ""
var media_source_path: String = ""
var media_source_sha256: String = ""
var load_error: String = ""
var aliases: Dictionary = {}
var home_data: Dictionary = {}
var _topics_by_id: Dictionary = {}
var _ordered_ids: Array[StringName] = []


static func load_generated(path: String = GENERATED_CATALOG_PATH) -> ManualCatalog:
	var catalog := ManualCatalog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		catalog.load_error = "无法读取游戏指南目录"
		push_error("%s：%s" % [catalog.load_error, path])
		return catalog
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		catalog.load_error = "游戏指南目录格式无效"
		push_error("%s：%s（第%d行）" % [catalog.load_error, parser.get_error_message(), parser.get_error_line()])
		return catalog
	catalog.load_dictionary(parser.data as Dictionary)
	return catalog


func load_dictionary(data: Dictionary) -> void:
	_topics_by_id.clear()
	_ordered_ids.clear()
	aliases.clear()
	home_data.clear()
	load_error = ""
	schema_version = int(data.get("schema_version", data.get("version", 2)))
	source_path = String(data.get("source_path", ""))
	source_sha256 = String(data.get("source_sha256", ""))
	media_source_path = String(data.get("media_source_path", ""))
	media_source_sha256 = String(data.get("media_source_sha256", ""))
	var raw_home: Variant = data.get("home", {})
	if raw_home is Dictionary:
		home_data = (raw_home as Dictionary).duplicate(true)
	var raw_aliases: Variant = data.get("aliases", {})
	if raw_aliases is Dictionary:
		for raw_key: Variant in (raw_aliases as Dictionary).keys():
			aliases[StringName(str(raw_key))] = StringName(str((raw_aliases as Dictionary)[raw_key]))
	for value: Variant in data.get("topics", []):
		if not value is Dictionary:
			continue
		var topic := ManualTopic.from_dictionary(value)
		if topic.topic_id.is_empty() or _topics_by_id.has(topic.topic_id):
			continue
		_topics_by_id[topic.topic_id] = topic
		_ordered_ids.append(topic.topic_id)
	if _ordered_ids.is_empty():
		load_error = "游戏指南暂时没有可显示的内容"
	elif schema_version > SUPPORTED_SCHEMA_VERSION:
		load_error = "游戏指南数据版本过新，请更新游戏"


func resolve_topic_id(topic_id: StringName) -> StringName:
	var current := topic_id
	var visited: Dictionary = {}
	while aliases.has(current) and not visited.has(current):
		visited[current] = true
		current = StringName(aliases[current])
	return current


func get_topic(topic_id: StringName) -> ManualTopic:
	return _topics_by_id.get(resolve_topic_id(topic_id)) as ManualTopic


func has_topic(topic_id: StringName) -> bool:
	return _topics_by_id.has(resolve_topic_id(topic_id))


func get_topics(category: StringName = &"") -> Array[ManualTopic]:
	var result: Array[ManualTopic] = []
	for topic_id: StringName in _ordered_ids:
		var topic := get_topic(topic_id)
		if topic != null and (category.is_empty() or topic.category == category):
			result.append(topic)
	return result


func search(query: String, category: StringName = &"", requirements_filter: Callable = Callable()) -> Array[ManualTopic]:
	var result: Array[ManualTopic] = []
	for topic: ManualTopic in get_topics(category):
		if topic.matches_query(query, requirements_filter):
			result.append(topic)
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not load_error.is_empty():
		errors.append(load_error)
	for alias_id: StringName in aliases:
		if not _topics_by_id.has(resolve_topic_id(alias_id)):
			errors.append("指南别名 %s 指向不存在的主题" % alias_id)
	for topic_id: StringName in _ordered_ids:
		var topic := get_topic(topic_id)
		if topic == null or topic.title.is_empty():
			errors.append("主题 %s 缺少标题" % topic_id)
			continue
		if topic.category != &"quick" and topic.category != &"rules":
			errors.append("主题 %s 使用了无效分类 %s" % [topic_id, topic.category])
		var section_ids: Dictionary = {}
		var group_ids: Dictionary = {}
		for group: Dictionary in topic.groups:
			var group_id := StringName(group.get("id", &""))
			if group_id.is_empty() or group_ids.has(group_id):
				errors.append("主题 %s 存在空白或重复小节 ID：%s" % [topic_id, group_id])
			else:
				group_ids[group_id] = true
		for section: ManualSection in topic.sections:
			if section.section_id.is_empty() or section_ids.has(section.section_id):
				errors.append("主题 %s 存在空白或重复内容 ID：%s" % [topic_id, section.section_id])
			else:
				section_ids[section.section_id] = true
		for group: Dictionary in topic.groups:
			for raw_id: Variant in group.get("section_ids", []):
				if not section_ids.has(StringName(str(raw_id))):
					errors.append("主题 %s 的小节 %s 引用了不存在的内容 %s" % [topic_id, group.get("id", ""), raw_id])
		for related_id: StringName in topic.related_topic_ids:
			if not has_topic(related_id):
				errors.append("主题 %s 关联了不存在的主题 %s" % [topic_id, related_id])
	return errors
