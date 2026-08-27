extends Resource
class_name ManualTopic

@export var topic_id: StringName = &""
@export var category: StringName = &""
@export var title: String = ""
@export_multiline var summary: String = ""
@export var summary_requirements: Array[Dictionary] = []
@export var keywords: PackedStringArray = []
@export var related_topic_ids: Array[StringName] = []
@export var groups: Array[Dictionary] = []
@export var sections: Array[ManualSection] = []


static func from_dictionary(data: Dictionary) -> ManualTopic:
	var topic := ManualTopic.new()
	topic.topic_id = StringName(str(data.get("id", "")))
	topic.category = StringName(str(data.get("category", "rules")))
	topic.title = String(data.get("title", ""))
	topic.summary = String(data.get("summary", ""))
	topic.summary_requirements = ManualSection._dictionary_array(data.get("summary_requirements", []))
	topic.keywords = PackedStringArray(data.get("keywords", []))
	for related_id: Variant in data.get("related", []):
		topic.related_topic_ids.append(StringName(str(related_id)))
	for raw_group: Variant in data.get("groups", []):
		if raw_group is Dictionary:
			var group := (raw_group as Dictionary).duplicate(true)
			group["id"] = StringName(str(group.get("id", "")))
			group["title"] = String(group.get("title", ""))
			group["requirements"] = ManualSection._dictionary_array(group.get("requirements", []))
			var section_ids: Array[StringName] = []
			for raw_id: Variant in group.get("section_ids", group.get("block_ids", [])):
				section_ids.append(StringName(str(raw_id)))
			group["section_ids"] = section_ids
			topic.groups.append(group)
	for section_data: Variant in data.get("sections", data.get("blocks", [])):
		if section_data is Dictionary:
			topic.sections.append(ManualSection.from_dictionary(section_data))
	topic._ensure_group_structure()
	return topic


func get_group(group_id: StringName) -> Dictionary:
	for group: Dictionary in groups:
		if StringName(group.get("id", &"")) == group_id:
			return group
	return {}


func get_group_id_for_section(section_id: StringName) -> StringName:
	if section_id.is_empty():
		return &""
	for section: ManualSection in sections:
		if section.section_id == section_id:
			return section.group_id
	for group: Dictionary in groups:
		var ids: Array = group.get("section_ids", []) as Array
		if ids.has(section_id):
			return StringName(group.get("id", &""))
	return &""


func get_sections_for_group(group_id: StringName) -> Array[ManualSection]:
	if group_id.is_empty():
		return sections.duplicate()
	var group := get_group(group_id)
	if group.is_empty():
		return []
	var result: Array[ManualSection] = []
	var ordered_ids: Array = group.get("section_ids", []) as Array
	if not ordered_ids.is_empty():
		for raw_id: Variant in ordered_ids:
			var requested_id := StringName(str(raw_id))
			for section: ManualSection in sections:
				if section.section_id == requested_id:
					result.append(section)
					break
		return result
	for section: ManualSection in sections:
		if section.group_id == group_id:
			result.append(section)
	return result


func has_section(section_id: StringName) -> bool:
	for section: ManualSection in sections:
		if section.section_id == section_id:
			return true
	return false


func matches_query(query: String, requirements_filter: Callable = Callable()) -> bool:
	var normalized := query.strip_edges().to_lower()
	if normalized.is_empty():
		return true
	var visible_summary := summary if _requirements_visible(summary_requirements, requirements_filter) else ""
	var searchable := "%s\n%s\n%s" % [title, visible_summary, " ".join(keywords)]
	for group: Dictionary in groups:
		if _requirements_visible(group.get("requirements", []), requirements_filter):
			searchable += "\n%s" % String(group.get("title", ""))
	for section: ManualSection in sections:
		if not _requirements_visible(section.requirements, requirements_filter):
			continue
		searchable += "\n%s\n%s\n%s" % [section.title, section.text, " ".join(section.table_headers)]
		for item: Dictionary in section.items:
			if _requirements_visible(item.get("requirements", []), requirements_filter):
				searchable += "\n%s" % String(item.get("text", ""))
		for row: Dictionary in section.table_rows:
			if _requirements_visible(row.get("requirements", []), requirements_filter):
				searchable += "\n%s" % " ".join(PackedStringArray(row.get("cells", [])))
	return normalized in searchable.to_lower()


func get_visible_summary(requirements_filter: Callable = Callable()) -> String:
	return summary if _requirements_visible(summary_requirements, requirements_filter) else ""


func _ensure_group_structure() -> void:
	if groups.is_empty():
		var default_id := &"content"
		var ids: Array[StringName] = []
		for section: ManualSection in sections:
			section.group_id = default_id
			ids.append(section.section_id)
		groups.append({
			"id": default_id,
			"title": title,
			"requirements": [],
			"section_ids": ids,
		})
		return
	var group_ids: Dictionary = {}
	for group: Dictionary in groups:
		group_ids[StringName(group.get("id", &""))] = true
	for section: ManualSection in sections:
		if section.group_id.is_empty():
			for group: Dictionary in groups:
				var ids: Array = group.get("section_ids", []) as Array
				if ids.has(section.section_id):
					section.group_id = StringName(group.get("id", &""))
					break
		if section.group_id.is_empty() or not group_ids.has(section.group_id):
			section.group_id = StringName(groups[0].get("id", &""))


static func _requirements_visible(requirements: Variant, filter: Callable) -> bool:
	if not filter.is_valid():
		return true
	return bool(filter.call(requirements))
