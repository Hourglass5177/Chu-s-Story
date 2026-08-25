extends Resource
class_name PlayerSetup

## 单个本地席位的开局配置草稿。
## -1 代表尚未选择；正式提交前由 SessionSetup.validate() 拦截。

enum ControlKind { HUMAN, BOT }

const UNSELECTED: int = -1

@export_range(0, 5, 1) var slot_index: int = 0
@export var display_name: String = ""
@export var control_kind: ControlKind = ControlKind.HUMAN
@export var profession_type: int = UNSELECTED
@export var starting_region: int = UNSELECTED


func _init(
		p_slot_index: int = 0,
		p_control_kind: ControlKind = ControlKind.HUMAN
) -> void:
	slot_index = p_slot_index
	control_kind = p_control_kind


func is_bot() -> bool:
	return control_kind == ControlKind.BOT


func has_valid_profession() -> bool:
	return PlayerClass.PlayerCharacter.values().has(profession_type)


func has_valid_starting_region() -> bool:
	return MapSection.出生点坐标.has(starting_region)


func is_configured() -> bool:
	return has_valid_profession() and has_valid_starting_region()


func normalized_display_name() -> String:
	var normalized: String = display_name.strip_edges()
	if normalized.is_empty():
		return "P%d" % (slot_index + 1)
	return normalized


func normalize_display_name() -> String:
	display_name = normalized_display_name()
	return display_name


func duplicate_snapshot() -> PlayerSetup:
	var snapshot := PlayerSetup.new(slot_index, control_kind)
	snapshot.display_name = display_name
	snapshot.profession_type = profession_type
	snapshot.starting_region = starting_region
	return snapshot


func is_equivalent_to(other: PlayerSetup) -> bool:
	return other != null \
		and slot_index == other.slot_index \
		and normalized_display_name() == other.normalized_display_name() \
		and control_kind == other.control_kind \
		and profession_type == other.profession_type \
		and starting_region == other.starting_region


func to_legacy_dictionary() -> Dictionary:
	var profession_name: String = ""
	if has_valid_profession():
		profession_name = String(PlayerClass.PlayerCharacter.find_key(profession_type))
	var region_name: String = ""
	if has_valid_starting_region():
		region_name = String(MapSection.REGION.find_key(starting_region))
	return {
		"name": normalized_display_name(),
		"location": region_name,
		"job": profession_name,
		"is_bot": is_bot(),
	}
