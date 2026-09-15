extends HeritagePerformanceTask

## Fixed game-authored practice rhythms. The teacher's demonstration is baked
## into the same audio timeline; this is not an authentic Gupen recording.
enum Stage { SHOW, REPEAT, INTERLUDE }
var _stage: Stage = Stage.SHOW
var _stage_time: float = 0.0
var _round_index: int = 0
var _rounds_passed: int = 0
var _pattern: Array[float] = [0.0, 0.7, 1.4]
var _input_times: Array[float] = []
var _round_scores: Array[float] = []

func _init() -> void:
	instrument = "drum"

func setup_game() -> void:
	super.setup_game()
	_round_index = 0
	_rounds_passed = 0
	_round_scores.clear()
	_input_times.clear()
	_pattern.assign([0.0, 0.7, 1.4])

func build_lesson_plan() -> Dictionary:
	return {"steps": [lesson_step_plan("看示范；圈合上时敲回三下", 4400,
		[lesson_event("echo-1", 1700, "tap", 0), lesson_event("echo-2", 2400, "tap", 0), lesson_event("echo-3", 3100, "tap", 0)], "double")]}

func performance_idle_hint() -> String:
	return "听师傅，接三轮"

func action_for_event(_kind: String, _direction: int, down: bool) -> StringName:
	return &"hold" if down else &"recover"

func task_tick(delta: float) -> void:
	super.task_tick(delta)
	if phase != Phase.LIVE or chart == null: return
	var ms := performance_time_ms()
	while _round_scores.size() < chart.sections.size() and ms >= int(chart.sections[_round_scores.size()].end_ms):
		_score_round(_round_scores.size())
	_round_index = mini(2, ms / 11000)
	var section: Dictionary = chart.sections[_round_index]
	var response_start: int = int(section.response_start_ms)
	_stage = Stage.SHOW if ms < response_start else (Stage.REPEAT if ms < response_start + 3400 else Stage.INTERLUDE)
	_stage_time = (ms - (int(section.start_ms) if _stage == Stage.SHOW else response_start)) / 1000.0
	_pattern.clear()
	for at: int in section.pattern_ms: _pattern.append(at / 1000.0)

func _score_round(index: int) -> void:
	var points := 0.0
	var count := 0
	for i: int in judge.events.size():
		if int(judge.events[i].get("round", 0)) != index: continue
		points += float(judge.states[i].score)
		count += 1
	var start: int = int(chart.sections[index].start_ms)
	var end: int = int(chart.sections[index].end_ms)
	for at: int in judge.ghost_inputs:
		if at >= start and at < end: points -= HeritageMusicJudge.GHOST_PENALTY
	var score := clampf(points / maxf(1, count), 0, 1)
	_round_scores.append(score)
	if score >= .70: _rounds_passed += 1

func on_time_expired() -> void:
	judge.advance(chart.end_ms + 250)
	while _round_scores.size() < chart.sections.size(): _score_round(_round_scores.size())
	var metrics := {"rounds_passed": _rounds_passed, "round_scores": _round_scores.duplicate(),
		"score": judge.score(), "grades":judge.grade_summary(),"judgments":judge.judgments.values(), "ghost_inputs": judge.ghosts, "audio_sha256": chart.audio_sha256,
		"chart_version": chart.version, "chart_annotation": chart.annotation_note}
	if _rounds_passed >= 2: complete_success(metrics, "三轮接好了")
	else: complete_failure(&"rhythm_missed", "听清停顿，再接一次", metrics)

func get_performance_visual_state() -> Dictionary:
	var state := super.get_performance_visual_state()
	var ms := performance_time_ms()
	var teacher_frame := 0
	var showing := phase == Phase.DEMO
	var round_number := 0
	if phase == Phase.LIVE and chart != null:
		round_number = mini(2, ms / 11000)
		var section: Dictionary = chart.sections[round_number]
		showing = ms < int(section.response_start_ms)
		for beat: int in section.teacher_times_ms:
			if ms >= beat - 350 and ms < beat: teacher_frame = 1
			elif ms >= beat and ms < beat + 220: teacher_frame = 2
			elif ms >= beat + 220 and ms < beat + 400: teacher_frame = 3
		state.handoff = ms >= int(section.listen_end_ms) and ms < int(section.response_start_ms)
	elif phase in [Phase.DEMO, Phase.PRACTICE]:
		showing = bool(state.partner_turn)
		var actors: Dictionary = state.get("actors", {})
		teacher_frame = HeritagePerformanceTimeline.pose_frame(actors.get("teacher", {}))
		# The teacher demonstrates in both teaching and practice. During the
		# response, the player is the only striking figure (demo or real input).
	state.showing = showing
	state.teacher_frame = teacher_frame
	state.round = round_number
	state.rounds_passed = _rounds_passed
	state.round_scores = _round_scores.duplicate()
	state.stage_theme = &"gupen_courtyard"
	state.local_hint = "准备接" if state.get("handoff", false) else ("听" if showing else "接")
	return state
