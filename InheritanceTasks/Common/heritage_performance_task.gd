class_name HeritagePerformanceTask
extends HeritageStageTask

const TUTORIAL_VERSION: int = 6
const CUES := preload("res://InheritanceTasks/Presentation/heritage_rhythm_cues.gd")
var chart: HeritageMusicChart
var clock: HeritageMusicClock
var judge := HeritageMusicJudge.new()
var lesson_judge := HeritageMusicJudge.new()
var lesson_chart := HeritageMusicChart.new()
var instrument: String = "dance"
var lane: int = -1
var resume_grace_until: int = 0
var playback_stall: float = 0.0
var previous_audio_time: float = 0.0
var calibration: Button
var visual_aid_button: CheckButton
var calibrating: bool = false
var visual_assistance: bool = true
var lesson_plan: Dictionary = {}
var lesson_round: int = 0
var lesson_hint: String = ""
var player_action: StringName = &"idle"
var player_direction: int = 0
var input_offset_ms: int = 0
var feedback_detail: StringName = &"idle"
var _lesson_started: bool = false
var _demo_edges: Dictionary = {}
var _lesson_audio_start: float = 0.0
var _guide_sfx: AudioStreamPlayer
var lesson_steps: Array[Dictionary] = []
var lesson_step: int = 0
var action_serial: int = 0
var action_started_ms: int = 0
var _action_audio: AudioStreamPlayer
var _confirmation_audio: AudioStreamPlayer

func tutorial_version() -> int:
	return 5 if task_id==&"gu_pen_ge" else TUTORIAL_VERSION

func on_task_started() -> void:
	super.on_task_started()
	if run_state == RunState.FINISHED: return
	if phase == Phase.DEMO: _start_lesson_round(true)

func setup_game() -> void:
	chart = context.metadata.get(&"music_chart") as HeritageMusicChart
	if chart == null: chart = load("res://InheritanceTasks/Charts/%s.tres" % task_id) as HeritageMusicChart
	if chart == null or not chart.validate().is_empty():
		complete_technical_error(&"invalid_chart", "乐谱未就绪")
		return
	if not ResourceLoader.exists(chart.audio_path) or (FileAccess.file_exists(chart.audio_path) and FileAccess.get_sha256(chart.audio_path) != chart.audio_sha256):
		complete_technical_error(&"missing_audio", "原声未就绪")
		return
	if clock == null:
		clock = HeritageMusicClock.new()
		add_child(clock)
	clock.stop()
	clock.stream_paused = false
	judge.configure(chart)
	lane = -1
	player_action = &"idle"
	player_direction = 0
	input_offset_ms = HeritageMinigamePreferences.offset_ms(_calibration_device_key())
	resume_grace_until = 0
	_lesson_started = false
	lesson_round = 0
	lesson_step = 0
	duration_seconds = chart.end_ms / 1000.0
	lesson_plan = {"steps": chart.tutorial_steps} if not chart.tutorial_steps.is_empty() else build_lesson_plan()
	lesson_steps.assign(lesson_plan.get("steps", [lesson_plan]))
	lesson_plan = lesson_steps[0]
	lesson_text = str(lesson_plan.get("instruction", "听提示，跟着做一次"))
	lesson_hint = lesson_text
	status_text = performance_idle_hint()
	visual_assistance = bool(context.metadata.get("music_visual_assistance", HeritageMinigamePreferences.visual_assistance_enabled()))
	if _guide_sfx == null:
		_guide_sfx = AudioStreamPlayer.new()
		_guide_sfx.stream = load("res://InheritanceTasks/Audio/rhythm-v4/%s-recorded.wav" % instrument if instrument in ["sing","bow"] else "res://InheritanceTasks/Audio/rhythm-v2/%s.wav" % instrument)
		_guide_sfx.volume_db = -14.0 if instrument in ["sing","bow"] else -10.0
		add_child(_guide_sfx)
	if _action_audio == null:
		_action_audio = AudioStreamPlayer.new()
		_action_audio.stream = _guide_sfx.stream
		_action_audio.max_polyphony = 4
		_action_audio.volume_db = -14.0 if instrument in ["sing","bow"] else -8.0
		add_child(_action_audio)
		_confirmation_audio = AudioStreamPlayer.new()
		_confirmation_audio.stream = load("res://InheritanceTasks/Audio/rhythm-v2/confirm.wav")
		_confirmation_audio.max_polyphony = 3
		_confirmation_audio.volume_db = -17.0
		add_child(_confirmation_audio)
	if calibration == null:
		calibration = Button.new()
		calibration.text = "节拍校准"
		calibration.position = Vector2(92, 8)
		calibration.pressed.connect(_open_calibration)
		add_child(calibration)
	if visual_aid_button == null:
		visual_aid_button = CheckButton.new()
		visual_aid_button.text = "节奏提示"
		visual_aid_button.position = Vector2(390, 8)
		visual_aid_button.toggled.connect(func(enabled: bool) -> void:
			visual_assistance = enabled
			if not context.test_mode: HeritageMinigamePreferences.save_visual_assistance(enabled)
			grab_focus())
		add_child(visual_aid_button)
	visual_aid_button.set_pressed_no_signal(visual_assistance)
	calibration.disabled = false
	if bool(context.metadata.get("host_controls", false)):
		calibration.hide()
		visual_aid_button.hide()

