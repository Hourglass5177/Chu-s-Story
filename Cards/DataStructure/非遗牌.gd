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
# 导出变量
@export var region: REGION = REGION.鄂州 # 地域 [cite: 1]
@export var category: CardCategory = CardCategory.戏曲表演:
	set(value):
		category = value
		# 当类别发生变化时，如果字典里有这个类别，自动更新基础分
		base_score = CATEGORY_BASE_SCORES[category]
		emit_changed()
@export var rarity: int = 1 # 稀有度 [cite: 1]
@export var base_score: int = 0

# ----- 针对 Demo 的特殊效果标识 -----
# 为了让程序知道这张牌打出时该执行什么逻辑，我们定义几个效果类型
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
