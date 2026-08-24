extends RefCounted
class_name ProfessionDrawResult

var selected_card = null
var return_order: Array = []
var cancelled: bool = false


func _init(p_selected_card = null, p_return_order: Array = [], p_cancelled: bool = false) -> void:
	selected_card = p_selected_card
	return_order = p_return_order.duplicate()
	cancelled = p_cancelled
