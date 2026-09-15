class_name HeritageAvatarAppearance
extends Resource

## 只存只读表现资产。换装不能携带判定、碰撞或速度参数。
@export var avatar_id: StringName = &""
@export var costume_id: StringName = &""
@export var portrait: Texture2D = null
@export var sprite_frames: SpriteFrames = null
@export var atlas: Texture2D = null
@export var frame_size: Vector2i = Vector2i(64, 96)
@export var anchors: Dictionary[StringName, Vector2] = {}
@export var scene: PackedScene = null
@export_multiline var reference_note: String = ""


func is_for_avatar(requested_id: StringName) -> bool:
	return HeritageAvatarCatalog.is_known(avatar_id) and avatar_id == requested_id
