extends GutTest

## Controlled source timestamps, real Key/Mouse/Joy events via viewport GUI routing.
## This regression is not a real-time device latency check or human listening review.
const ClockFixture = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock
const TASKS := ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]
const AVATARS := [&"travel_blogger", &"life_blogger", &"business_blogger", &"food_blogger", &"adventure_blogger", &"magic_blogger"]
var viewport: SubViewport
var report: Array[Dictionary] = []

func before_all() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://music-input-avatar-regression.cfg")
	HeritageMinigamePreferences.save_offset(0)

func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.gui_disable_input = false
	add_child_autofree(viewport)

func after_all() -> void:
	HeritageMinigamePreferences.configure_storage_path()
	DirAccess.make_dir_recursive_absolute("res://artifacts/music-input-avatar-regression")
	var file := FileAccess.open("res://artifacts/music-input-avatar-regression/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"clock": "controlled source clock", "routing": "SubViewport.push_input", "human_listening_review": false, "runs": report}, "\t"))

func test_identical_key_trace_gives_same_full_result_with_six_current_appearances() -> void:
	for id: String in TASKS:
		var definition := load("res://InheritanceTasks/Definitions/%s.tres" % id) as HeritageTaskDefinition
		assert_not_null(definition.presentation, id)
		assert_not_null(definition.presentation.stage_scene, id)
		var trace := _trace(definition.music_chart.events, id)
		var baseline: Dictionary = {}
		for avatar: StringName in AVATARS:
			var task := definition.instantiate_task() as HeritagePerformanceTask
			viewport.add_child(task)
			task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			task.clock = ClockFixture.new()
			task.add_child(task.clock)
			var context := HeritageTaskRunContext.new(StringName(id))
			context.test_mode = true
			context.avatar_id = avatar
			context.metadata["skip_tutorial"] = true
			context.metadata["host_controls"] = true
			context.metadata["music_chart"] = definition.music_chart
			context.metadata["presentation"] = definition.presentation
			task.configure(context)
			task.start_task()
			task.set_process(false)
			task.set_physics_process(false)
			task.focus_mode = Control.FOCUS_ALL
			task.grab_focus()
			await wait_process_frames(2)
			assert_eq(viewport.gui_get_focus_owner(), task, id + " " + str(avatar))
			assert_eq(task.context.avatar_id, avatar)
			assert_not_null(task.pixel_stage, "Current art is attached: " + id)
			assert_eq(definition.presentation.get_appearance(avatar).avatar_id, avatar)
			var results: Array[HeritageTaskResult] = []
			task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
			for frame: int in 320:
				if task.phase == HeritageStageTask.Phase.LIVE: break
				task._process(0.01)
			for edge: Dictionary in trace:
				_advance_source(task, float(edge.at_ms) / 1000.0)
				_dispatch(task, "keyboard", int(edge.direction), bool(edge.down))
			_advance_source(task, float(definition.music_chart.end_ms + 300) / 1000.0)
			assert_eq(results.size(), 1, id + " " + str(avatar))
			var actual := {"score": task.judge.score(), "ghosts": task.judge.ghosts, "states": task.judge.states.duplicate(true), "lane": task.lane}
			if not results.is_empty():
				actual.status = results[0].status
				assert_true(results[0].is_success(), id + " " + str(avatar))
			if baseline.is_empty(): baseline = actual
			else: assert_eq(actual, baseline, "Appearance must not alter any event outcome: " + id + " " + str(avatar))
			report.append({"task_id": id, "avatar": str(avatar), "phase": "full_chart", "input": "InputEventKey", "score": actual.score, "ghosts": actual.ghosts, "status": actual.get("status", -1), "same_as_first_avatar": actual == baseline, "edge_count": trace.size()})
			task.queue_free()
			await wait_process_frames(1)

func test_all_six_host_lessons_accept_key_mouse_and_joy_without_focus_or_repeat_errors() -> void:
	for id: String in TASKS:
		for device: String in ["keyboard", "mouse", "joypad"]:
			var definition := load("res://InheritanceTasks/Definitions/%s.tres" % id) as HeritageTaskDefinition
			var host := load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate() as HeritageTaskHost
			viewport.add_child(host)
			var context := HeritageTaskRunContext.new(StringName(id))
			context.test_mode = true
			context.avatar_id = &"business_blogger"
			host.configure(definition, context)
			host.begin()
			await wait_process_frames(2)
			assert_ne(viewport.gui_get_focus_owner(), host.active_task, "Preparation has its own focus.")
			var task := host.active_task as HeritagePerformanceTask
			task.clock = ClockFixture.new()
			task.add_child(task.clock)
			host.start_from_preparation(true)
			task.set_process(false)
			task.set_physics_process(false)
			await wait_process_frames(2)
			assert_eq(viewport.gui_get_focus_owner(), task, "Start transfers focus into the real task: " + id + " " + device)
			var edge_count := 0
			for step: int in task.lesson_steps.size():
				for frame: int in 1500:
					if task.phase == HeritageStageTask.Phase.PRACTICE: break
					_frame(task, 0.01)
				assert_eq(task.phase, HeritageStageTask.Phase.PRACTICE, id)
				var trace := _trace(task.lesson_chart.events, id)
				edge_count += trace.size()
				for edge: Dictionary in trace:
					_advance_source(task, float(edge.at_ms) / 1000.0)
					_dispatch(task, device, int(edge.direction), bool(edge.down))
					if bool(edge.down):
						# No new edge: device repeat must neither double-hit nor re-toggle a light.
						var lane_before := task.lane
						var ghosts_before := task.lesson_judge.ghosts
						_dispatch(task, device, int(edge.direction), true, device == "keyboard")
						_dispatch(task, device, int(edge.direction), true)
						assert_eq(task.lane, lane_before, "Repeated down must not change lamp position.")
						assert_eq(task.lesson_judge.ghosts, ghosts_before, "Repeated down must not score as an extra strike.")
					assert_eq(viewport.gui_get_focus_owner(), task, "Gameplay input must not navigate to old controls: " + id + " " + device)
				_advance_source(task, float(task.lesson_chart.end_ms) / 1000.0)
				_frame(task, 0.01)
			assert_eq(task.phase, HeritageStageTask.Phase.COUNTDOWN, id + " " + device)
			assert_eq(task.game_time, 0.0, "Teaching does not consume official challenge time.")
			assert_eq(task.lesson_judge.ghosts, 0, id + " " + device)
			assert_almost_eq(task.lesson_judge.score(), 1.0, 0.000001, "Includes hold start, sustain and release: " + id + " " + device)
			report.append({"task_id": id, "avatar": "business_blogger", "phase": "host_lesson", "input": device, "score": task.lesson_judge.score(), "ghosts": task.lesson_judge.ghosts, "lesson_passed": task.phase == HeritageStageTask.Phase.COUNTDOWN, "focus_owner_is_task": viewport.gui_get_focus_owner() == task, "repeated_down_checked": true, "edge_count": edge_count})
			host.cancel(&"regression_complete")
			host.queue_free()
			await wait_process_frames(1)

func _trace(events: Array[Dictionary], id: String) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.kind == "rest": continue
		var direction := int(event.direction) if id in ["tujia_saye_erhe", "ti_qin_xi", "han_ju"] else 0
		trace.append({"at_ms": int(event.time_ms), "direction": direction, "down": true})
		trace.append({"at_ms": int(event.end_ms) if event.kind == "hold" else int(event.time_ms) + 45, "direction": direction, "down": false})
	trace.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at_ms) < int(b.at_ms))
	return trace