func build_lesson_plan() -> Dictionary:
	return {"instruction": "听提示，跟着做一次", "duration_ms": 5000, "events": []}

func lesson_event(id: String, at_ms: int, kind: String, direction: int, end_ms: int = -1) -> Dictionary:
	return {"id": "%s-lesson-v4-%s" % [task_id, id], "time_ms": at_ms, "kind": kind, "direction": direction,
		"end_ms": at_ms if end_ms < 0 else end_ms, "cue_ms": 900, "rest_policy": "keep_position" if instrument == "switch" else "release_required"}

func lesson_step_plan(instruction: String, duration_ms: int, events: Array[Dictionary], required: String = "hit") -> Dictionary:
	return {"instruction": instruction, "retry_hint": instruction, "duration_ms": duration_ms,
		"events": events, "required": required}

func performance_idle_hint() -> String:
	return "看准备动作，听原声接入"

func action_for_event(kind: String, _direction: int, down: bool) -> StringName:
	if not down: return &"release"
	return &"hold" if kind == "hold" else &"tap"

func _start_lesson_round(demonstration: bool) -> void:
	lesson_plan = lesson_steps[lesson_step]
	lesson_text = str(lesson_plan.instruction)
	lesson_hint = lesson_text
	lesson_chart.events.assign(lesson_plan.get("events", []))
	lesson_chart.presentation.assign(lesson_plan.get("presentation", lesson_chart.events))
	lesson_chart.choreography.assign(lesson_plan.get("choreography", []))
	lesson_chart.sections.assign(lesson_plan.get("sections", []))
	lesson_chart.end_ms = int(lesson_plan.get("duration_ms", 8000))
	lesson_judge.configure(lesson_chart)
	_demo_edges.clear()
	pressed = {-1: false, 0: false, 1: false}
	_clear_profile_input()
	lane = int(lesson_plan.get("initial_lane", -1))
	player_action = &"listen" if demonstration else &"prepare"
	phase = Phase.DEMO if demonstration else Phase.PRACTICE
	phase_time = 0.0
	_lesson_started = true
	_lesson_audio_start = float(lesson_plan.get("audio_start_ms", 0)) / 1000.0
	var audio_path := str(lesson_plan.get("audio_path", chart.tutorial_audio_path if not chart.tutorial_audio_path.is_empty() else chart.audio_path))
	if not ResourceLoader.exists(audio_path):
		complete_technical_error(&"audio_load_failed", "教学原声未就绪")
		return
	if lesson_plan.has("audio_sha256") and FileAccess.get_sha256(audio_path) != str(lesson_plan.audio_sha256):
		complete_technical_error(&"invalid_chart", "教学原声版本不匹配")
		return
	var stream := load(audio_path) as AudioStream
	if stream == null:
		complete_technical_error(&"audio_load_failed", "原声无法播放")
		return
	clock.stream_paused = false
	clock.begin(stream)
	if _lesson_audio_start > 0.0:
		clock.play(_lesson_audio_start)
		clock.last_time = _lesson_audio_start
	playback_stall = 0.0
	previous_audio_time = _lesson_audio_start
	status_text = "看示范" if demonstration else ("轮到你" if lesson_round == 0 else "再试这一小段")
	control_hints_changed.emit()

