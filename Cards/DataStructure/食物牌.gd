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
	FoodType.省级: 200,
	FoodType.国家级: 250
}

@export var food_type: FoodType = FoodType.市级:
	set(value):
		food_type = value
		cost = COSTOFTYPE[food_type]
		emit_changed()
@export var cost: int = 150
@export_multiline var effect_description: String = "精力+2 或 精力+1, 积分点+100"
