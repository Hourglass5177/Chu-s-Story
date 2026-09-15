class_name AIGoalPlanner
extends RefCounted

var current: Dictionary = {}
var recent_positions: Array = []
var last_epoch: int = -1
var distances: Dictionary = {}

func update(observation: AIObservation, policy: AIPolicy) -> void:
	var own: Dictionary = observation.state.self
	var epoch := int(observation.state.get("epoch", 0))
	if epoch != last_epoch:
		last_epoch = epoch
		recent_positions.append(own.position)
		if recent_positions.size() > 6: recent_positions.pop_front()
	if policy.profile.goal_horizon == 0:
		current.clear()
		distances.clear()
		return
	var map: Dictionary = {}
	for tile: Dictionary in observation.state.get("map", []): map[tile.position] = tile
	var costs := policy._distances(map, [own.position])
	var candidates: Array[Dictionary] = []
	for tile: Dictionary in map.values():
		if bool(tile.get("occupied", false)) and tile.position != own.position: continue
		var distance := float(costs.get(tile.position, 10000))
		# Reverse entry-cost paths differ from forward paths by their two endpoint costs.
		if map.has(own.position): distance += float(tile.cost) - float(map[own.position].cost)
		var steps := maxi(absi(tile.position.x - own.position.x), maxi(absi(tile.position.y - own.position.y), absi(tile.position.z - own.position.z)))
		if steps > 7 * policy.profile.goal_horizon: continue
		var kind := ""
		var benefit := 0.0
		match int(tile.type):
			3:
				if int(own.money) >= 400 or int(tile.get("visited", 0)) > 0 or int(own.get("statuses", {}).get("work_banned", 0)) > 0: continue
				kind = "funding"
				benefit = 180.0 if int(own.money) < 150 else 45.0
			1:
				if not bool(tile.supply): continue
				kind = "collect"
				benefit = policy.expected_collection(int(tile.region), observation)
				if policy.region_completion_progress(int(tile.region), own) >= 3: kind = "combination"
			4:
				if int(own.money) < 150: continue
				kind = "supply"
				benefit = maxf(0.0, 7 - int(own.energy)) * 38.0 if own.foods.is_empty() else 10.0
			5:
				if not bool(tile.fresh_scenery): continue
				kind = "supply"
				benefit = mini(3, 12 - int(own.energy)) * 38.0
				var achievement: Dictionary = own.get("achievement_progress", {}).get("you_shan_wan_shui", {})
				if int(achievement.get("state", -1)) == 0:
					kind = "achievement"
					benefit += float(achievement.points) * 100.0 / maxf(1, int(achievement.target) - int(achievement.current))
			6:
				kind = "combination"
				for card: Dictionary in observation.state.market:
					if int(card.price) <= int(own.money): benefit = maxf(benefit, policy.card_value(card, observation) - sqrt(float(card.price)) * 2.0)
		if kind.is_empty() or benefit <= 0: continue
		var utility := minf(300.0, benefit / (1.0 + distance * 0.16)) - distance * 7.0
		if distance >= int(own.energy) and int(tile.type) not in [4, 5]: utility -= 180.0
		var repetitions := recent_positions.count(tile.position)
		if int(tile.type) not in [4, 5] and repetitions >= 2: utility -= (repetitions - 1) * 35.0
		if utility > 0: candidates.append({"key": "%s:%s" % [kind, tile.position], "kind": kind, "position": tile.position, "value": utility})
	for action: GameAction in observation.actions:
		if action.kind != GameAction.Kind.INHERIT: continue
		var gain := policy.inheritance_gain(action.data, observation)
		var kind := "finish" if int(own.score) + gain >= int(observation.state.target_score) else "inherit"
		candidates.append({"key": "%s:%d" % [kind, action.target], "kind": kind, "position": own.position, "value": gain * 100.0 * policy.profile.inheritance_chance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.value) > float(b.value) if not is_equal_approx(float(a.value), float(b.value)) else String(a.key) < String(b.key))
	var previous: Dictionary = {}
	for candidate: Dictionary in candidates:
		if candidate.key == current.get("key", ""): previous = candidate
	var best: Dictionary = candidates[0] if not candidates.is_empty() else {}
	var crisis := int(own.energy) <= 2
	if previous.is_empty() or best.get("kind", "") == "finish" or crisis or float(best.get("value", 0)) > float(previous.value) * 1.2:
		current = best
	else:
		current = previous
	distances = policy._distances(map, [current.position]) if not current.is_empty() else {}

func potential(state: Dictionary) -> float:
	if current.is_empty(): return 0.0
	var distance := float(distances.get(state.position, 10000))
	return maxf(0.0, float(current.value) - distance * 12.0)

func snapshot() -> Dictionary:
	return {"current": current.duplicate(true), "recent_positions": recent_positions.duplicate(), "last_epoch": last_epoch}

func restore(data: Dictionary) -> void:
	current = data.get("current", {}).duplicate(true)
	recent_positions = data.get("recent_positions", []).duplicate()
	last_epoch = int(data.get("last_epoch", -1))
