extends GutTest

const TASK_SCENE := preload("res://InheritanceTasks/Tasks/tianmen_tang_su.tscn")
const CANVAS := preload("res://InheritanceTasks/Presentation/Stages/tianmen_tang_su_pixel.gd")
const DT := 1.0 / 120.0

func test_mixed_outcomes_keep_their_own_shape_and_final_radius() -> void:
	var task := _start()
	var first := _blow(task, 0.35)
	_blow(task, 0.70)
	var last := _blow(task, 0.88)
	assert_eq(task.outcomes, ["偏小", "合适", "过大"])
	assert_eq(task.successes, 1)
	assert_true(last.has("outcomes"), "Presentation needs every result, not only the last result.")
	assert_true(last.has("outcome_radii"), "Each finished sugar bubble keeps its own final size.")
	if not last.has("outcomes") or not last.has("outcome_radii"): return
	assert_eq(first.outcomes, ["偏小"], "Previously emitted state is a snapshot.")
	assert_eq(last.outcomes, task.outcomes)
	assert_eq(last.outcome_radii.size(), 3)
	assert_lt(last.outcome_radii[0], last.outcome_radii[1])
	assert_lt(last.outcome_radii[1], last.outcome_radii[2])
	var canvas: HeritagePixelCanvas = autofree(CANVAS.new())
	canvas.visual_state = last
	assert_true(canvas.has_method("get_outcome_draw_items"))
	if not canvas.has_method("get_outcome_draw_items"): return
	var items: Array = canvas.call("get_outcome_draw_items")
	assert_eq(items.size(), 3)
	assert_eq(items[0].source, Rect2(0, 0, 160, 160), "Small: existing thick-walled embryo.")
	assert_eq(items[1].source, Rect2(800, 0, 160, 160), "Good: existing formed amber bubble.")
	assert_eq(items[2].source, Rect2(640, 0, 160, 160), "Overblown: existing deformed bubble.")
	assert_lt(items[0].destination.size.x, items[1].destination.size.x)
	assert_lt(items[1].destination.size.x, items[2].destination.size.x)
	for item: Dictionary in items:
		assert_almost_eq(item.destination.end.y, 541.0, 0.001, "All outcomes rest on the tray.")
	last.outcomes[0] = "合适"
	last.outcome_radii[0] = 9.0
	assert_eq(task.outcomes[0], "偏小", "Presentation cannot change scoring history.")
	assert_lt(task.outcome_radii[0], 0.56)

func test_two_good_bubbles_still_pass_and_a_new_run_starts_empty() -> void:
	var task := _start()
	var results: Array[HeritageTaskResult] = []
	task.task_completed.connect(func(result: HeritageTaskResult) -> void: results.append(result))
	_blow(task, 0.60)
	_blow(task, 0.70)
	_blow(task, 0.76)
	assert_eq(results.size(), 1)
	if not results.is_empty():
		assert_true(results[0].is_success())
		assert_eq(results[0].metrics.successes, 2)
		assert_eq(results[0].metrics.outcomes, ["合适", "合适", "过大"])
	var fresh := _start()
	var state: Dictionary = fresh.get_presentation_state()
	assert_eq(state.get("outcomes", ["missing"]), [])
	assert_eq(state.get("outcome_radii", [1.0]), [])
	assert_eq(fresh.successes, 0)

func test_pause_freezes_current_blow_and_preserves_finished_outcomes() -> void:
	var task := _start()
	_blow(task, 0.35)
	_edge(task, true)
	for frame: int in 160: task._process(DT)
	var before: Dictionary = task.get_presentation_state()
	task.set_suspended(true)
	for frame: int in 240: task._process(DT)
	var paused: Dictionary = task.get_presentation_state()
	assert_eq(paused, before)
	task.set_suspended(false)
	for frame: int in 190:
		if task.resume_countdown <= 0.0: break
		task._process(DT)
	_edge(task, true)
	task._process(DT)
	var resumed: Dictionary = task.get_presentation_state()
	assert_eq(resumed.get("outcomes", ["missing"]), ["偏小"])
	assert_eq(resumed.get("outcome_radii", []), before.get("outcome_radii", [1.0]))
	assert_eq(resumed.blow_phase, 1, "The active blow resumes; no premature result is added.")
	_edge(task, false)

