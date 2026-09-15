class_name HeritageMusicJudge
extends RefCounted

const START_WINDOW: int = 180
const END_WINDOW: int = 220
const EXCELLENT_START: int = 75
const EXCELLENT_END: int = 100
const HOLD_START_WEIGHT: float = 0.30
const HOLD_SUSTAIN_WEIGHT: float = 0.30
const HOLD_RELEASE_WEIGHT: float = 0.40
const MAX_REST_WEIGHT: float = 0.20
const GHOST_PENALTY: float = 0.35
var events: Array[Dictionary] = []
var states: Array[Dictionary] = []
var ghosts: int = 0
var now_ms: int = 0
var last_hit: String = ""
var paused: bool = false
var _active_count: int = 0
var _rest_count: int = 0
var input_edges: Array[Dictionary] = []
var selections: Array[Dictionary] = []
var ghost_inputs: Array[int] = []
var judgments: Dictionary = {}
var feedback_records: Array[Dictionary] = []
var judgment_serial: int = 0

func configure(chart: HeritageMusicChart) -> void:
	events = chart.events.duplicate(true)
	# Equal-time authoring order must not change which event an input consumes.
	events.sort_custom(_event_before)
	states.clear()
	ghosts = 0
	now_ms = 0
	last_hit = ""
	paused = false
	_active_count = 0
	_rest_count = 0
	input_edges.clear()
	selections.clear()
	ghost_inputs.clear()
	judgments.clear()
	feedback_records.clear()
	judgment_serial = 0
	for e: Dictionary in events:
		if e.kind == "rest": _rest_count += 1
		else: _active_count += 1
		states.append({"started": false, "done": false, "score": 0.0,
			"down": false, "broken": false, "released": false,
			"sustain_ok": false, "release_ok": false, "start_value":0.0, "release_value":0.0,
			"suspended": false, "resume_until": -1, "resume_missed": false})

func advance(timestamp_ms: int) -> void:
	if paused: return
	now_ms = maxi(now_ms, timestamp_ms)
	for i: int in events.size():
		var e: Dictionary = events[i]
		var s: Dictionary = states[i]
		var end: int = int(e.get("end_ms", e.time_ms))
		if e.kind == "rest":
			s.broken = _rest_is_broken(e)
			if now_ms > end:
				s.score = 0.0 if s.broken else 1.0
				s.done = true
		elif not s.started and now_ms > int(e.time_ms) + START_WINDOW:
			if not s.done: _judge_record(i,"start",START_WINDOW+1,0.0,"漏击")
			s.done = true
		elif e.kind == "hold" and s.started and not s.released:
			if s.suspended and int(s.resume_until) >= 0 and now_ms > int(s.resume_until):
				s.broken = true
				s.resume_missed = true
			if now_ms > end + END_WINDOW:
				if not s.done: _judge_record(i,"release",END_WINDOW+1,0.0,"未收尾")
				s.sustain_ok = not s.broken and s.down
				s.done = true
				_update_hold_score(s)

