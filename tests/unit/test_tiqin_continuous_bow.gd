extends GutTest

const Motion = preload("res://InheritanceTasks/Presentation/tiqin_bow_motion.gd")
const ClockFixture = preload("res://tests/unit/test_heritage_performance_lessons.gd").ManualMusicClock
const AVATARS := [&"travel_blogger", &"life_blogger", &"business_blogger", &"food_blogger", &"adventure_blogger", &"magic_blogger"]

func before_all() -> void:
	HeritageMinigamePreferences.configure_storage_path("user://tiqin-continuous-bow-test.cfg")
	HeritageMinigamePreferences.save_offset(0)

func after_all() -> void:
	HeritageMinigamePreferences.configure_storage_path()

func test_long_bow_changes_hand_and_bow_position_while_contact_and_arm_lengths_stay_fixed() -> void:
	for direction: int in [-1, 1]:
		var previous: Dictionary = {}
		for progress: float in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
			var pose: Dictionary = Motion.sample(progress, direction, Vector2(38, 92), Vector2(81, 105))
			assert_almost_eq(pose.shoulder.distance_to(pose.elbow), 18.0, 0.0001)
			assert_almost_eq(pose.elbow.distance_to(pose.wrist), 26.0, 0.0001)
			assert_eq(pose.shoulder, Vector2(38, 92), "Shoulder cannot follow the bow.")
			assert_eq(pose.string_contact, Vector2(81, 105))
			assert_eq(pose.bow_rect.size, Vector2(108, 8), "The bow translates; it must not stretch.")
			assert_lt(pose.bow_rect.position.x, pose.string_contact.x)
			assert_gt(pose.bow_rect.end.x, pose.string_contact.x)
			assert_almost_eq(pose.bow_rect.position.y + 6.0, pose.string_contact.y, 0.0001, "Authored horsehair remains on the string height.")
			assert_eq(pose.wrist, pose.bow_grip, "Grip follows the same position as the bow.")
			if not previous.is_empty():
				assert_gt((pose.wrist.x - previous.wrist.x) * direction, 0.0)
				assert_gt((pose.bow_rect.position.x - previous.bow_rect.position.x) * direction, 0.0)
			previous = pose

func test_generated_hold_input_drives_native_pose_progress_for_six_appearances_and_freezes_when_paused() -> void:
	var definition := load("res://InheritanceTasks/Definitions/ti_qin_xi.tres") as HeritageTaskDefinition
	for avatar: StringName in AVATARS:
		var task := definition.instantiate_task() as HeritagePerformanceTask
		add_child_autofree(task)
		task.clock = ClockFixture.new()
		task.add_child(task.clock)
		var context := HeritageTaskRunContext.new(&"ti_qin_xi")
		context.test_mode = true
		context.avatar_id = avatar
		context.metadata["skip_tutorial"] = true
		context.metadata["presentation"] = definition.presentation
		task.configure(context)
		task.start_task()
		task.set_process(false)
		task.set_physics_process(false)
		for frame: int in 320:
			if task.phase == HeritageStageTask.Phase.LIVE: break
			_frame(task, 0.01)
		var stage := definition.presentation.stage_scene.instantiate() as HeritagePixelCanvas
		stage.artwork = definition.presentation
		stage.avatar_id = avatar
		add_child_autofree(stage)
		for event: Dictionary in task.chart.events:
			if event.kind != "hold": continue
			_advance(task, float(event.time_ms) / 1000.0)
			_key(task, int(event.direction), true)
			if event.kind == "hold":
				var starting := task.get_performance_visual_state()
				assert_true(starting.active_hold)
				stage.receive_visual_state(starting)
				var first_pose: int = stage.get_generated_bow_frame()
				var duration := float(int(event.end_ms) - int(event.time_ms)) / 1000.0
				_advance(task, float(event.time_ms) / 1000.0 + duration * 0.45)
				var middle := task.get_performance_visual_state()
				assert_gt(middle.hold_progress, starting.hold_progress)
				assert_almost_eq(middle.hold_progress, 0.45, 0.002)
				stage.receive_visual_state(middle)
				assert_ne(stage.get_generated_bow_frame(), first_pose, "Generated arm and bow advance through source poses.")
				task.set_suspended(true)
				for frame: int in 20: _frame(task, 0.05)
				assert_true(task.get_performance_visual_state().active_hold, "Paused artwork retains its grip pose.")
				assert_eq(task.get_performance_visual_state().hold_progress, middle.hold_progress, "Pausing freezes arm/bow progress.")
				task.set_suspended(false)
				for frame: int in 152: _frame(task, 0.01)
				_key(task, int(event.direction), true)
				_advance(task, float(event.end_ms) / 1000.0)
				var ending := task.get_performance_visual_state()
				assert_true(ending.active_hold)
				assert_gt(ending.hold_progress, middle.hold_progress)
			_key(task, int(event.direction), false)
			var event_index := task.judge.events.find(event)
			assert_true(task.judge.states[event_index].done)
			assert_almost_eq(float(task.judge.states[event_index].score), 1.0, 0.0001, "Animation must not alter judgment.")
			break
		assert_eq(definition.presentation.pixel_canvas_size, Vector2i(1000, 600))
		assert_true(definition.presentation.get_appearance(avatar).frame_size.y >= 512, "Native generated details stay available.")

func _frame(task: HeritagePerformanceTask, delta: float) -> void:
	(task.clock as ClockFixture).elapse(delta)
	task._process(delta)

func _advance(task: HeritagePerformanceTask, seconds: float) -> void:
	while task.clock.seconds() < seconds - 0.000001 and task.phase != HeritageStageTask.Phase.COUNTDOWN:
		_frame(task, minf(1.0 / 120.0, seconds - task.clock.seconds()))

func _key(task: HeritagePerformanceTask, direction: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_LEFT if direction < 0 else KEY_RIGHT
	event.pressed = down
	task.task_input(event)