func _frame(task: HeritagePerformanceTask, delta: float) -> void:
	(task.clock as ClockFixture).elapse(delta)
	task._process(delta)

func _advance_source(task: HeritagePerformanceTask, target: float) -> void:
	var limit := 10000
	var segment := [task.phase, task.lesson_step, task.lesson_round]
	while task.clock.seconds() < target - 0.000001 and task.run_state == HeritageTaskBase.RunState.RUNNING and limit > 0:
		limit -= 1
		if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
		_frame(task, minf(1.0 / 120.0, target - task.clock.seconds()))
		# Each excerpt restarts its source clock. Never consume the next demo or
		# practice while trying to reach a timestamp in the previous excerpt.
		if [task.phase, task.lesson_step, task.lesson_round] != segment: break

func _dispatch(task: HeritagePerformanceTask, device: String, direction: int, down: bool, echo: bool = false) -> void:
	var event: InputEvent
	match device:
		"keyboard":
			var key := InputEventKey.new()
			key.keycode = KEY_LEFT if direction < 0 else (KEY_RIGHT if direction > 0 else KEY_SPACE)
			key.physical_keycode = key.keycode
			key.pressed = down
			key.echo = echo
			event = key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_RIGHT if direction > 0 and task.instrument in ["dance", "bow", "switch"] else MOUSE_BUTTON_LEFT
			mouse.pressed = down
			mouse.button_mask = (MOUSE_BUTTON_MASK_RIGHT if mouse.button_index == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT) if down else 0
			var logical := Vector2(250 if direction < 0 else (750 if direction > 0 else 500), 420)
			var factor := minf(task.size.x / 1000.0, task.size.y / 600.0)
			mouse.position = task.get_global_transform() * ((task.size - Vector2(1000, 600) * factor) * 0.5 + logical * factor)
			mouse.global_position = mouse.position
			event = mouse
		"joypad":
			var joy := InputEventJoypadButton.new()
			joy.button_index = JOY_BUTTON_DPAD_LEFT if direction < 0 else (JOY_BUTTON_DPAD_RIGHT if direction > 0 else JOY_BUTTON_A)
			joy.pressed = down
			joy.pressure = 1.0 if down else 0.0
			event = joy
	viewport.push_input(event, true)
