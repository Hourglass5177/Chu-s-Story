@tool
extends 卡牌基类
class_name 事件牌

enum EventCategory {
	积分,
	精力,
	卡牌,
	移动,
	功能,
}

enum ImplementationStatus {
	可用,
	依赖交易所,
	依赖职业技能,
}

@export var event_id: StringName = &""
@export var event_category: EventCategory = EventCategory.积分
@export var retainable: bool = false
@export var implementation_status: ImplementationStatus = ImplementationStatus.可用
@export_multiline var dependency_note: String = ""

func is_available() -> bool:
	return implementation_status == ImplementationStatus.可用
