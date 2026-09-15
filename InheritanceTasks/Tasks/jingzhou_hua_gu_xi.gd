extends HeritagePerformanceTask

func _init() -> void:
	instrument = "sing"

func build_lesson_plan() -> Dictionary:
	return {"steps": [
		lesson_step_plan("轮到你，点一下", 2800, [lesson_event("short-answer", 1700, "tap", 0)]),
		lesson_step_plan("按住；青圈合上时松开", 4100, [lesson_event("long-answer", 1600, "hold", 0, 3000)], "hold"),
		lesson_step_plan("收声后，停手听主唱", 4800, [lesson_event("last-answer", 1300, "hold", 0, 2450), lesson_event("listen-singer", 3100, "rest", 0, 4100)], "hold")]}

func performance_idle_hint() -> String:
	return "看台上收手转身 · 你来接这一声"

func action_for_event(kind: String, _direction: int, down: bool) -> StringName:
	if not down: return &"voice_close"
	return &"voice_sustain" if kind == "hold" else &"voice_short"

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	state.stage_theme = &"flower_wall_stage"
	state.lead_singer_turn = bool(state.partner_turn) or state.event_kind == "rest"
	state.local_hint = "收声" if state.release_cue else ("听主唱" if state.event_kind == "rest" else ("按住这一声" if state.event_kind == "hold" else "接一声"))
	state.participation_is_game_arrangement = true
	return state
