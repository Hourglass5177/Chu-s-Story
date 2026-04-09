@tool
extends Resource
class_name 卡牌基类
enum CardType{
	非遗牌,
	事件牌,
	食物牌,
	成就牌,
	任务牌,
	风景卡,
	其他
}
# 导出变量
@export var card_type: CardType = CardType.非遗牌
@export var card_name: String = "未命名卡牌" 

@export var image_of_front : Texture2D = null
@export var image_of_back: Texture2D = null

@export_multiline var description: String = "描述文本"