func begin_game() -> void:
	var stream := load(chart.audio_path) as AudioStream
	if stream == null:
		complete_technical_error(&"audio_load_failed", "原声无法播放")
		return
	clock.stream_paused = false
	clock.begin(stream)
	judge.configure(chart)
	lane = -1
	player_action = &"idle"
	playback_stall = 0.0
	previous_audio_time = 0.0
	status_text = performance_idle_hint()
	calibration.disabled = true

func finish_lesson() -> void:
	if not context.test_mode: HeritageMinigamePreferences.complete_tutorial(task_id, tutorial_version())
	stop_media()
	phase = Phase.COUNTDOWN
	phase_time = 0.0
	setup_game()
	set_progress(0.0)
	pressed = {-1: false, 0: false, 1: false}
	_clear_profile_input()

func restart_current_step() -> void:
	if phase not in [Phase.DEMO, Phase.PRACTICE]: return
	stop_media()
	lesson_round = 0
	_start_lesson_round(true)

func skip_tutorial() -> void:
	if phase not in [Phase.DEMO, Phase.PRACTICE]: return
	stop_media()
	setup_game()
	phase = Phase.COUNTDOWN
	phase_time = 0.0
	pressed = {-1: false, 0: false, 1: false}
	_clear_profile_input()
	set_progress(0.0)

func get_instruction_state() -> Dictionary:
	var state := super.get_instruction_state()
	if phase in [Phase.DEMO, Phase.PRACTICE]:
		state.text = lesson_text
		state.step = lesson_step + 1
		state.steps = lesson_steps.size()
		state.demonstration = phase == Phase.DEMO
	return state

func task_tick(delta: float) -> void:
	if calibrating: return
	if resume_countdown > 0.0 or phase == Phase.COUNTDOWN:
		super.task_tick(delta)
		return
	feedback_age = maxf(0.0, feedback_age - delta)
	if phase in [Phase.DEMO, Phase.PRACTICE]:
		if not _lesson_started: _start_lesson_round(phase == Phase.DEMO)
		_tick_lesson(delta)
		return
	game_time = clock.seconds()
	if not _check_playback(delta, game_time): return
	judge.advance(_judgment_ms())
	set_progress(judge.score())
	time_left = maxf(0.0, duration_seconds - game_time)
	if game_time >= duration_seconds:
		on_time_expired()
		return
	if not clock.playing and game_time >= duration_seconds - 0.35: on_time_expired()
	elif game_time > duration_seconds + 0.5: complete_technical_error(&"audio_duration_mismatch", "原声与乐谱时长不一致")

func _check_playback(delta: float, source_seconds: float) -> bool:
	var expected_end := _lesson_audio_start + lesson_chart.end_ms / 1000.0 if phase in [Phase.DEMO, Phase.PRACTICE] else duration_seconds
	if source_seconds <= previous_audio_time + 0.00001: playback_stall += delta
	else: playback_stall = 0.0
	previous_audio_time = source_seconds
	if playback_stall > 2.0 or (not clock.playing and source_seconds < expected_end - 0.35):
		complete_technical_error(&"audio_playback_failed", "原声播放中断")
		return false
	return true