func test_demo_and_practice_results_do_not_leak_into_live_trays() -> void:
	var task := _start(false)
	var demo_had_result := false
	for frame: int in 400:
		if task.phase == HeritageStageTask.Phase.PRACTICE: break
		task._process(DT)
		if not task.outcomes.is_empty(): demo_had_result = true
	assert_true(demo_had_result)
	assert_eq(task.phase, HeritageStageTask.Phase.PRACTICE)
	assert_eq(task.get_presentation_state().get("outcomes", ["missing"]), [])
	assert_eq(task.get_presentation_state().get("outcome_radii", [1.0]), [])
	_edge(task, true)
	for frame: int in 130: task._process(DT)
	_edge(task, false)
	for frame: int in 260:
		if task.phase == HeritageStageTask.Phase.COUNTDOWN: break
		task._process(DT)
	assert_eq(task.phase, HeritageStageTask.Phase.COUNTDOWN)
	assert_eq(task.get_presentation_state().get("outcomes", ["missing"]), [])
	assert_eq(task.get_presentation_state().get("outcome_radii", [1.0]), [])

func test_generated_art_keeps_source_detail_and_same_outcome_sizes() -> void:
	var art := load("res://InheritanceTasks/Art/Pixel/v3/resources/tianmen_tang_su.tres") as HeritageTaskPresentation
	assert_eq(art.pixel_canvas_size, Vector2i(1000,600), "The larger view retains source facial and hand detail.")
	for id: StringName in [&"travel_blogger", &"life_blogger", &"business_blogger", &"food_blogger", &"adventure_blogger", &"magic_blogger"]:
		var appearance := art.get_appearance(id)
		assert_eq(appearance.frame_size, Vector2i(362,362), "No 200px downsample of generated actors.")
		assert_eq(appearance.portrait.get_size(), Vector2(362,362))
	var canvas: HeritagePixelCanvas = autofree(CANVAS.new())
	canvas.visual_state = {"outcomes": ["偏小", "合适", "过大"], "outcome_radii": [0.4,0.66,0.9]}
	var legacy: Array = canvas.call("get_outcome_draw_items")
	canvas.artwork = art
	var current: Array = canvas.call("get_outcome_draw_items")
	for i: int in 3:
		assert_eq(current[i].source.size, Vector2(362,362), "Preserve membrane source detail too.")
		assert_eq(current[i].destination.size, legacy[i].destination.size, "Art resolution does not alter represented size.")
		assert_eq(current[i].radius, legacy[i].radius)

func _start(skip_tutorial: bool = true) -> HeritageStageTask:
	var task := TASK_SCENE.instantiate() as HeritageStageTask
	add_child_autofree(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000, 600)
	var context := HeritageTaskRunContext.new(&"tianmen_tang_su")
	context.test_mode = true
	context.metadata["skip_tutorial"] = skip_tutorial
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	if skip_tutorial:
		for frame: int in 380:
			if task.phase == HeritageStageTask.Phase.LIVE: break
			task._process(DT)
		assert_eq(task.phase, HeritageStageTask.Phase.LIVE)
	return task

func _blow(task: HeritageStageTask, release_radius: float) -> Dictionary:
	var trial: int = task.trial
	assert_eq(task.blow_phase, 0)
	_edge(task, true)
	for frame: int in 1200:
		if task.radius >= release_radius or task.run_state == HeritageTaskBase.RunState.FINISHED: break
		task._process(DT)
	var release_size: float = task.radius
	_edge(task, false)
	for frame: int in 100:
		if task.blow_phase == 3: break
		task._process(DT)
	assert_eq(task.blow_phase, 3)
	assert_gt(task.radius, release_size, "The real residual growth remains intact.")
	var state: Dictionary = task.get_presentation_state()
	for frame: int in 160:
		if task.trial != trial or task.run_state == HeritageTaskBase.RunState.FINISHED: break
		task._process(DT)
	return state

func _edge(task: HeritageTaskBase, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	task.task_input(event)
