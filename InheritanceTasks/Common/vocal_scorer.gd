class_name VocalScorer
extends RefCounted

signal scoring_completed(payload: Dictionary)


func is_available() -> bool:
	return false


func get_unavailable_reason() -> StringName:
	return &"vocal_scorer_unavailable"


func begin_capture(_reference_id: StringName, _duration_seconds: float) -> Error:
	return ERR_UNAVAILABLE


func finish_capture_and_score() -> Error:
	return ERR_UNAVAILABLE


func set_capture_paused(_paused: bool) -> void:
	pass


func cancel_capture() -> void:
	pass
