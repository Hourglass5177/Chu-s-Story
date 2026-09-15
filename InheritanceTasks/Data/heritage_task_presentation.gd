class_name HeritageTaskPresentation
extends Resource

## 每关独立美术配置。所有引用可选，尚未接入的关卡继续使用原表现。
@export_range(1, 1000, 1) var version: int = 1
@export var pixel_canvas_size: Vector2i = Vector2i(500, 300)
@export var logical_stage_size: Vector2i = Vector2i(1000, 600)
@export var stage_scene: PackedScene = null
@export var background: Texture2D = null
@export var foreground: Texture2D = null
@export var cover: Texture2D = null
@export var avatar_covers: Dictionary[StringName, Texture2D] = {}
@export var shared_actions: SpriteFrames = null
@export var avatar_appearances: Dictionary[StringName, HeritageAvatarAppearance] = {}
@export var story_panels: Array[Texture2D] = []
@export var story_thumbnails: Array[Texture2D] = []
@export var story_animation: Array[Texture2D] = []
@export var properties: Dictionary = {}
@export_file("*.json") var source_manifest_path: String = ""


func get_appearance(avatar_id: StringName) -> HeritageAvatarAppearance:
	var appearance := avatar_appearances.get(avatar_id) as HeritageAvatarAppearance
	# 缺资产时不偷偷换成另一位博主。
	return appearance if appearance != null and appearance.is_for_avatar(avatar_id) else null

func get_cover(avatar_id: StringName) -> Texture2D:
	return avatar_covers.get(avatar_id, cover) as Texture2D
