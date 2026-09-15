extends HeritagePerformanceTask

func _init() -> void:
	instrument = "dance"

func build_lesson_plan() -> Dictionary:
	return {"steps": [
		lesson_step_plan("左脚落地，按左边", 2800, [lesson_event("left", 1700, "tap", -1)]),
		lesson_step_plan("右脚落地，按右边", 2800, [lesson_event("right", 1700, "tap", 1)]),
		lesson_step_plan("跟着落步：左、右、右", 4400, [lesson_event("group-left", 1600, "tap", -1), lesson_event("group-right", 2350, "tap", 1), lesson_event("repeat-right", 3100, "tap", 1)], "double"),
		lesson_step_plan("站稳时，两边都松开", 4100, [lesson_event("step-stop", 1400, "tap", -1), lesson_event("still", 2200, "rest", 0, 3300)], "rest")]}

func performance_idle_hint() -> String:
	return "和领舞朝同一方向 · 看屈膝，听鼓落脚"

func action_for_event(_kind: String, direction: int, down: bool) -> StringName:
	if not down: return &"step_recover"
	return &"step_left" if direction < 0 else &"step_right"

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	state.stage_theme = &"village_stone_clearing"
	state.same_facing = true
	state.leader_weight_shift = float(state.cue) * int(state.direction)
	state.local_hint = "稳住" if state.event_kind == "rest" else ("落左脚" if int(state.direction) < 0 else "落右脚")
	return state