func _tick_lesson(delta: float) -> void:
	var source_seconds: float = clock.seconds()
	if not _check_playback(delta, source_seconds): return
	phase_time = maxf(0.0, source_seconds - _lesson_audio_start)
	var ms: int = roundi(phase_time * 1000.0)
	if phase == Phase.DEMO:
		for event: Dictionary in lesson_chart.events:
			var id: String = str(event.id)
			if ms >= int(event.time_ms) and not _demo_edges.has(id):
				_demo_edges[id] = true
				if event.kind != "rest":
					lesson_judge.press(int(event.time_ms), int(event.direction))
					if instrument == "switch": lane = int(event.direction)
					lesson_judge.select_position(int(event.time_ms), lane)
					player_direction = int(event.direction)
					player_action = action_for_event(str(event.kind), player_direction, true)
					feedback_age = 0.3
					feedback_good = true
					_trigger_action(str(event.kind), int(event.direction), true)
					_guide_sfx.pitch_scale = 1.0
					_guide_sfx.play()
			if event.kind == "hold" and ms >= int(event.end_ms) and not _demo_edges.has(id + "-up"):
				_demo_edges[id + "-up"] = true
				lesson_judge.release(int(event.end_ms), int(event.direction))
				player_action = action_for_event("hold", int(event.direction), false)
				_trigger_action("hold", int(event.direction), false)
				_guide_sfx.play()
			elif event.kind != "rest" and event.kind != "hold" and ms >= int(event.time_ms) + 80 and not _demo_edges.has(id + "-up"):
				_demo_edges[id + "-up"] = true
				lesson_judge.release(int(event.time_ms) + 80, int(event.direction))
	lesson_judge.advance(ms if phase == Phase.DEMO else _judgment_ms())
	# After EOF, playback position resets before the final output buffer drains.
	# Every lesson has >=700 ms of non-scoring tail; accept the same 350 ms EOF
	# margin as formal play, only after every scoring/release window has elapsed.
	if not _lesson_audio_finished(ms): return
	if phase == Phase.DEMO:
		_start_lesson_round(false)
	elif _lesson_goal_met():
		play_feedback(true)
		lesson_step += 1
		lesson_round = 0
		if lesson_step >= lesson_steps.size(): finish_lesson()
		else: _start_lesson_round(true)
	else:
		lesson_round += 1
		lesson_hint = str(lesson_plan.get("retry_hint", lesson_text))
		# Two unsuccessful attempts replay this exact step, not the whole tutorial.
		_start_lesson_round(lesson_round % 2 == 0)

func _lesson_audio_finished(ms: int) -> bool:
	if ms >= lesson_chart.end_ms: return true
	if clock.playing or ms < lesson_chart.end_ms - 350: return false
	for event: Dictionary in lesson_chart.events:
		var settled_at := int(event.end_ms) + (220 if event.kind == "hold" else 180)
		if ms < settled_at: return false
	return true

func _lesson_goal_met() -> bool:
	if lesson_judge.ghosts > 1 or lesson_judge.score() < 0.70: return false
	var required: String = str(lesson_plan.get("required", "hit"))
	var complete_holds := 0
	var hits := 0
	var rests := 0
	for i: int in lesson_judge.events.size():
		var event: Dictionary = lesson_judge.events[i]
		var outcome: Dictionary = lesson_judge.states[i]
		if event.kind == "hold" and outcome.sustain_ok and outcome.release_ok: complete_holds += 1
		elif event.kind == "rest" and float(outcome.score) > 0.0: rests += 1
		if event.kind != "rest" and outcome.started: hits += 1
	if required == "hold": return complete_holds >= 1
	if required == "hold_rest": return complete_holds >= 1 and rests >= 1
	if required == "rest": return rests >= 1 and hits >= 1
	if required == "double": return hits >= 2
	return hits >= 1

func receive_edge(direction: int, down: bool) -> void:
	if not is_input_active() or calibrating or resume_countdown > 0.0: return
	if phase not in [Phase.PRACTICE, Phase.LIVE]: return
	if bool(pressed.get(direction, false)) == down: return
	pressed[direction] = down
	if phase == Phase.PRACTICE: practice_edge(direction, down)
	else: game_edge(direction, down)

func _judgment_ms() -> int:
	return roundi((clock.seconds() - (_lesson_audio_start if phase in [Phase.DEMO, Phase.PRACTICE] else 0.0)) * 1000.0) - input_offset_ms

func practice_edge(direction: int, down: bool) -> void:
	_performance_edge(lesson_judge, direction, down)

