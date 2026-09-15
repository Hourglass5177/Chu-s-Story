extends GutTest

func _event(id: String, at: int, kind: String = "tap", direction: int = 0, until: int = -1) -> Dictionary:
	return {"id": id, "time_ms": at, "kind": kind, "direction": direction, "end_ms": at if until < 0 else until, "cue_ms": 700}

func _judge(data: Array[Dictionary]) -> HeritageMusicJudge:
	var chart := HeritageMusicChart.new()
	chart.events = data
	var result := HeritageMusicJudge.new()
	result.configure(chart)
	return result

func test_hold_start_sustain_and_release_have_separate_weights() -> void:
	var judge := _judge([_event("long", 1000, "hold", 0, 2000)])
	assert_true(judge.press(1000, 0))
	assert_almost_eq(judge.score(), 0.30, 0.00001)
	judge.advance(2221)
	assert_almost_eq(judge.score(), 0.60, 0.00001, "Holding forever misses the 40% release component")
	assert_lt(judge.score(), 0.70)

func test_rest_contribution_is_capped_even_for_a_malformed_rest_heavy_chart() -> void:
	var events: Array[Dictionary] = [_event("tap", 1000)]
	for i: int in 9:
		events.append(_event("rest-%d" % i, 2000 + i * 1000, "rest", 0, 2500 + i * 1000))
	var idle := _judge(events)
	idle.advance(12000)
	assert_almost_eq(idle.score(), 0.20, 0.00001)
	var active := _judge(events)
	active.press(1000, 0)
	active.advance(12000)
	assert_almost_eq(active.score(), 1.0, 0.00001)

func test_equal_time_candidates_use_stable_id_and_consume_only_one() -> void:
	for reverse: bool in [false, true]:
		var data: Array[Dictionary] = [_event("z", 1000), _event("a", 1000)]
		if reverse: data.reverse()
		var judge := _judge(data)
		assert_true(judge.press(1000, 0))
		assert_eq(judge.last_hit, "a")
		assert_almost_eq(judge.score(), 0.5, 0.00001)

func test_tap_window_is_inclusive_at_both_edges() -> void:
	for at: int in [819, 820, 1180, 1181]:
		var judge := _judge([_event("tap", 1000)])
		assert_eq(judge.press(at, 0), at >= 820 and at <= 1180, str(at))

func test_hold_release_window_is_inclusive_at_both_edges() -> void:
	for at: int in [1779, 1780, 2220, 2221]:
		var judge := _judge([_event("hold", 1000, "hold", 0, 2000)])
		judge.press(1000, 0)
		assert_eq(judge.release(at, 0), at >= 1780 and at <= 2220, str(at))
		if at >= 1780 and at <= 2220:
			assert_almost_eq(judge.score(), 0.92, 0.00001,"Good release earns 80% of the 40% ending component")

func test_excellent_good_miss_boundaries_and_final_event_counts() -> void:
	for offset: int in [-181,-180,-76,-75,0,75,76,180,181]:
		var judge := _judge([_event("tap",1000)])
		judge.press(1000+offset,0)
		judge.advance(1500)
		var expected := 1.0 if absi(offset)<=75 else .8 if absi(offset)<=180 else 0.0
		assert_almost_eq(judge.states[0].score,expected,.00001,str(offset))
		var counts:=judge.grade_summary()
		assert_eq(counts["优"]+counts["良"]+counts["失"],1)
	for offset: int in [-221,-220,-101,-100,0,100,101,220,221]:
		var judge := _judge([_event("hold",1000,"hold",0,2000)])
		judge.press(1100,0)
		judge.release(2000+offset,0)
		var expected := 1.0 if absi(offset)<=100 else .8 if absi(offset)<=220 else 0.0
		var sustain := .3 if offset>=-220 else 0.0
		assert_almost_eq(judge.score(),.24+sustain+.4*expected,.00001,str(offset))
		var counts:=judge.grade_summary()
		assert_eq(counts["优"]+counts["良"]+counts["失"],1,"A hold has one final event count")

func test_missing_events_emit_once_and_late_timestamp_replaces_record() -> void:
	var judge := _judge([_event("tap",1000)])
	for at: int in range(1181,2000): judge.advance(at)
	assert_eq(judge.feedback_records.size(),1)
	assert_eq(judge.judgments["tap:start"].grade,"失")
	assert_true(judge.press(1050,0))
	assert_eq(judge.judgments.size(),1)
	assert_eq(judge.judgments["tap:start"].grade,"优")
	assert_almost_eq(judge.score(),1.0,.00001)

func test_same_press_cannot_score_an_event_twice() -> void:
	var judge := _judge([_event("tap", 1000)])
	assert_true(judge.press(1000, 0))
	assert_false(judge.press(1000, 0))
	assert_eq(judge.ghosts, 1)
	assert_almost_eq(judge.score(), 0.65, 0.00001)

func test_echo_is_ignored_without_consuming_or_penalizing() -> void:
	var judge := _judge([_event("tap", 1000)])
	assert_false(judge.press(1000, 0, true))
	assert_eq(judge.ghosts, 0)
	assert_eq(judge.score(), 0.0)
	assert_true(judge.press(1000, 0))
	assert_almost_eq(judge.score(), 1.0, 0.00001)

func test_rest_rejects_inputs_on_both_inclusive_boundaries() -> void:
	for at: int in [2000, 2500]:
		var judge := _judge([_event("tap", 1000), _event("rest", 2000, "rest", 0, 2500)])
		judge.press(1000, 0)
		judge.advance(2600)
		judge.press(at, 0)
		assert_almost_eq(judge.score(), 0.45, 0.00001, "Late frame delivery cannot preserve a broken rest")

