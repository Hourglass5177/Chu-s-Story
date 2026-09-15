extends GutTest
const STORY := preload("res://InheritanceTasks/Tasks/xiabaoping_minjian_gushi.tscn")
const Driver := preload("res://tests/support/action_story_input.gd")

func _new_story(tutorial: bool = false) -> HeritageStageTask:
	var task := add_child_autofree(STORY.instantiate()) as HeritageStageTask
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size = Vector2(1000,600)
	var context := HeritageTaskRunContext.new(&"xiabaoping_minjian_gushi")
	context.test_mode = true
	context.metadata["skip_tutorial"] = not tutorial
	context.metadata[&"presentation"] = load("res://InheritanceTasks/Definitions/xiabaoping_minjian_gushi.tres").presentation
	task.configure(context)
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	Driver.tick(task,2.6 if tutorial else 3.1)
	return task

func test_formal_art_keeps_the_interactive_board_renderer() -> void:
	var task := _new_story()
	assert_false(is_instance_valid(task.pixel_stage),"Puzzle cells are drawn by the story controller, not the generic avatar stage")
	assert_not_null(task.scene_texture)
	assert_not_null(task.reference_texture)
	assert_eq(task.scene_texture.get_size(),Vector2(724,724))
	assert_same(task.scene_texture,task.reference_texture,"Reference must retain the same original details")
	assert_eq(task.texture_filter,CanvasItem.TEXTURE_FILTER_NEAREST)

func test_clock_and_scene_are_separate_from_small_tv_dial() -> void:
	var task := _new_story()
	task.time_left = 104.0
	assert_eq(task.get_time_display(),"拼图")
	assert_eq(task.puzzle_hud_state().clock,"剩余 1:44")
	assert_eq(task.puzzle_hud_state().scene,"第 1 / 3 幕")
	Driver.solve_scene(task)
	assert_eq(task.get_time_display(),"故事")
	assert_eq(task.puzzle_hud_state().clock,"计时暂停")
	var before: float = task.time_left
	Driver.tick(task,1.0)
	assert_eq(task.time_left,before)

func test_gamepad_moves_blank_and_echo_never_moves_it_again() -> void:
	var task := _new_story()
	var direction: int = task.candidates[0].solution[0]
	var before: int = task.empty_index
	for down: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = {-1:JOY_BUTTON_DPAD_LEFT,1:JOY_BUTTON_DPAD_RIGHT,-2:JOY_BUTTON_DPAD_UP,2:JOY_BUTTON_DPAD_DOWN}[direction]
		event.pressed = down
		task.task_input(event)
	assert_eq(task.empty_index,before+{-1:-1,1:1,-2:-3,2:3}[direction])
	Driver.tick(task,.15)
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_A
	echo.pressed = true
	echo.echo = true
	task.task_input(echo)
	assert_eq(task.moves,1)

func test_mouse_neighbor_moves_identically_at_all_window_sizes() -> void:
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1600)]:
		var task := _new_story()
		task.size = dimensions
		var direction: int = task.candidates[0].solution[0]
		var index: int = task.empty_index+{-1:-1,1:1,-2:-3,2:3}[direction]
		var point: Vector2 = task.BOARD_RECT.position+Vector2(index%3,index/3)*task.CELL+Vector2.ONE*task.CELL*.5
		Driver.mouse(task,point,true)
		Driver.mouse(task,point,false)
		assert_eq(task.empty_index,index)
		assert_eq(task.moves,1)

func test_replay_shows_three_complete_images_pauses_and_finishes_once() -> void:
	var task := _new_story()
	for scene: int in 3:
		Driver.solve_scene(task)
		Driver.tick(task,task.reveal_left+.01)
	watch_signals(task)
	task.replay_story()
	assert_true(task.replaying)
	assert_eq(task.scene_index,0)
	assert_eq(task.board,task.GOAL)
	Driver.tick(task,4.6)
	assert_eq(task.scene_index,1)
	task.set_suspended(true)
	Driver.tick(task,8.0)
	assert_eq(task.scene_index,1)
	task.set_suspended(false)
	Driver.tick(task,9.0)
	assert_signal_emit_count(task,"story_replay_finished",1)
	task._end_replay()
	assert_signal_emit_count(task,"story_replay_finished",1)
	assert_signal_not_emitted(task,"task_completed")

func test_practice_requires_two_real_moves_and_resets_to_seeded_first_board() -> void:
	var task := _new_story(true)
	assert_eq(task.phase,HeritageStageTask.Phase.PRACTICE)
	Driver.tap(task,KEY_SPACE)
	Driver.tick(task,.2)
	assert_eq(task.lesson_moves,0)
	Driver.tap(task,KEY_D)
	Driver.tick(task,.15)
	assert_eq(task.lesson_moves,1)
	Driver.tap(task,KEY_S)
	Driver.tick(task,.15)
	assert_eq(task.phase,HeritageStageTask.Phase.COUNTDOWN)
	Driver.tick(task,3.1)
	assert_eq(task.scene_index,0)
	assert_eq(task.board,task.candidates[0].board.map(func(value: Variant) -> int: return int(value)))
	assert_eq(task.moves,0)
	assert_eq(task.completed_scenes,0)

func test_replay_after_timeout_restores_the_players_partial_board() -> void:
	var task := _new_story()
	var direction: int = task.candidates[0].solution[0]
	Driver.tap(task,{-1:KEY_A,1:KEY_D,-2:KEY_W,2:KEY_S}[direction])
	Driver.tick(task,.2)
	var saved: Array[int] = task.board.duplicate()
	var blank: int = task.empty_index
	Driver.tick(task,120.0)
	task.replay_story()
	Driver.tick(task,13.6)
	assert_eq(task.board,saved)
	assert_eq(task.empty_index,blank)
