extends RefCounted
class_name FoodUseCheck

var allowed: bool = false
var reason: String = ""

func _init(p_allowed: bool = false, p_reason: String = "") -> void:
	allowed = p_allowed
	reason = p_reason
