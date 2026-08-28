class_name HeritageTaskDefinition
extends Resource

@export var task_id: StringName = &""
@export var display_name: String = ""
@export var heritage_name: String = ""
@export var region: String = ""
@export_multiline var hook: String = ""
@export var instructions: PackedStringArray = PackedStringArray()
@export_multiline var control_hint: String = ""
@export_multiline var cultural_link: String = ""
@export_range(10.0, 60.0, 0.5) var duration_seconds: float = 25.0
@export var task_scene: PackedScene = null
@export var microphone_required: bool = false

@export_group("图鉴与原型素材")
@export var gallery_thumbnail: Texture2D = null
@export_multiline var prototype_asset_note: String = ""
@export_multiline var future_asset_slot: String = ""

@export_group("参考媒体")
@export_file("*.ogv") var reference_video_path: String = ""
@export_file("*.ogg", "*.wav", "*.mp3") var reference_audio_path: String = ""
@export_file("*.json") var reference_analysis_path: String = ""


func is_valid_definition() -> bool:
	return not task_id.is_empty() \
			and not display_name.is_empty() \
			and not heritage_name.is_empty() \
			and gallery_thumbnail != null \
			and task_scene != null \
			and duration_seconds > 0.0


func instantiate_task() -> HeritageTaskBase:
	if task_scene == null:
		return null
	var instance := task_scene.instantiate()
	if instance is HeritageTaskBase:
		return instance as HeritageTaskBase
	if is_instance_valid(instance):
		instance.free()
	return null
