extends HeritagePerformanceTask

func _init() -> void:
	instrument = "pluck"

func build_lesson_plan() -> Dictionary:
	return {"steps": [
		lesson_step_plan("圈合上，拨一下", 2800, [lesson_event("single", 1700, "tap", 0)]),
		lesson_step_plan("拨、松开、再拨", 3400, [lesson_event("double-a", 1700, "tap", 0), lesson_event("double-b", 2220, "tap", 0)], "double"),
		lesson_step_plan("伙伴接奏时停手", 5100, [lesson_event("before-rest", 1300, "tap", 0), lesson_event("listen", 1950, "rest", 0, 3000), lesson_event("return", 4100, "tap", 0)], "rest")]}

func performance_idle_hint() -> String:
	return "你是中间的三弦乐师 · 看伙伴收句，再接上"

func action_for_event(kind: String, _direction: int, down: bool) -> StringName:
	return &"pluck" if down and kind != "rest" else &"pluck_recover"

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	state.stage_theme = &"window_ensemble"
	state.player_role = &"sanxian"
	state.ensemble_turn = &"partners" if bool(state.partner_turn) or state.event_kind == "rest" else &"player"
	state.local_hint = "留给伙伴" if state.event_kind == "rest" else "拨弦"
	return state
