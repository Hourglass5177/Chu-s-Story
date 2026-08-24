extends RefCounted
class_name InteractionTicket

enum State { WAITING, RESOLVED, TIMED_OUT, CANCELLED }

var interaction_id: int = 0
var owner: StringName = &""
var session_generation: int = -1
var turn_epoch: int = -1
var timeout_seconds: float = 0.0
var modal_policy: int = 0
var state: State = State.WAITING
var preview = null
var timeout_resolver: Callable = Callable()
var modal_lease_id: int = -1
var metadata: Dictionary = {}

func _init(
	p_interaction_id: int = 0,
	p_owner: StringName = &"",
	p_session_generation: int = -1,
	p_turn_epoch: int = -1,
	p_timeout_seconds: float = 0.0,
	p_timeout_resolver: Callable = Callable(),
	p_modal_policy: int = 0,
	p_metadata: Dictionary = {}
) -> void:
	interaction_id = p_interaction_id
	owner = p_owner
	session_generation = p_session_generation
	turn_epoch = p_turn_epoch
	timeout_seconds = maxf(p_timeout_seconds, 0.0)
	timeout_resolver = p_timeout_resolver
	modal_policy = p_modal_policy
	metadata = p_metadata.duplicate()

func is_waiting() -> bool:
	return state == State.WAITING
