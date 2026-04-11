@tool
extends 卡牌基类
class_name 非遗牌
enum CardCategory {
	戏曲表演,
	民间音乐,
	手工技艺,
	神话传说,
	节日庆典,
	武术拳法,
	国家级非遗
}
const CATEGORY_BASE_SCORES = {
	CardCategory.戏曲表演:0, 
	CardCategory.民间音乐:0,
	CardCategory.手工技艺:1,
	CardCategory.神话传说:2,
	CardCategory.节日庆典:3,
	CardCategory.武术拳法:4,
	CardCategory.国家级非遗:5
}
enum REGION{
	鄂州,
	恩施,
	黄冈,
	黄石,
	荆门,
	荆州,
	潜江,
	神农架,
	十堰,
	随州,
	天门,
	武汉,
	仙桃,
	咸宁,
	襄阳,
	孝感,
	宜昌,
	其他,
	未知
}
const TYPE_TO_EFFECT = {
	CardCategory.戏曲表演:"行动阶段，可以消耗此牌，获得 3 点精力。",
	CardCategory.民间音乐:"行动阶段，可以消耗此牌，获得 750 点积分点。",
	CardCategory.手工技艺:"移动阶段，可以消耗此牌，使可移动最大步数翻倍。",
	CardCategory.神话传说:"任意时候可以消耗此牌，无效化对你的食物牌或事件牌的效果。",
	CardCategory.节日庆典:"获得此牌时，立即获得 3 点精力点数和 750 积分点。",
	CardCategory.武术拳法:"拥有此牌时，移动阶段第一次移动时消耗精力点数-1（不重复叠加）。",
	CardCategory.国家级非遗:"国家级非遗，此牌的基础分数为 5 。"
}
# 导出变量
@export var region: REGION = REGION.鄂州 # 地域 [cite: 1]
@export var category: CardCategory = CardCategory.戏曲表演:
	set(value):
		category = value
		# 当类别发生变化时，如果字典里有这个类别，自动更新基础分
		base_score = CATEGORY_BASE_SCORES[category]
		effect_description = TYPE_TO_EFFECT[category]
		emit_changed()
@export var rarity: int = 1 # 稀有度 [cite: 1]
@export var base_score: int = 0

enum EffectType { 
	NONE, 
	DOUBLE_MOVE,       # 移动步数翻倍 (手工技艺) 
	GAIN_MONEY,        # 获得积分 (民间音乐) 
	GAIN_ENERGY,       # 获得精力 (戏曲表演) 
	REDUCE_MOVE_COST   # 移动时精力消耗-1 (武术拳法) 
}

@export var effect_type: EffectType = EffectType.NONE
@export var effect_value: int = 0 # 比如加750积分，这里就填 750
@export var passive: bool = false
@export var destroy_after_use: bool = false
@export var unbreakable:bool = false
@export_multiline var effect_description: String = TYPE_TO_EFFECT[category]

# --- 留给未来实现的接口 ---
# 判定当前时机是否满足使用条件
func can_use(player: PlayerClass) -> bool:
	match category:
		CardCategory.戏曲表演:
			return (TurnManager.now_phase == TurnManager.TurnPhase.ACTION) and player.onTurn and player.alive
		CardCategory.民间音乐:
			return (TurnManager.now_phase == TurnManager.TurnPhase.ACTION) and player.onTurn and player.alive
		CardCategory.手工技艺:
			return (TurnManager.now_phase == TurnManager.TurnPhase.MOVING) and player.onTurn and player.alive
		_:
			return false
