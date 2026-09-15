extends HeritagePerformanceTask

func _init() -> void:
	instrument = "switch"

func build_lesson_plan() -> Dictionary:
	return {"steps": [
		lesson_step_plan("演员到右台，按右边", 2900, [lesson_event("cross-right", 1750, "switch", 1)]),
		lesson_step_plan("演员站定，灯也留住", 4800, [lesson_event("right-light", 1400, "switch", 1), lesson_event("hold-light", 2100, "rest", 1, 3200), lesson_event("cross-left", 3900, "switch", -1)], "rest")]}

func performance_idle_hint() -> String:
	return "你在观众席后方控制追光 · 跨台时换灯，站定时留住"

func action_for_event(_kind: String, direction: int, _down: bool) -> StringName:
	return &"spotlight_right" if direction > 0 else &"spotlight_left"

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	state.stage_theme = &"auditorium_followspot"
	var ms: int = performance_time_ms()
	var actor_lane: int = int(lesson_plan.get("initial_lane", -1)) if phase in [Phase.DEMO, Phase.PRACTICE] else -1
	var actor_x: float = 0.30 if actor_lane < 0 else 0.70
	var crossing: bool = false
	for event: Dictionary in performance_events():
		if event.kind != "switch": continue
		if ms >= int(event.time_ms):
			actor_lane = int(event.direction)
			actor_x = 0.30 if actor_lane < 0 else 0.70
		elif ms >= int(event.time_ms) - int(event.cue_ms):
			var fraction: float = clampf(float(ms - int(event.time_ms) + int(event.cue_ms)) / maxf(1.0, int(event.cue_ms)), 0.0, 1.0)
			actor_x = lerpf(actor_x, 0.30 if int(event.direction) < 0 else 0.70, fraction)
			crossing = true
			break
	state.actor_lane = actor_lane
	state.actor_x = actor_x
	state.actor_crossing = crossing
	state.light_lane = lane
	state.light_on_actor = absf(actor_x - (0.30 if lane < 0 else 0.70)) < 0.15
	state.local_hint = "跟着跨台换灯" if crossing else "演员站定，把灯留住"
	return state
