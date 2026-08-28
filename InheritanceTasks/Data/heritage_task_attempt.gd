class_name HeritageTaskAttempt
extends RefCounted

enum State {
	PENDING,
	RUNNING,
	FINISHED,
	ROLLED_BACK,
}

var attempt_id: int = 0
var task_id: StringName = &""
var player: Object = null
var card: Resource = null
var session_generation: int = 0
var turn_epoch: int = 0
var interaction_ticket: RefCounted = null
var energy_cost: int = 1
var energy_paid: bool = false
var state: State = State.PENDING


func _init(
		p_attempt_id: int = 0,
		p_task_id: StringName = &"",
		p_player: Object = null,
		p_card: Resource = null,
		p_session_generation: int = 0,
		p_turn_epoch: int = 0
) -> void:
	attempt_id = p_attempt_id
	task_id = p_task_id
	player = p_player
	card = p_card
	session_generation = p_session_generation
	turn_epoch = p_turn_epoch


func mark_running(p_ticket: RefCounted = null) -> bool:
	if state != State.PENDING:
		return false
	interaction_ticket = p_ticket
	state = State.RUNNING
	return true


func mark_finished() -> bool:
	if state != State.RUNNING:
		return false
	state = State.FINISHED
	return true


func mark_rolled_back() -> bool:
	if state == State.FINISHED or state == State.ROLLED_BACK:
		return false
	state = State.ROLLED_BACK
	energy_paid = false
	interaction_ticket = null
	return true