## Input timestamps are captured in musical time. Rendering may already have
## advanced past an edge, so a visual-frame miss does not discard that edge.
## The caller supplies real down edges; optional echo is rejected defensively.
func press(timestamp_ms: int, direction: int, echo: bool = false) -> bool:
	if paused or echo: return false
	_record_edge(timestamp_ms, direction, true)
	advance(timestamp_ms)
	last_hit = ""
	for i: int in events.size():
		var e: Dictionary = events[i]
		if e.kind == "rest" and timestamp_ms >= int(e.time_ms) and timestamp_ms <= int(e.end_ms):
			states[i].broken = true
			states[i].score = 0.0
			ghosts += 1
			ghost_inputs.append(timestamp_ms)
			judgment_serial += 1
			feedback_records.append({"serial":judgment_serial,"id":"ghost_%d"%ghosts,"part":"input","direction":direction,"time_ms":timestamp_ms,"error_ms":0,"grade":"失","value":0.0,"reason":"该停手"})
			return false
	var best: int = -1
	var distance: int = START_WINDOW + 1
	for i: int in events.size():
		var e: Dictionary = events[i]
		if states[i].started or e.kind == "rest": continue
		var d: int = absi(timestamp_ms - int(e.time_ms))
		if int(e.get("direction", 0)) == direction and d <= START_WINDOW and d < distance:
			best = i
			distance = d
	if best < 0:
		ghosts += 1
		ghost_inputs.append(timestamp_ms)
		var reason := "早了"
		for e: Dictionary in events:
			if absi(timestamp_ms-int(e.time_ms)) <= START_WINDOW and int(e.get("direction",0)) != direction: reason = "错侧"; break
			if timestamp_ms > int(e.time_ms): reason = "晚了"
		judgment_serial += 1
		feedback_records.append({"serial":judgment_serial,"id":"ghost_%d"%ghosts,"part":"input","direction":direction,"time_ms":timestamp_ms,"error_ms":0,"grade":"失","value":0.0,"reason":reason})
		return false
	var s: Dictionary = states[best]
	s.started = true
	s.down = true
	s.start_value = grade_value(distance,EXCELLENT_START,START_WINDOW)
	s.score = HOLD_START_WEIGHT * s.start_value if events[best].kind == "hold" else s.start_value
	_judge_record(best,"start",timestamp_ms-int(events[best].time_ms),s.start_value,"")
	s.done = events[best].kind != "hold"
	last_hit = str(events[best].id)
	advance(timestamp_ms)
	return true

func release(timestamp_ms: int, direction: int) -> bool:
	if paused: return false
	_record_edge(timestamp_ms, direction, false)
	advance(timestamp_ms)
	var best: int = -1
	var distance: int = 2147483647
	for i: int in events.size():
		var e: Dictionary = events[i]
		var s: Dictionary = states[i]
		if e.kind != "hold" or not s.started or s.released or int(e.direction) != direction: continue
		var d: int = absi(timestamp_ms - int(e.end_ms))
		if d < distance:
			best = i
			distance = d
	if best < 0: return false
	var s: Dictionary = states[best]
	var ending: int = int(events[best].end_ms)
	s.release_ok = distance <= END_WINDOW and s.down
	s.release_value = grade_value(distance,EXCELLENT_END,END_WINDOW) if s.down else 0.0
	s.sustain_ok = not s.broken and s.down and timestamp_ms >= ending - END_WINDOW
	s.down = false
	s.released = true
	s.done = true
	s.suspended = false
	if not s.release_ok: s.broken = true
	_update_hold_score(s)
	_judge_record(best,"release",timestamp_ms-ending,s.release_value,"" if s.release_ok else "收早了" if timestamp_ms<ending else "收晚了")
	return s.release_ok

## Freeze scoring and drop held physical inputs when a modal pause opens.
## Neither paused wall time nor keys pressed in a modal contribute to scoring.
func pause_holds(timestamp_ms: int) -> void:
	advance(timestamp_ms)
	paused = true
	for direction: int in [-1, 0, 1]: _record_edge(timestamp_ms, direction, false)
	for i: int in events.size():
		var s: Dictionary = states[i]
		if events[i].kind == "hold" and s.started and not s.done:
			s.down = false
			s.suspended = true
			s.resume_until = -1
			s.resume_missed = false

## Call after the visual resume countdown, at the still-frozen musical time.
func begin_resume(timestamp_ms: int, grace_ms: int = 350) -> void:
	paused = false
	for s: Dictionary in states:
		if s.suspended:
			s.resume_until = timestamp_ms + maxi(0, grace_ms)
	advance(timestamp_ms)

func resume_hold(direction: int, timestamp_ms: int) -> bool:
	if paused: return false
	advance(timestamp_ms)
	for i: int in events.size():
		var e: Dictionary = events[i]
		var s: Dictionary = states[i]
		if e.kind == "hold" and int(e.direction) == direction and s.suspended and (not s.broken or s.resume_missed) and not s.released and timestamp_ms <= int(s.resume_until) and timestamp_ms <= int(e.end_ms) + END_WINDOW:
			s.down = true
			_record_edge(timestamp_ms, direction, true)
			s.suspended = false
			s.broken = false
			s.resume_missed = false
			return true
	return false

