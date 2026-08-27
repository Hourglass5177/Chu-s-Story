extends GutTest

const PAUSE_SCENE := preload("res://HUDs/PauseOverlay/pause_overlay.tscn")

var _overlay: PauseOverlay
var _paused_backup := false
var _game_on_backup := false
var _phase_backup: TurnManager.TurnPhase
var _result_backup: GameResult
var _timer_was_stopped := true
var _timer_time_backup := 0.0


func before_each() -> void:
	_paused_backup = get_tree().paused
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_result_backup = TurnManager.get_game_result()
	_timer_was_stopped = TurnManager.turn_timer.is_stopped()
	_timer_time_backup = TurnManager.turn_timer.time_left
	get_tree().paused = false
	InteractionCoordinator.cancel_all(&"pause_test_setup")
	TurnManager.invalidate_all_modals(&"pause_test_setup")
	TurnManager.GameOn = true
	TurnManager._last_game_result = null
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.turn_timer.start(9.0)
	_overlay = PAUSE_SCENE.instantiate() as PauseOverlay
	add_child_autofree(_overlay)
	await get_tree().process_frame


func after_each() -> void:
	if _overlay != null and _overlay.visible:
		_overlay.close_pause()
	InteractionCoordinator.cancel_all(&"pause_test_teardown")
	TurnManager.invalidate_all_modals(&"pause_test_teardown")
	TurnManager.turn_timer.stop()
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager._last_game_result = _result_backup
	if not _timer_was_stopped and _timer_time_backup > 0.0:
		TurnManager.turn_timer.start(_timer_time_backup)
	get_tree().paused = _paused_backup


func test_pause_owns_one_modal_and_restores_the_exact_remaining_phase_time() -> void:
	await get_tree().create_timer(0.05).timeout
	var remaining_before := TurnManager.turn_timer.time_left
	assert_true(_overlay.open_pause())
	assert_true(_overlay.visible)
	assert_true(get_tree().paused)
	assert_true(TurnManager.turn_timer.is_stopped())
	var snapshot := TurnManager.get_modal_snapshot()
	assert_eq(int(snapshot.get("depth", 0)), 1)
	assert_true(&"pause_menu" in snapshot.get("owners", []))
	await get_tree().create_timer(0.05, true).timeout
	assert_true(_overlay.close_pause())
	assert_false(_overlay.visible)
	assert_false(get_tree().paused)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_almost_eq(TurnManager.turn_timer.time_left, remaining_before, 0.2, "继续游戏应恢复暂停前的剩余时间，而不是重置15秒")
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)


func test_pause_preserves_an_uncovered_map_choice_modal() -> void:
	var lease := TurnManager.acquire_modal(&"map_choice", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	assert_true(_overlay.open_pause())
	assert_true(_overlay.visible)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	assert_true(_overlay.close_pause())
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 1)
	assert_true(TurnManager.release_modal(lease))


func test_pause_freezes_and_resumes_an_active_interaction() -> void:
	var ticket := InteractionCoordinator.begin_interaction(&"pause_test_interaction", 5.0)
	await get_tree().create_timer(0.05).timeout
	var remaining_before := InteractionCoordinator.get_time_left(ticket.interaction_id)

	assert_true(_overlay.open_pause())
	assert_true(InteractionCoordinator.is_active_suspended())
	await get_tree().create_timer(0.05, true).timeout
	assert_almost_eq(InteractionCoordinator.get_time_left(ticket.interaction_id), remaining_before, 0.05)
	assert_true(_overlay.close_pause())
	assert_false(InteractionCoordinator.is_active_suspended())
	assert_gt(InteractionCoordinator.get_time_left(ticket.interaction_id), 0.0)
	assert_true(InteractionCoordinator.cancel(ticket.interaction_id, &"pause_test_complete"))
