extends RefCounted
class_name FoodResolutionResult

var success: bool = false
var effect_applied: bool = false
var message: String = ""
var card: 食物牌 = null

func _init(
	p_success: bool = false,
	p_effect_applied: bool = false,
	p_message: String = "",
	p_card: 食物牌 = null
) -> void:
	success = p_success
	effect_applied = p_effect_applied
	message = p_message
	card = p_card