func score() -> float:
	var active_points: float = 0.0
	var rest_points: float = 0.0
	for i: int in events.size():
		if events[i].kind == "rest": rest_points += float(states[i].score)
		else: active_points += float(states[i].score)
	var rest_weight: float = minf(MAX_REST_WEIGHT, float(_rest_count) / maxf(1.0, events.size()))
	var value: float = active_points / maxf(1.0, _active_count) * (1.0 - rest_weight)
	value += rest_points / maxf(1.0, _rest_count) * rest_weight
	value -= ghosts * GHOST_PENALTY / maxf(1.0, _active_count)
	return clampf(value, 0.0, 1.0)

func _update_hold_score(state: Dictionary) -> void:
	state.score = HOLD_START_WEIGHT * float(state.start_value)
	if state.sustain_ok: state.score += HOLD_SUSTAIN_WEIGHT
	if state.release_ok: state.score += HOLD_RELEASE_WEIGHT * float(state.release_value)

static func grade_value(error_ms: int, excellent: int, window: int) -> float:
	if absi(error_ms) <= excellent: return 1.0
	if absi(error_ms) <= window: return 0.8
	return 0.0

func _judge_record(index: int, part: String, error_ms: int, value: float, reason: String) -> void:
	var e := events[index]
	var key := "%s:%s" % [e.id,part]
	judgment_serial += 1
	var record := {"serial":judgment_serial,"id":str(e.id),"part":part,"direction":int(e.get("direction",0)),
		"time_ms":int(e.get("end_ms",e.time_ms) if part=="release" else e.time_ms)+error_ms,
		"error_ms":error_ms,"grade":"优" if value==1.0 else "良" if value>0 else "失","value":value,"reason":reason}
	judgments[key] = record
	feedback_records.append(record)

func grade_summary() -> Dictionary:
	var result := {"优":0,"良":0,"失":0,"release_errors":0}
	for i: int in events.size():
		if events[i].kind=="rest" or not states[i].done: continue
		var value := float(states[i].score)
		var grade := "优" if is_equal_approx(value,1.0) else "良" if value>=0.8-0.00001 else "失"
		result[grade] += 1
		if events[i].kind=="hold" and not states[i].release_ok: result.release_errors += 1
	return result

func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.time_ms) != int(b.time_ms): return int(a.time_ms) < int(b.time_ms)
	return str(a.id) < str(b.id)

## Spotlight position is a persistent selection, not a held physical button.
func select_position(timestamp_ms: int, direction: int) -> void:
	if paused: return
	selections.append({"time": timestamp_ms, "direction": direction})
	selections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) < int(b.time))

func _record_edge(timestamp_ms: int, direction: int, down: bool) -> void:
	input_edges.append({"time": timestamp_ms, "direction": direction, "down": down})
	# Inputs can be delivered after the render frame crossed a rest boundary.
	# Reconstruct from timestamped edges so frame rate cannot change rest scores.
	input_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) < int(b.time))

func _rest_is_broken(event: Dictionary) -> bool:
	var start: int = int(event.time_ms)
	var finish: int = mini(now_ms, int(event.end_ms))
	if finish < start: return false
	var policy: String = str(event.get("rest_policy", "no_press"))
	if policy == "keep_position":
		var selected: int = -1
		for choice: Dictionary in selections:
			if int(choice.time) > finish: break
			if int(choice.time) <= start: selected = int(choice.direction)
			elif int(choice.direction) != int(event.direction): return true
		return selected != int(event.direction)
	var held: Dictionary = {-1: false, 0: false, 1: false}
	for edge: Dictionary in input_edges:
		var at: int = int(edge.time)
		if at > finish: break
		if at >= start:
			if policy == "release_required" and (held[-1] or held[0] or held[1]): return true
			if bool(edge.down): return true
		held[int(edge.direction)] = bool(edge.down)
	return policy == "release_required" and (held[-1] or held[0] or held[1])
