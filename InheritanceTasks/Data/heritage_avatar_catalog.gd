class_name HeritageAvatarCatalog
extends RefCounted

## 外观 ID 沿用职业资源的稳定 ID；不保存 PlayerCharacter 枚举序号。
const DEFAULT_AVATAR_ID: StringName = &"travel_blogger"
const IDS: Array[StringName] = [
	&"travel_blogger", &"life_blogger", &"business_blogger",
	&"food_blogger", &"adventure_blogger", &"magic_blogger",
]
const LABELS: Dictionary[StringName, String] = {
	&"travel_blogger": "旅行博主", &"life_blogger": "生活博主",
	&"business_blogger": "商业博主", &"food_blogger": "美食博主",
	&"adventure_blogger": "探险博主", &"magic_blogger": "魔术博主",
}
const PROFESSION_IDS: Dictionary[int, StringName] = {
	# 与 Cards/职业/*.tres 的 profession_type 对应，由资源契约测试逐项核对。
	# 不在表现数据类加载 Player 脚本，避免工具启动时循环解析 Autoload。
	4: &"travel_blogger", 5: &"life_blogger", 3: &"business_blogger",
	0: &"food_blogger", 2: &"adventure_blogger", 1: &"magic_blogger",
}


static func is_known(avatar_id: StringName) -> bool:
	return IDS.has(avatar_id)


static func normalize(avatar_id: StringName) -> StringName:
	return avatar_id if is_known(avatar_id) else DEFAULT_AVATAR_ID


static func from_player(player: Object) -> StringName:
	if not is_instance_valid(player):
		return DEFAULT_AVATAR_ID
	for property: Dictionary in player.get_property_list():
		if property.name == &"player_types":
			return PROFESSION_IDS.get(int(player.get(&"player_types")), DEFAULT_AVATAR_ID)
	return DEFAULT_AVATAR_ID


static func display_name(avatar_id: StringName) -> String:
	return LABELS[normalize(avatar_id)]
