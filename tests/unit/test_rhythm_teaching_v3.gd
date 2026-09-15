extends GutTest

const IDS := ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]

func test_lessons_are_bounded_real_mix_excerpts_and_have_independent_actor_tracks() -> void:
	for id: String in IDS:
		var chart := load("res://InheritanceTasks/Charts/%s.tres" % id) as HeritageMusicChart
		assert_eq(chart.validate(), "", id)
		assert_false(chart.choreography.is_empty(), id)
		assert_false(chart.tutorial_steps.is_empty(), id)
		for step: Dictionary in chart.tutorial_steps:
			assert_eq(step.source_mix, chart.audio_path, id)
			assert_eq(int(step.source_out_ms) - int(step.source_in_ms), int(step.duration_ms), id)
			assert_eq(FileAccess.get_sha256(step.audio_path), step.audio_sha256, id)
			var stream := load(step.audio_path) as AudioStream
			assert_almost_eq(stream.get_length(), step.duration_ms / 1000.0, 0.02, id)
			for e: Dictionary in step.events:
				assert_gte(int(e.time_ms), 0, id)
				assert_lt(int(e.end_ms), int(step.duration_ms), id)

func test_actor_tracks_do_not_mutate_score_and_are_frame_rate_independent() -> void:
	var chart := load("res://InheritanceTasks/Charts/laohekou_si_xian.tres") as HeritageMusicChart
	var before := chart.events.duplicate(true)
	var expected := HeritagePerformanceTimeline.actors_at(chart.choreography, 1200)
	for fps: int in [30, 60, 144]:
		for frame: int in fps * 2:
			HeritagePerformanceTimeline.actors_at(chart.choreography, roundi(frame * 1000.0 / fps))
		assert_eq(HeritagePerformanceTimeline.actors_at(chart.choreography, 1200), expected)
	assert_eq(chart.events, before)
	assert_true(expected.has("partner_left"))
	assert_true(expected.has("partner_right"), "Both partners play under the continuous recording")
	assert_true(HeritagePerformanceTimeline.actors_at(chart.choreography, 6000).has("partner_left"))

func test_unscored_partner_motion_is_valid_but_bad_link_or_bounds_are_rejected() -> void:
	var clip := {"id":"partner", "actor":"teacher", "action":"handoff", "start_ms":200, "end_ms":800, "frames":[0,1]}
	assert_eq(HeritageMusicChart.validate_choreography([clip], 1000, {}), "")
	clip.event_id = "missing"
	assert_string_contains(HeritageMusicChart.validate_choreography([clip], 1000, {}), "关联")
	clip.event_id = ""
	clip.end_ms = 1200
	assert_string_contains(HeritageMusicChart.validate_choreography([clip], 1000, {}), "超出")

func test_actor_clip_starts_at_first_pose_and_finishes_without_wrapping() -> void:
	var clips: Array[Dictionary] = [{"id":"step", "actor":"leader", "action":"land", "start_ms":1000, "end_ms":1400, "frames":[2,3]}]
	assert_eq(HeritagePerformanceTimeline.pose_frame(HeritagePerformanceTimeline.actors_at(clips,1000).leader),2)
	assert_eq(HeritagePerformanceTimeline.pose_frame(HeritagePerformanceTimeline.actors_at(clips,1399).leader),3)
	assert_true(HeritagePerformanceTimeline.actors_at(clips,1400).is_empty())

func test_malformed_teaching_event_is_rejected_before_playback() -> void:
	var chart := (load("res://InheritanceTasks/Charts/laohekou_si_xian.tres") as HeritageMusicChart).duplicate(true) as HeritageMusicChart
	var steps := chart.tutorial_steps.duplicate(true)
	steps[0].events[0].kind = "unknown"
	chart.tutorial_steps = steps
	assert_string_contains(chart.validate(), "教学动作")
	steps[0].events[0].kind = "tap"
	steps[0].events.append(steps[0].events[0].duplicate())
	chart.tutorial_steps = steps
	assert_string_contains(chart.validate(), "编号")