func game_edge(direction: int, down: bool) -> void:
	_performance_edge(judge, direction, down)

func _performance_edge(active_judge: HeritageMusicJudge, direction: int, down: bool) -> void:
	if calibrating: return
	input_offset_ms = HeritageMinigamePreferences.offset_ms(_calibration_device_key())
	if instrument in ["pluck", "sing", "drum"] and direction != 0: return
	if instrument in ["dance", "bow", "switch"] and direction == 0: return
	var timestamp: int = _judgment_ms()
	if instrument == "switch":
		if not down: return
		if direction == lane: return
		lane = direction
		active_judge.select_position(timestamp, lane)
	var hit: bool = false
	var kind: String = "tap"
	if down:
		if active_judge.resume_hold(direction, timestamp):
			player_action = action_for_event("hold", direction, true)
			return
		hit = active_judge.press(timestamp, direction)
		for event: Dictionary in active_judge.events:
			if str(event.id) == active_judge.last_hit:
				kind = str(event.kind)
				break
	else:
		# Releases also update the physical held state used by rest rules.
		var has_hold: bool = false
		for i: int in active_judge.events.size():
			if active_judge.events[i].kind == "hold" and int(active_judge.events[i].direction) == direction and active_judge.states[i].started and not active_judge.states[i].released:
				has_hold = true
		if not has_hold:
			active_judge.release(timestamp, direction)
			return
		hit = active_judge.release(timestamp, direction)
		kind = "hold"
	player_direction = direction
	player_action = action_for_event(kind, direction, down)
	_trigger_action(kind, direction, down)
	if is_instance_valid(_action_audio):
		_action_audio.pitch_scale = 1.0
		_action_audio.play()
	play_feedback(hit)
	feedback_detail = &"good" if hit else &"miss"
	status_text = "接上了" if hit else "下一句再接"
	if not hit:
		for event: Dictionary in active_judge.events:
			if event.kind == "rest" and timestamp >= int(event.time_ms) and timestamp <= int(event.end_ms):
				feedback_detail = &"rest"
				status_text = "先听，停手"
				break
			if down and event.kind != "rest" and absi(timestamp - int(event.time_ms)) < 700:
				feedback_detail = &"wrong_side" if direction != int(event.direction) else (&"early" if timestamp < int(event.time_ms) else &"late")
				status_text = "错侧了" if feedback_detail == &"wrong_side" else ("早了" if feedback_detail == &"early" else "晚了")
				break
			if not down and event.kind == "hold" and int(event.direction) == direction and absi(timestamp - int(event.end_ms)) < 1800:
				feedback_detail = &"early_release" if timestamp < int(event.end_ms) else &"late_release"
				status_text = "收早了" if feedback_detail == &"early_release" else "收晚了"
				break

func _trigger_action(kind: String, direction: int, down: bool) -> void:
	action_serial += 1
	action_started_ms = performance_time_ms()
	player_direction = direction
	player_action = action_for_event(kind, direction, down)

func play_feedback(good: bool) -> void:
	feedback_good = good
	feedback_age = 0.45
	if good and instrument not in ["sing","bow"] and is_instance_valid(_confirmation_audio): _confirmation_audio.play()

func pointer_direction(point: Vector2) -> int:
	if instrument in ["dance", "bow", "switch"]: return -1 if point.x < 500 else 1
	return 0

func pause_media(value: bool) -> void:
	if not is_instance_valid(clock): return
	var active_judge: HeritageMusicJudge = lesson_judge if phase in [Phase.DEMO, Phase.PRACTICE] else judge
	if value:
		clock.freeze(true)
		active_judge.pause_holds(_judgment_ms())
	else:
		active_judge.begin_resume(_judgment_ms(), 350)
		resume_grace_until = _judgment_ms() + 350
		clock.freeze(false)
	if is_instance_valid(_guide_sfx): _guide_sfx.stream_paused = value
	if is_instance_valid(_action_audio): _action_audio.stream_paused = value
	if is_instance_valid(_confirmation_audio): _confirmation_audio.stream_paused = value

