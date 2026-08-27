extends Resource
class_name ManualSection

## Runtime representation of one schema-v3 guide content block.
enum Type {
	HEADING,
	PARAGRAPH,
	BULLETS,
	NUMBERED,
	TABLE,
	QUOTE,
	MEDIA,
	DIVIDER,
}

# Source compatibility while callers migrate from schema v2.
const Kind = Type

@export var section_id: StringName = &""
@export var group_id: StringName = &""
@export var section_type: Type = Type.PARAGRAPH
@export_range(1, 6, 1) var level: int = 3
@export var title: String = ""
@export_multiline var text: String = ""
@export_multiline var body: String = ""
@export var requirements: Array[Dictionary] = []
@export var items: Array[Dictionary] = []
@export var table_headers: PackedStringArray = []
@export var table_alignments: PackedStringArray = []
@export var table_rows: Array[Dictionary] = []
@export var media_entries: Array[Dictionary] = []

# Legacy catalogs bundled title, prose, bullets and an image in one section.
var legacy_flow: bool = false


var kind: Type:
	get:
		return section_type
	set(value):
		section_type = value


static func from_dictionary(data: Dictionary) -> ManualSection:
	var section := ManualSection.new()
	section.section_id = StringName(str(data.get("id", data.get("section_id", ""))))
	section.group_id = StringName(str(data.get("group_id", data.get("group", ""))))
	var raw_type := String(data.get("type", data.get("kind", "paragraph"))).to_lower()
	section.section_type = _type_from_string(raw_type)
	section.legacy_flow = raw_type == "flow"
	section.level = clampi(int(data.get("level", 3)), 1, 6)
	section.title = String(data.get("title", ""))
	section.text = String(data.get("text", data.get("body", "")))
	section.body = section.text
	section.requirements = _dictionary_array(data.get("requirements", []))
	section.items = _normalize_items(data.get("items", []))
	section.table_headers = PackedStringArray(data.get("table_headers", data.get("headers", [])))
	section.table_alignments = PackedStringArray(data.get("table_alignments", data.get("alignments", [])))
	section.table_rows = _normalize_rows(data.get("table_rows", data.get("rows", [])))
	section.media_entries = _normalize_media_entries(data)
	return section


static func _type_from_string(value: String) -> Type:
	match value:
		"heading":
			return Type.HEADING
		"bullets":
			return Type.BULLETS
		"numbered":
			return Type.NUMBERED
		"table":
			return Type.TABLE
		"quote":
			return Type.QUOTE
		"media":
			return Type.MEDIA
		"divider":
			return Type.DIVIDER
		# hero/tip/detail/flow are schema-v2 labels.  They remain visible
		# normal content; no DETAIL accordion is recreated.
		_:
			return Type.PARAGRAPH


static func _normalize_items(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for raw_item: Variant in value:
		if raw_item is Dictionary:
			var item := (raw_item as Dictionary).duplicate(true)
			item["text"] = String(item.get("text", item.get("body", "")))
			item["requirements"] = _dictionary_array(item.get("requirements", []))
			result.append(item)
		else:
			result.append({"text": String(raw_item), "requirements": []})
	return result


static func _normalize_rows(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for raw_row: Variant in value:
		if raw_row is Dictionary:
			var row := (raw_row as Dictionary).duplicate(true)
			row["cells"] = PackedStringArray(row.get("cells", []))
			row["requirements"] = _dictionary_array(row.get("requirements", []))
			result.append(row)
		elif raw_row is Array:
			result.append({"cells": PackedStringArray(raw_row), "requirements": []})
	return result


static func _normalize_media_entries(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_entries: Variant = data.get("media_entries", [])
	if raw_entries is Array:
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary:
				var entry := (raw_entry as Dictionary).duplicate(true)
				entry["requirements"] = _dictionary_array(entry.get("requirements", []))
				result.append(entry)
	if result.is_empty() and (
		data.has("path") or data.has("paths") or data.has("media")
		or data.has("provider") or data.has("dynamic_kind")
	):
		result.append({
			"id": String(data.get("media_id", data.get("id", ""))),
			"provider": String(data.get("provider", "static")),
			"path": String(data.get("path", data.get("media", ""))),
			"paths": data.get("paths", []),
			"layout": String(data.get("layout", "full")),
			"fit": String(data.get("fit", "contain")),
			"min_item_width": float(data.get("min_item_width", 0.0)),
			"target_width_ratio": float(data.get("target_width_ratio", 1.0)),
			"dynamic_kind": String(data.get("dynamic_kind", "")),
			"dynamic_id": String(data.get("dynamic_id", "")),
			"alt": String(data.get("alt", "")),
			"requirements": _dictionary_array(data.get("requirements", [])),
		})
	return result


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Dictionary:
		result.append((value as Dictionary).duplicate(true))
	elif value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result
