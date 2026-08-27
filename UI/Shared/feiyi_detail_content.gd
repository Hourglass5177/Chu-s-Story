extends RefCounted
class_name FeiyiDetailContent

## Pure presentation data shared by the collected-feiyi popup and the guide.
## Keeping the strings here prevents the two read-only views from drifting.


static func build(card_data: 非遗牌) -> Dictionary:
	if card_data == null:
		return {}
	return {
		"heading": "==  湖北省非物质文化遗产  ==",
		"texture": card_data.image_of_front,
		"name": "【名称】" + card_data.card_name,
		"category": "【类别】" + String(非遗牌.CardCategory.find_key(card_data.category)),
		"score": "【分数】" + str(card_data.base_score) + " 分",
		"description": "【描述】" + card_data.description,
		"effect": "【效果】" + card_data.effect_description,
	}