func stop_media() -> void:
	if is_instance_valid(clock): clock.stop()
	if is_instance_valid(_guide_sfx): _guide_sfx.stop()
	if is_instance_valid(_action_audio): _action_audio.stop()
	if is_instance_valid(_confirmation_audio): _confirmation_audio.stop()

func on_time_expired() -> void:
	judge.advance(chart.end_ms + 250)
	set_progress(judge.score())
	var metrics := {"score": judge.score(), "grades":judge.grade_summary(),"judgments":judge.judgments.values(), "ghost_inputs": judge.ghosts, "chart_version": chart.version, "audio_sha256": chart.audio_sha256, "chart_annotation": chart.annotation_note}
	if judge.score() >= 0.70: complete_success(metrics, "这一段合上了")
	else: complete_failure(&"score_low", "再听一次，跟上准备和收束动作", metrics)

func performance_events() -> Array[Dictionary]:
	return lesson_chart.presentation if phase in [Phase.DEMO, Phase.PRACTICE] else (chart.presentation if chart != null else [])

func performance_sections() -> Array[Dictionary]:
	return lesson_chart.sections if phase in [Phase.DEMO, Phase.PRACTICE] else (chart.sections if chart != null else [])

func performance_time_ms() -> int:
	return roundi((clock.seconds() - _lesson_audio_start) * 1000.0) if phase in [Phase.DEMO, Phase.PRACTICE] and clock != null else roundi(game_time * 1000.0)

