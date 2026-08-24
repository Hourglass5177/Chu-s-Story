@tool
extends 卡牌基类
class_name 食物牌

enum FoodType{
	市级,
	省级,
	国家级,
	其他
}
const COSTOFTYPE = {
	FoodType.市级: 150,
	FoodType.省级: 250,
	FoodType.国家级: 500,
	FoodType.其他: 150,
}

## 跨文件名、牌面版本和本局运行时保持稳定的食物标识。
@export var food_id: StringName = &""
@export var food_type: FoodType = FoodType.市级
@export var cost: int = 150
@export_multiline var effect_description: String = "精力 +2"

func get_default_cost() -> int:
	return int(COSTOFTYPE.get(food_type, 150))


## Resource 只提供便捷查询，实际规则和事务统一由 FoodManager 处理。
func can_use(player: PlayerClass) -> bool:
	var manager: Node = Engine.get_main_loop().root.get_node_or_null("FoodManager") if Engine.get_main_loop() is SceneTree else null
	if manager != null and manager.has_method("get_use_check"):
		var check = manager.call("get_use_check", player, self)
		return check != null and bool(check.get("allowed"))
	return false
