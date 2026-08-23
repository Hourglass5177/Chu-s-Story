@tool
extends 卡牌基类
class_name 成就牌

enum ConditionKind {
	风景打卡,
	享用食物,
	神农架收藏,
	达到精力,
	触发事件,
}

@export var achievement_id: StringName = &""
@export_range(0, 100, 1) var score_value: int = 0
@export var condition_kind: ConditionKind = ConditionKind.风景打卡
@export_range(1, 100, 1) var threshold: int = 1
@export var replaces_achievement_id: StringName = &""
