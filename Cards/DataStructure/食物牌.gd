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
# TODO(P2): 目前所有食物均按市级效果处理。待省级、国家级效果实现后，
# 再将价格统一调整为说明书定义的市级 100 / 省级 150 / 国家级 200 积分。

@export var food_type: FoodType = FoodType.市级:
	set(value):
		food_type = value
		cost = COSTOFTYPE[food_type]
		emit_changed()
@export var cost: int = 150
@export_multiline var effect_description: String = "精力 +2"

# 食物是否可以在当前状态下使用
func can_use(player: PlayerClass) -> bool:
	if player == null or not TurnManager.GameOn:
		return false
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size():
		return false
	# 只要在自己的行动阶段就能吃
	var is_my_turn = (TurnManager.players[TurnManager.now_player_index] == player)
	var is_action_phase = (TurnManager.now_phase == TurnManager.TurnPhase.ACTION)
	
	return is_my_turn and is_action_phase and not player.food_used_this_turn

# 执行吃食物的效果
func execute_effect(player: PlayerClass, _option_id: int = -1) -> void:
	if food_type == FoodType.市级:
		ResourceManager.modify_energy(player, 2, "吃食物: " + card_name)
	else:
		print(player.player_name, " 吃了【", card_name, "】，回复了 ", 2, " 点精力！")
		ResourceManager.modify_energy(player, 2, "吃食物: " + card_name)
