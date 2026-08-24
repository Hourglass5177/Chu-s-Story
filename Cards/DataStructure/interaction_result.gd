extends RefCounted
class_name InteractionResult

var interaction_id: int = 0
var state: InteractionTicket.State = InteractionTicket.State.CANCELLED
var value = null
var timed_out: bool = false
var cancel_reason: StringName = &""

func _init(
	p_interaction_id: int = 0,
	p_state: InteractionTicket.State = InteractionTicket.State.CANCELLED,
	p_value = null,
	p_timed_out: bool = false,
	p_cancel_reason: StringName = &""
) -> void:
	interaction_id = p_interaction_id
	state = p_state
	value = p_value
	timed_out = p_timed_out
	cancel_reason = p_cancel_reason
