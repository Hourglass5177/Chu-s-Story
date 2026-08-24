@tool
extends Resource
class_name ProfessionDefinition

## 职业的只读配置。玩家归属、封锁回合等本局状态由 ProfessionManager 保存，
## 不得写回这个共享 Resource。

@export var profession_id: StringName = &""
@export var profession_type: PlayerClass.PlayerCharacter = PlayerClass.PlayerCharacter.美食博主
@export var profession_name: String = ""
@export var skill_name: String = ""
@export_multiline var description: String = ""
@export var short_description: String = ""

@export_group("规则参数")
@export_range(1, 10, 1) var food_use_limit: int = 1
@export_range(1, 10, 1) var draw_count: int = 1
@export var can_reorder_draws: bool = false
@export var can_move_at_begin: bool = false
@export var can_move_at_end: bool = false
@export_range(0.0, 1.0, 0.05) var market_buy_multiplier: float = 1.0
@export_range(0, 10, 1) var food_shop_refreshes: int = 0
@export_range(0, 5000, 50) var scenery_arrival_money: int = 0
@export_range(0, 3, 1) var scenery_movement_discount: int = 0
@export_range(0, 12, 1) var work_energy_cost: int = 1
@export_range(0, 5000, 50) var starting_money_bonus: int = 0
