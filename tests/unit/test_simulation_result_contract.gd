extends GutTest


func test_complete_report_satisfies_balance_data_contract() -> void:
	var report := _valid_report(3)
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 3)
	assert_true(errors.is_empty())
	assert_true(bool(report.contract_valid))
	assert_false(bool(report.aborted))
	assert_eq(report.validation_errors, [])


func test_missing_game_result_is_never_reported_as_success() -> void:
	var config := SimulationSchedule.build_match(2, SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 0, 777)
	var recorder := BalanceTelemetryRecorder.new()
	recorder.start_match(config, [])
	var report := recorder.finish_match(null)
	assert_true(bool(report.aborted))
	assert_string_contains(String(report.abort_reason), "missing_game_result")
	assert_eq(int(report.end_reason), -1)


func test_contract_rejects_startup_player_and_turn_failures() -> void:
	var report := _valid_report(2)
	report.startup_ready = false
	report.started_player_count = 1
	report.players = [report.players[0]]
	report.turns = 0
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 2)
	assert_has(errors, "startup_not_ready")
	assert_has(errors, "started_player_count_mismatch")
	assert_has(errors, "reported_player_count_mismatch")
	assert_has(errors, "no_completed_turns")
	assert_true(bool(report.aborted))
	assert_false(bool(report.contract_valid))


func test_contract_rejects_missing_or_invalid_result() -> void:
	var report := _valid_report(2)
	report.result_present = false
	report.result_turn_number = 0
	report.result_entry_count = 0
	report.end_reason = -1
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 2)
	assert_has(errors, "missing_game_result")
	assert_has(errors, "invalid_result_turn")
	assert_has(errors, "invalid_end_reason")
	assert_has(errors, "result_entry_count_mismatch")


func test_contract_rejects_every_runtime_state_leak() -> void:
	var report := _valid_report(2)
	report.interaction_snapshot = {"interaction_id": 7}
	report.game_on = true
	report.modal_snapshot = {
		"depth": 1,
		"owners": [&"event"],
		"tree_pause_depth": 1,
		"tree_pause_owners": [&"event"],
		"tree_paused": true,
	}
	report.map_choice_active = true
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 2)
	assert_has(errors, "interaction_not_quiescent")
	assert_has(errors, "game_still_running")
	assert_has(errors, "modal_not_quiescent")
	assert_has(errors, "modal_owners_not_empty")
	assert_has(errors, "tree_pause_not_quiescent")
	assert_has(errors, "tree_pause_owners_not_empty")
	assert_has(errors, "scene_tree_still_paused")
	assert_has(errors, "map_choice_not_quiescent")
	assert_string_contains(String(report.abort_reason), "contract:")


func test_contract_rejects_missing_runtime_snapshots_instead_of_assuming_empty() -> void:
	var report := _valid_report(2)
	report.erase("interaction_snapshot")
	report.erase("modal_snapshot")
	report.erase("map_choice_active")
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 2)
	assert_has(errors, "missing_interaction_snapshot")
	assert_has(errors, "missing_modal_snapshot")
	assert_has(errors, "missing_map_choice_state")


func test_contract_rejects_a_modal_snapshot_without_tree_pause_ownership() -> void:
	var report := _valid_report(2)
	report.modal_snapshot = {"depth": 0, "owners": []}
	var errors := BalanceTelemetryRecorder.apply_report_contract(report, 2)
	assert_has(errors, "missing_tree_pause_state")


func _valid_report(player_count: int) -> Dictionary:
	var players: Array[Dictionary] = []
	for player_index: int in player_count:
		players.append({"player_index": player_index})
	return {
		"startup_ready": true,
		"player_count": player_count,
		"started_player_count": player_count,
		"players": players,
		"turns": 8,
		"result_present": true,
		"game_on": false,
		"result_turn_number": 8,
		"result_entry_count": player_count,
		"end_reason": GameResult.EndReason.SCORE_LIMIT,
		"interaction_snapshot": {},
		"modal_snapshot": {
			"depth": 0,
			"owners": [],
			"tree_pause_depth": 0,
			"tree_pause_owners": [],
			"tree_paused": false,
		},
		"map_choice_active": false,
		"aborted": false,
		"abort_reason": "",
	}
