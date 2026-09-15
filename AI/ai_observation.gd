class_name AIObservation
extends RefCounted

## Only value data crosses into the policy. No Object, Callable or live deck references.
var state: Dictionary = {}
var actions: Array[GameAction] = []
var memory: Dictionary = {}

func copy() -> AIObservation:
	var result := AIObservation.new()
	result.state = state.duplicate(true)
	result.memory = memory.duplicate(true)
	for action: GameAction in actions:
		result.actions.append(action.copy())
	return result
