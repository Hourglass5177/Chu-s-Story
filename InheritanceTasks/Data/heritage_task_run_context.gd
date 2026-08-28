class_name HeritageTaskRunContext
extends RefCounted

const NO_FORCED_OUTCOME: int = -1

var task_id: StringName = &""
var player: Object = null
var card: Resource = null
var session_generation: int = 0
var turn_epoch: int = 0
var random_seed: int = 1
var practice_mode: bool = false
var test_mode: bool = false
var forced_outcome: int = NO_FORCED_OUTCOME
var services: Dictionary = {}
var metadata: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(
		p_task_id: StringName = &"",
		p_player: Object = null,
		p_card: Resource = null,
		p_session_generation: int = 0,
		p_turn_epoch: int = 0,
		p_random_seed: int = 1,
		p_practice_mode: bool = false
) -> void:
	task_id = p_task_id
	player = p_player
	card = p_card
	session_generation = p_session_generation
	turn_epoch = p_turn_epoch
	random_seed = p_random_seed
	practice_mode = p_practice_mode
	reset_rng()


func reset_rng() -> void:
	rng.seed = random_seed


func get_service(service_name: StringName) -> Variant:
	return services.get(service_name)


func duplicate_snapshot() -> HeritageTaskRunContext:
	var snapshot := HeritageTaskRunContext.new(
		task_id,
		player,
		card,
		session_generation,
		turn_epoch,
		random_seed,
		practice_mode
	)
	snapshot.test_mode = test_mode
	snapshot.forced_outcome = forced_outcome
	snapshot.services = services.duplicate()
	snapshot.metadata = metadata.duplicate(true)
	return snapshot
