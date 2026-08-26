extends Resource
class_name ManualTopic

@export var topic_id: StringName = &""
@export var category: StringName = &""
@export var title: String = ""
@export_multiline var summary: String = ""
@export var keywords: PackedStringArray = []
@export var related_topic_ids: Array[StringName] = []
@export var sections: Array[ManualSection] = []


static func from_dictionary(data: Dictionary) -> ManualTopic:
	var topic := ManualTopic.new()
	topic.topic_id = StringName(str(data.get("id", "")))
	topic.category = StringName(str(data.get("category", "rules")))
	topic.title = String(data.get("title", ""))
	topic.summary = String(data.get("summary", ""))
	topic.keywords = PackedStringArray(data.get("keywords", []))
	for related_id: Variant in data.get("related", []):
		topic.related_topic_ids.append(StringName(str(related_id)))
	for section_data: Variant in data.get("sections", []):
		if section_data is Dictionary:
			topic.sections.append(ManualSection.from_dictionary(section_data))
	return topic


func matches_query(query: String) -> bool:
	var normalized := query.strip_edges().to_lower()
	if normalized.is_empty():
		return true
	var searchable := "%s\n%s\n%s" % [title, summary, " ".join(keywords)]
	for section: ManualSection in sections:
		searchable += "\n%s\n%s\n%s" % [section.title, section.body, " ".join(section.items)]
	return normalized in searchable.to_lower()
