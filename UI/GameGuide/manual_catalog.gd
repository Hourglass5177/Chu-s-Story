extends RefCounted
class_name ManualCatalog

const GENERATED_CATALOG_PATH := "res://UI/GameGuide/generated/manual_catalog.json"

var source_sha256: String = ""
var _topics_by_id: Dictionary = {}
var _ordered_ids: Array[StringName] = []


static func load_generated(path: String = GENERATED_CATALOG_PATH) -> ManualCatalog:
	var catalog := ManualCatalog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取数字版指南目录：%s" % path)
		return catalog
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("数字版指南目录格式无效：%s" % path)
		return catalog
	catalog.source_sha256 = String(parsed.get("source_sha256", ""))
	for value: Variant in parsed.get("topics", []):
		if not value is Dictionary:
			continue
		var topic := ManualTopic.from_dictionary(value)
		if topic.topic_id.is_empty() or catalog._topics_by_id.has(topic.topic_id):
			continue
		catalog._topics_by_id[topic.topic_id] = topic
		catalog._ordered_ids.append(topic.topic_id)
	return catalog


func get_topic(topic_id: StringName) -> ManualTopic:
	return _topics_by_id.get(topic_id) as ManualTopic


func has_topic(topic_id: StringName) -> bool:
	return _topics_by_id.has(topic_id)


func get_topics(category: StringName = &"") -> Array[ManualTopic]:
	var result: Array[ManualTopic] = []
	for topic_id: StringName in _ordered_ids:
		var topic := get_topic(topic_id)
		if topic != null and (category.is_empty() or topic.category == category):
			result.append(topic)
	return result


func search(query: String, category: StringName = &"") -> Array[ManualTopic]:
	var result: Array[ManualTopic] = []
	for topic: ManualTopic in get_topics(category):
		if topic.matches_query(query):
			result.append(topic)
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for topic_id: StringName in _ordered_ids:
		var topic := get_topic(topic_id)
		if topic == null or topic.title.is_empty():
			errors.append("主题 %s 缺少标题" % topic_id)
			continue
		for related_id: StringName in topic.related_topic_ids:
			if not has_topic(related_id):
				errors.append("主题 %s 关联了不存在的主题 %s" % [topic_id, related_id])
	return errors
