extends RefCounted
class_name FeiyiDetailContent

## Pure presentation data shared by the collected-feiyi popup and the guide.
## Keeping the strings here prevents the two read-only views from drifting.


static func build(card_data: 非遗牌, use_runtime_state: bool = false) -> Dictionary:
	if card_data == null:
		return {}
	var score_value: Variant = card_data.base_score
	if use_runtime_state and Engine.has_singleton("HeritageTaskManager"):
		score_value = HeritageTaskManager.get_display_score(card_data)
	elif use_runtime_state and card_data.category == 非遗牌.CardCategory.国家级非遗:
		var manager: Node = Engine.get_main_loop().root.get_node_or_null("HeritageTaskManager")
		if manager != null and manager.has_method("get_display_score"):
			score_value = manager.call("get_display_score", card_data)
	return {
		"heading": "==  湖北省非物质文化遗产  ==",
		"texture": card_data.image_of_front,
		"name": "【名称】" + card_data.card_name,
		"category": "【类别】" + String(非遗牌.CardCategory.find_key(card_data.category)),
		"score": "【分数】" + str(score_value) + ("" if score_value is String else " 分"),
		"description": "【描述】" + card_data.description,
		"effect": "【效果】" + card_data.effect_description,
	}
