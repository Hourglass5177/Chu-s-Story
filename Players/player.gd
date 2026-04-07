extends AnimatedSprite2D
class_name PlayerClass
signal turn_over_byself
signal roll_dice

enum PlayerCharacter{
	无,
	美食博主,
	魔术博主,
	探险博主,
	商业博主,
	旅行博主,
	生活博主
}
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 玩家的基础属性 [cite: 1]
@export var player_name: String = "Player"
@export var player_types: PlayerCharacter = PlayerCharacter.无

@export var current_energy: int = 6 
@export var max_energy: int = 12
@export var current_score: int = 0
@export var current_money: int = 1000

var player_index: int = 0
var alive: bool = true
var now_pos: Vector3i = Vector3i(0, 0, 0)

# 这是一个数组，专门用来存放 CardData 类型的资源，也就是玩家手里的“非遗卡牌”
var 非遗牌手牌: Array[非遗牌] = [] 
var 食物牌手牌: Array[食物牌] = []

## 测试函数：模拟抽到一张卡
#func draw_card(card: CardData):
	#hand_cards.append(card)
	#print("获得了卡牌：", card.card_name, "，当前积分：", current_score)
#
## 测试函数：打出一张卡牌
#func play_card(card_index: int):
	#if card_index < 0 or card_index >= hand_cards.size():
		#return
		#
	#var card = hand_cards[card_index]
	#
	## 根据我们在 Resource 里配表的数据，执行相应的逻辑
	#match card.effect_type:
		#CardData.EffectType.GAIN_MONEY:
			#current_score += card.effect_value
			#print("使用了", card.card_name, "，增加了", card.effect_value, "积分点！")
		#CardData.EffectType.GAIN_ENERGY:
			#current_energy += card.effect_value
			#print("使用了", card.card_name, "，恢复了", card.effect_value, "点精力！")
		#CardData.EffectType.DOUBLE_MOVE:
			#pass
			#
	## 打出后移出手牌
	#hand_cards.remove_at(card_index)

func _on_turn_manager_turn_start(player_idx: int, sourse: TurnManager) -> void:
	before_turn()
	
	await during_turn(sourse)
	
	after_turn()

func before_turn():
	print("玩家",player_name,"回合开始")

func during_turn(sourse):
	var turntimer = sourse.get_node("TurnTimer")
	await turntimer.timeout or turn_over_byself
	turntimer.stop()

func after_turn():
	print("玩家",player_name,"回合结束")