func get_performance_visual_state() -> Dictionary:
	var state: Dictionary = {"cue": 0.0, "event_kind": "", "direction": lane, "player_direction": player_direction,
		"player_action": player_action, "active_hold": false, "release_cue": false, "lane": lane,
		"feedback": feedback_detail if feedback_age > 0.0 else &"idle", "feedback_age": feedback_age, "lesson_hint": lesson_hint,
		"demonstration": phase == Phase.DEMO, "lesson": phase in [Phase.DEMO, Phase.PRACTICE],
		"visual_assistance": visual_assistance or phase != Phase.LIVE, "avatar_id": context.avatar_id if context != null else &"travel"}
	var ms: int = performance_time_ms()
	var active_chart := lesson_chart if phase in [Phase.DEMO, Phase.PRACTICE] else chart
	state.actors = HeritagePerformanceTimeline.actors_at(active_chart.choreography, ms) if active_chart != null else {}
	var active_cues: Array[Dictionary] = []
	var previous_cues: Dictionary = {}
	for event: Dictionary in performance_events():
		var start: int = int(event.time_ms)
		var ending: int = int(event.end_ms)
		var lead: int = int(event.cue_ms)
		var direction: int = int(event.direction)
		var previous: Dictionary = previous_cues.get(direction, {})
		var slot: int = 0
		if not previous.is_empty() and start - int(previous.start) < lead + 220:
			slot = 1 - int(previous.slot)
		previous_cues[direction] = {"start": start, "slot": slot}
		if ms < start - lead or ms > ending + 220: continue
		var cue: Dictionary = event.duplicate(true)
		cue.cue_slot = slot
		cue.approach = clampf(float(ms - start + lead) / maxf(1.0, lead), 0.0, 1.0)
		cue.holding = event.kind == "hold" and ms >= start and ms <= ending
		cue.hold_progress = clampf(float(ms - start) / maxf(1.0, ending - start), 0.0, 1.0)
		cue.releasing = event.kind == "hold" and ms >= ending - 500
		cue.release_progress = clampf(float(ms - ending + 500) / 500.0, 0.0, 1.0)
		cue.after_contact = ms >= start
		active_cues.append(cue)
	state.cues = active_cues
	state.song_time_ms = ms
	state.action_serial = action_serial
	state.action_time = maxf(0.0, (ms - action_started_ms) / 1000.0)
	state.partner_turn = false
	state.partner_pose = 0
	if active_chart != null:
		for section: Dictionary in performance_sections():
			if ms < int(section.start_ms) or ms >= int(section.end_ms): continue
			state.section_id = str(section.id)
			state.partner_turn = ms < int(section.get("response_start_ms", section.start_ms))
			state.partner_pose = 2 if ms < int(section.get("listen_end_ms", section.start_ms)) else 3
			state.partner_elapsed = maxf(0.0, (ms - int(section.start_ms)) / 1000.0)
			state.handoff = ms >= int(section.get("listen_end_ms", section.start_ms)) and bool(state.partner_turn)
			break
	# Keep compatibility fields for each independent stage, while all upcoming
	# marks remain available in cues. Prefer the next contact over a past tap.
	for cue: Dictionary in active_cues:
		if bool(cue.after_contact) and cue.kind not in ["hold", "rest"]: continue
		state.cue = float(cue.approach)
		state.direction = int(cue.direction)
		state.event_kind = str(cue.kind)
		state.release_cue = bool(cue.releasing)
		state.event_id = str(cue.id)
		state.hold_progress = float(cue.hold_progress)
		state.hold_start_ms = int(cue.time_ms)
		state.hold_end_ms = int(cue.end_ms)
		break
	var active_judge: HeritageMusicJudge = lesson_judge if phase in [Phase.DEMO, Phase.PRACTICE] else judge
	var marks: Array[Dictionary] = []
	for record: Dictionary in active_judge.feedback_records:
		var latest: Dictionary = active_judge.judgments.get("%s:%s"%[record.id,record.part],record)
		if int(latest.serial) != int(record.serial): continue
		var age := (ms-int(record.time_ms))/1000.0
		if age < 0.0 or age > 0.45: continue
		var mark := record.duplicate()
		mark.age = age
		marks.append(mark)
	state.judgment_marks = marks
	for index: int in active_judge.events.size():
		if active_judge.events[index].kind == "hold" and active_judge.states[index].started and not active_judge.states[index].released and not active_judge.states[index].done:
			# Suspension releases physical inputs but keeps the pictured grip frozen;
			# the grace window can reconnect this same hold without an idle-pose jump.
			state.active_hold = bool(active_judge.states[index].down) or (bool(active_judge.states[index].suspended) and not bool(active_judge.states[index].resume_missed))
			state.hold_direction = int(active_judge.events[index].direction)
			var hold_event: Dictionary = active_judge.events[index]
			state.hold_progress = clampf(float(ms - int(hold_event.time_ms)) / maxf(1.0, int(hold_event.end_ms) - int(hold_event.time_ms)), 0.0, 1.0)
			state.hold_start_ms = int(hold_event.time_ms)
			state.hold_end_ms = int(hold_event.end_ms)
	if feedback_age <= 0.0 and not state.active_hold:
		state.player_action = &"prepare" if float(state.cue) > 0.0 else &"idle"
	state.motion_phase = &"action" if state.active_hold else (&"prepare" if float(state.cue) > 0.0 else &"idle")
	if feedback_age > 0.0:
		state.motion_phase = &"recover" if feedback_age < 0.18 else (&"action" if feedback_good else &"miss")
	return state

