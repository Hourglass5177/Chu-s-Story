extends Resource
class_name ManualSection

enum Kind {
	HERO,
	BULLETS,
	FLOW,
	MEDIA,
	TIP,
	DETAIL,
}

@export var section_id: StringName = &""
@export var kind: Kind = Kind.BULLETS
@export var title: String = ""
@export_multiline var body: String = ""
@export var items: PackedStringArray = []
@export_file var media_path: String = ""


static func from_dictionary(data: Dictionary) -> ManualSection:
	var section := ManualSection.new()
	section.section_id = StringName(str(data.get("id", "")))
	section.kind = _kind_from_string(String(data.get("kind", "bullets")))
	section.title = String(data.get("title", ""))
	section.body = String(data.get("body", ""))
	section.items = PackedStringArray(data.get("items", []))
	section.media_path = String(data.get("media", ""))
	return section


static func _kind_from_string(value: String) -> Kind:
	match value.to_lower():
		"hero":
			return Kind.HERO
		"flow":
			return Kind.FLOW
		"media":
			return Kind.MEDIA
		"tip":
			return Kind.TIP
		"detail":
			return Kind.DETAIL
		_:
			return Kind.BULLETS
