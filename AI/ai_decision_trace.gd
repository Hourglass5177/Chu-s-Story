class_name AIDecisionTrace
extends RefCounted

## Developer-only, value-only snapshots. Never reads a world object or world RNG.
var enabled: bool = false
var records: Array[Dictionary] = []
var dropped: int = 0
const LIMIT: int = 512

static func action_data(action: GameAction) -> Dictionary:
	return {"kind": int(action.kind), "actor": action.actor, "target": action.target, "session": action.session, "epoch": action.epoch, "phase": action.phase, "data": action.data.duplicate(true)}

static func observation_data(observation: AIObservation) -> Dictionary:
	var actions: Array = []
	for action: GameAction in observation.actions: actions.append(action_data(action))
	return {"state": observation.state.duplicate(true), "memory": observation.memory.duplicate(true), "actions": actions}

static func restore_observation(data: Dictionary) -> AIObservation:
	var result := AIObservation.new()
	result.state = data.state.duplicate(true)
	result.memory = data.memory.duplicate(true)
	for item: Dictionary in data.actions:
		var action := GameAction.new(int(item.kind) as GameAction.Kind, int(item.actor), int(item.target), item.data)
		action.session = int(item.session)
		action.epoch = int(item.epoch)
		action.phase = int(item.phase)
		result.actions.append(action)
	return result

static func _collect_ids(value: Variant, ids: Dictionary) -> void:
	if value is Dictionary:
		var string_keys: bool = not value.is_typed_key() or value.get_typed_key_builtin() in [TYPE_STRING, TYPE_STRING_NAME]
		if string_keys and value.has("id") and value.id is int and (value.has("type") or value.has("cost")):
			ids[value.id] = "%s:%s:%s" % [value.get("type", "tile"), value.get("name", ""), value.get("position", "")]
		for child: Variant in value.values(): _collect_ids(child, ids)
	elif value is Array:
		for child: Variant in value: _collect_ids(child, ids)

static func _stable(value: Variant, ids: Dictionary, field: String = "") -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[_stable(key, ids)] = _stable(value[key], ids, str(key))
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_stable(item, ids))
		return result
	if value is int and field in ["id", "target"]: return ids.get(value, value)
	if value is String:
		var parts: PackedStringArray = String(value).split(":")
		if parts.size() in [2, 3] and parts[-1].is_valid_int() and ids.has(int(parts[-1])):
			parts[-1] = str(ids[int(parts[-1])])
			return ":".join(parts)
	return value

func capture(observation: AIObservation, policy: AIPolicy, before_goal: Dictionary, rng_state: int, excluded: Dictionary, action: GameAction, elapsed: int, success: bool) -> void:
	if not enabled: return
	var view := observation_data(observation)
	var descriptions: Dictionary = {}
	_collect_ids(view, descriptions)
	var original_ids: Array = descriptions.keys()
	original_ids.sort_custom(func(a: int, b: int): return String(descriptions[a]) < String(descriptions[b]) if descriptions[a] != descriptions[b] else a < b)
	var stable_ids: Dictionary = {}
	for index: int in original_ids.size(): stable_ids[original_ids[index]] = 1000000 + index
	var candidates: Array = policy.trace_candidates.values()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.value) > float(b.value))
	var record := {"version": policy.profile.version, "difficulty": policy.profile.difficulty, "inheritance_chance": policy.profile.inheritance_chance, "rng_state": str(rng_state), "observation": view, "goal_before": before_goal, "goal_after": policy.goals.snapshot(), "excluded": excluded.duplicate(), "selected": action.key() if action != null else "", "candidates": candidates.slice(0, 8), "nodes": policy.last_nodes, "elapsed_us": elapsed, "success": success}
	record["profile"] = policy.profile.parameters()
	records.append(_stable(record, stable_ids))
	if records.size() > LIMIT:
		records.pop_front()
		dropped += 1

func flush(path: String) -> Error:
	if not enabled or records.is_empty(): return OK
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	# Godot's value text retains Vector3i and integer keys; str_to_var does not enable objects.
	file.store_string(var_to_str({"format": 1, "dropped": dropped, "records": records}))
	records.clear()
	return OK

static func replay(record: Dictionary) -> Dictionary:
	var policy := AIPolicy.new()
	policy.profile = AIProfile.for_difficulty(int(record.difficulty))
	if policy.profile.version != int(record.version): return {"matches": false, "reason": "profile_version_mismatch"}
	policy.profile.inheritance_chance = float(record.inheritance_chance)
	for key: String in policy.profile.parameters():
		if record.get("profile", {}).has(key): policy.profile.set(key, record.profile[key])
	policy.rng.state = int(record.rng_state)
	policy.goals.restore(record.goal_before)
	var action := policy.choose(restore_observation(record.observation), record.excluded)
	var selected := action.key() if action != null else ""
	return {"matches": selected == record.selected, "expected": record.selected, "actual": selected}