func draw_scene() -> void:
	draw_rect(Rect2(0,100,1000,365), Color("dde1c9"))
	draw_rect(Rect2(0,465,1000,135), Color("9a7155"))
	for x: int in [60,920]:
		draw_rect(Rect2(x,80,20,390), RED)
		draw_circle(Vector2(x+10,120), 32, GOLD)
	var visual_state := get_performance_visual_state()
	var cue: float = float(visual_state.cue)
	var direction: int = int(visual_state.direction)
	var current_kind: String = str(visual_state.event_kind)
	var release_cue: bool = bool(visual_state.release_cue)
	var player_pose: float = cue*0.35
	if feedback_age > 0.0: player_pose = 1.0 if feedback_good else -0.65
	match instrument:
		"dance":
			person(Vector2(330,370), TEAL, cue*direction)
			person(Vector2(650,420), RED, player_pose*direction)
			person(Vector2(180,430), TEAL, cue*direction)
			person(Vector2(820,420), TEAL, cue*direction)
			# All silhouettes face into the rehearsal circle in the same orientation.
			draw_circle(Vector2(500,360), 37, GOLD)
			draw_arc(Vector2(500,360), 37, 0, TAU, 24, INK, 4)
			label_at(Vector2(380,510), "传习排练 · 跟鼓落步")
		"pluck":
			for i: int in 3:
				var p := Vector2(260+i*240,410)
				person(p, RED if i==1 else TEAL, player_pose if i==1 else cue)
				if i == 0:
					draw_rect(Rect2(p+Vector2(-70,-22),Vector2(140,24)),GOLD)
					for string: int in 6: draw_line(p+Vector2(-65,-18+string*3),p+Vector2(65,-18+string*3),INK,1)
				else:
					draw_circle(p+Vector2(5,-20),25 if i==1 else 31,GOLD)
					draw_line(p+Vector2(5,-20),p+Vector2(30,-100 if i==1 else -76),INK,9)
					for string: int in (3 if i==1 else 4): draw_line(p+Vector2(string*2,-20),p+Vector2(26+string*2,-100 if i==1 else -76),PAPER,1)
			label_at(Vector2(370,505), "轮到中间的三弦乐师")
		"bow":
			person(Vector2(340,370), TEAL, cue)
			person(Vector2(610,430), RED, player_pose)
			draw_circle(Vector2(610,400), 19, GOLD)
			draw_line(Vector2(610,400),Vector2(602,320),INK,7)
			draw_line(Vector2(550+player_pose*direction*22,392),Vector2(680+player_pose*direction*22,372),INK,4)
			label_at(Vector2(320,510), "琴筒抵腰 · 短短长，句尾收弓")
		"sing":
			person(Vector2(330,365), TEAL, cue)
			person(Vector2(680,365), GOLD, -cue)
			person(Vector2(360,460), RED, player_pose)
			label_at(Vector2(350,520), "接这一声")
		"switch":
			var light_center := Vector2(300 if lane < 0 else 700, 315)
			draw_colored_polygon(PackedVector2Array([Vector2(165,460),light_center+Vector2(-65,0),light_center+Vector2(65,0)]), Color(0.98,0.87,0.56,0.25))
			draw_circle(light_center, 68, Color(0.98,0.87,0.56,0.35))
			person(Vector2(float(visual_state.get("actor_x", 0.3))*1000,365), GOLD, cue)
			person(Vector2(110,510), RED, player_pose)
			draw_rect(Rect2(150,430,42,28), INK)
			draw_line(Vector2(170,455),Vector2(170,530), INK, 7)
			label_at(Vector2(350,520), "演员走台，追光跟上；站定时留住")
	if not bool(visual_state.visual_assistance): return
	if not str(visual_state.get("local_hint", "")).is_empty():
		label_at(Vector2(375,555), str(visual_state.local_hint), 25)
	if current_kind == "rest": label_at(Vector2(420,180), "听，稍候", 26)
	elif release_cue: label_at(Vector2(420,180), "收住", 26)
	elif cue > 0.1:
		draw_arc(Vector2(500,250), 25+cue*20, PI, TAU, 24, GOLD, 5)
		if phase != Phase.LIVE: label_at(Vector2(430,210), "左 / 右" if instrument in ["dance","bow"] else "接上", 26)


func _open_calibration() -> void:
	if not is_input_active() or phase == Phase.LIVE: return
	calibrating = true
	pressed = {-1: false, 0: false, 1: false}
	pause_media(true)
	var panel := HeritageBeatCalibration.new()
	panel.device_key = _calibration_device_key()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.closed.connect(func() -> void:
		panel.queue_free()
		calibrating = false
		input_offset_ms = HeritageMinigamePreferences.offset_ms(_calibration_device_key())
		if phase in [Phase.DEMO, Phase.PRACTICE]:
			clock.stop()
			_lesson_started = false
		resume_countdown = 1.5
		grab_focus())

func _calibration_device_key() -> String:
	var source := str(get_input_device())
	if source == "gamepad" and input_profile != null:
		source += ":" + Input.get_joy_name(input_profile.active_gamepad)
	return source + "|" + AudioServer.output_device