func test_a_rest_violation_does_not_also_consume_a_playable_event() -> void:
	var judge := _judge([_event("rest", 800, "rest", 0, 1200), _event("tap", 1000)])
	assert_false(judge.press(1000, 0))
	assert_eq(judge.last_hit, "")
	assert_eq(judge.ghosts, 1)
	judge.advance(1500)
	assert_eq(judge.score(), 0.0)

func test_closest_event_then_earlier_time_wins_equal_distance() -> void:
	var judge := _judge([_event("later", 1200), _event("earlier", 1000)])
	assert_true(judge.press(1100, 0))
	assert_eq(judge.last_hit, "earlier")
	assert_true(judge.press(1190, 0))
	assert_eq(judge.last_hit, "later")

func test_pause_freezes_time_and_drops_modal_inputs() -> void:
	var judge := _judge([_event("hold", 1000, "hold", 0, 3000)])
	judge.press(1000, 0)
	judge.pause_holds(1500)
	judge.advance(90000)
	assert_false(judge.press(2000, 0))
	assert_false(judge.release(3000, 0))
	assert_eq(judge.now_ms, 1500)
	assert_eq(judge.ghosts, 0)
	assert_almost_eq(judge.score(), 0.3, 0.00001)

func test_pause_resume_has_inclusive_grace_and_no_extra_start_points() -> void:
	for delayed_frame: bool in [false, true]:
		var judge := _judge([_event("hold", 1000, "hold", 0, 3000)])
		judge.press(1000, 0)
		judge.pause_holds(1500)
		judge.begin_resume(1500, 350)
		if delayed_frame: judge.advance(1900)
		assert_true(judge.resume_hold(0, 1850))
		assert_almost_eq(judge.score(), 0.3, 0.00001)
		assert_true(judge.release(3000, 0))
		assert_almost_eq(judge.score(), 1.0, 0.00001)

func test_resume_after_grace_does_not_restore_sustain_or_release_points() -> void:
	var judge := _judge([_event("hold", 1000, "hold", 0, 3000)])
	judge.press(1000, 0)
	judge.pause_holds(1500)
	judge.begin_resume(1500, 350)
	assert_false(judge.resume_hold(0, 1851))
	assert_false(judge.release(3000, 0))
	assert_almost_eq(judge.score(), 0.3, 0.00001)

func test_repeated_resume_and_release_never_duplicate_points() -> void:
	var judge := _judge([_event("hold", 1000, "hold", 0, 3000)])
	judge.press(1000, 0)
	judge.pause_holds(1500)
	judge.begin_resume(1500)
	assert_true(judge.resume_hold(0, 1600))
	assert_false(judge.resume_hold(0, 1601))
	assert_true(judge.release(3000, 0))
	assert_false(judge.release(3000, 0))
	assert_almost_eq(judge.score(), 1.0, 0.00001)

func test_timestamp_replay_is_independent_of_frame_steps_and_delayed_delivery() -> void:
	var expected := _replay([1])
	for steps: Array in [[33], [17], [8], [7], [11, 27, 4, 61, 12], [1200]]:
		var actual := _replay(steps)
		assert_eq(actual, expected, str(steps))

func _replay(steps: Array) -> Dictionary:
	var judge := _judge([
		_event("tap", 1000), _event("long", 2000, "hold", 0, 3000),
		_event("rest", 3300, "rest", 0, 3800), _event("switch", 4200, "switch", 1),
		_event("bow", 4700, "hold", -1, 5700)])
	var inputs: Array = [[1000, 0, true], [2000, 0, true], [3000, 0, false],
		[4200, 1, true], [4700, -1, true], [5480, -1, false], [6100, 0, true]]
	var frame_time: int = 0
	var step: int = 0
	var cursor: int = 0
	var consumed: Array[String] = []
	while frame_time < 7500:
		frame_time += int(steps[step % steps.size()])
		step += 1
		judge.advance(frame_time)
		while cursor < inputs.size() and int(inputs[cursor][0]) <= frame_time:
			var edge: Array = inputs[cursor]
			if edge[2]:
				if judge.press(int(edge[0]), int(edge[1])): consumed.append(judge.last_hit)
			else: judge.release(int(edge[0]), int(edge[1]))
			cursor += 1
	judge.advance(8000)
	return {"score": judge.score(), "ghosts": judge.ghosts, "ids": consumed}

func test_two_misses_remain_recoverable_in_five_current_charts() -> void:
	for id: String in ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi"]:
		var chart := load("res://InheritanceTasks/Charts/%s.tres" % id) as HeritageMusicChart
		var judge := HeritageMusicJudge.new()
		judge.configure(chart)
		var missed: int = 0
		for e: Dictionary in chart.events:
			if e.kind == "rest": continue
			if missed < 2:
				missed += 1
				continue
			judge.press(int(e.time_ms), int(e.direction))
			if e.kind == "hold": judge.release(int(e.end_ms), int(e.direction))
		judge.advance(chart.end_ms + 250)
		assert_gte(judge.score(), 0.70, id)

func test_configure_clears_previous_run_and_leaves_shared_chart_untouched() -> void:
	var chart := HeritageMusicChart.new()
	chart.events = [_event("z", 1000), _event("a", 1000)]
	var judge := HeritageMusicJudge.new()
	judge.configure(chart)
	judge.press(1000, 0)
	judge.press(4000, 0)
	judge.pause_holds(4500)
	judge.configure(chart)
	assert_eq(judge.score(), 0.0)
	assert_eq(judge.last_hit, "")
	assert_eq(judge.ghosts, 0)
	assert_false(judge.paused)
	assert_eq(chart.events[0].id, "z")
