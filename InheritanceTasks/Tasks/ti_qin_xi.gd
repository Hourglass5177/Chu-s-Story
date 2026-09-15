extends HeritagePerformanceTask

func _init() -> void:
	instrument = "bow"

func build_lesson_plan() -> Dictionary:
	return {"steps": [
		lesson_step_plan("跟弓向，左一下、右一下", 3700, [lesson_event("short-left", 1600, "tap", -1), lesson_event("short-right", 2500, "tap", 1)], "double"),
		lesson_step_plan("向左按住，青圈合上时松开", 4200, [lesson_event("long-left", 1600, "hold", -1, 3150)], "hold"),
		lesson_step_plan("向右长弓，收住后停手", 4900, [lesson_event("long-right", 1400, "hold", 1, 2700), lesson_event("bow-rest", 3350, "rest", 0, 4200)], "hold")]}

func performance_idle_hint() -> String:
	return "琴筒抵腰 · 看起弓方向，长弓按住，句尾收住"

func action_for_event(kind: String, direction: int, down: bool) -> StringName:
	if not down: return &"bow_close_left" if direction < 0 else &"bow_close_right"
	if kind == "hold": return &"bow_long_left" if direction < 0 else &"bow_long_right"
	return &"bow_short_left" if direction < 0 else &"bow_short_right"

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	state.stage_theme = &"foreground_tiqin"
	state.instrument_anchor = &"waist"
	state.bow_direction = int(state.get("hold_direction", state.player_direction))
	state.local_hint = "收弓" if state.release_cue else ("停弓听句" if state.event_kind == "rest" else ("长弓按住" if state.event_kind == "hold" else "短弓"))
	state.bowing_is_game_arrangement = true
	return state
