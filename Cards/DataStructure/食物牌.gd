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

# 食物是否可以在当前状态下使用
func can_use(player: PlayerClass) -> bool:
	# 只要在自己的行动阶段就能吃
	var is_my_turn = (TurnManager.players[TurnManager.now_player_index] == player)
	var is_action_phase = (TurnManager.now_phase == TurnManager.TurnPhase.ACTION)
	
	return is_my_turn and is_action_phase

# 执行吃食物的效果
func execute_effect(player: PlayerClass, id: int = -1):
	if food_type == FoodType.市级:
		if id == 0:
			ResourceManager.modify_energy(player, 2, "吃食物: " + card_name)
		elif id == 1:
			ResourceManager.modify_energy(player, 1, "吃食物: " + card_name)
			ResourceManager.modify_money(player, 100, "吃食物：" + card_name)
	else:
		print(player.player_name, " 吃了【", card_name, "】，回复了 ", 2, " 点精力！")
		ResourceManager.modify_energy(player, 2, "吃食物: " + card_name)
