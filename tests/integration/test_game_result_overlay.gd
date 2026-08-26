extends GutTest

const OVERLAY_SCENE := preload("res://HUDs/GameResultOverlay/game_result_overlay.tscn")

var _overlay: GameResultOverlay
var _was_paused := false


func before_each() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = false
	_overlay = OVERLAY_SCENE.instantiate() as GameResultOverlay
	add_child_autofree(_overlay)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_overlay):
		_overlay.reset_overlay(false)
	get_tree().paused = _was_paused


func test_dictionary_snapshot_supports_competition_ranking_and_tied_winners() -> void:
	_overlay.present(_make_snapshot([18, 18, 12]), false)
	var entries := _overlay.get_normalized_entries()
	assert_eq(entries.size(), 3)
	assert_eq(entries[0]["rank"], 1)
	assert_eq(entries[1]["rank"], 1)
	assert_eq(entries[2]["rank"], 3)
	assert_true(entries[0]["is_winner"])
	assert_true(entries[1]["is_winner"])
	assert_false(entries[2]["is_winner"])
	assert_eq(_overlay.get_state_name(), &"COMPLETE")
	assert_true(get_tree().paused, "正式结算在暂停树时仍须保持可交互")


func test_accepts_typed_game_result_without_overlay_side_preload() -> void:
	var first := PlayerClass.new()
	first.player_index = 0
	first.player_name = "甲"
	first.player_types = PlayerClass.PlayerCharacter.魔术博主
	var second := PlayerClass.new()
	second.player_index = 1
	second.player_name = "乙"
	second.player_types = PlayerClass.PlayerCharacter.旅行博主
	var achievement := 成就牌.new()
	achievement.card_name = "幸运儿"
	achievement.score_value = 3
	var first_entry := GameResultEntry.new(first, {
		"base_score": 17,
		"category_combo_score": 0,
		"category_completion_score": 0,
		"regional_combo_score": 0,
		"achievement_score": 3,
		"total_score": 20,
		"achievements": [achievement],
	}, 1, true)
	var second_entry := GameResultEntry.new(second, {"base_score": 9, "total_score": 9}, 2, false)
	var typed_entries: Array[GameResultEntry] = [first_entry, second_entry]
	var result := GameResult.new(GameResult.EndReason.SCORE_LIMIT, 8, typed_entries)
	_overlay.present(result, false)
	var entries := _overlay.get_normalized_entries()
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["profession"], "魔术博主")
	assert_eq(entries[0]["achievement_score"], 3)
	assert_eq(entries[0]["achievements"][0]["score"], 3)
	assert_eq(entries[0]["rank"], 1)
	first.free()
	second.free()


func test_solo_defeat_keeps_rank_but_has_no_champion_presentation() -> void:
	var player := PlayerClass.new()
	player.player_index = 0
	player.player_name = "独行者"
	player.player_types = PlayerClass.PlayerCharacter.探险博主
	var entry := GameResultEntry.new(player, {
		"base_score": 8,
		"category_combo_score": 2,
		"total_score": 10,
	}, 1, false)
	var typed_entries: Array[GameResultEntry] = [entry]
	var result := GameResult.new(GameResult.EndReason.SOLO_DEFEAT, 4, typed_entries)

	_overlay.present(result, false)

	var entries := _overlay.get_normalized_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["rank"], 1, "单人失败仍保留最终排名")
	assert_false(entries[0]["is_winner"], "精力耗尽的单人局不得被结算层重新推导为冠军")
	assert_eq((_overlay.get_node("Frame/StagePanel/StageLabel") as Label).text, "挑战失败")
	assert_false(_overlay.get_node("Frame/WinnerShowcase").visible)
	assert_eq(_overlay.get_node("Frame/WinnerShowcase/WinnerList").get_child_count(), 0)
	assert_false((_overlay.get_node("Sparkles") as CPUParticles2D).emitting)
	player.free()


func test_solo_defeat_reveal_step_does_not_start_champion_particles() -> void:
	var snapshot := _make_snapshot([10])
	snapshot["end_reason"] = GameResult.EndReason.SOLO_DEFEAT
	_overlay.present(snapshot, true)
	for _index in range(7):
		_overlay.fast_forward_current_step()
	assert_eq(_overlay.get_state_name(), &"WINNER_REVEAL")
	assert_eq((_overlay.get_node("Frame/StagePanel/StageLabel") as Label).text, "挑战失败")
	assert_false(_overlay.get_node("Frame/WinnerShowcase").visible)
	assert_false((_overlay.get_node("Sparkles") as CPUParticles2D).emitting)


func test_skip_reaches_complete_without_waiting_for_animation() -> void:
	_overlay.present(_make_snapshot([20, 9]), true)
	assert_eq(_overlay.get_state_name(), &"INTRO")
	_overlay.skip_all()
	assert_eq(_overlay.get_state_name(), &"COMPLETE")
	assert_true(_overlay.get_node("Frame/ActionBar").visible)
	assert_false(_overlay.get_node("Frame/Header/SkipButton").visible)
	await get_tree().process_frame
	assert_eq(_overlay.get_state_name(), &"COMPLETE", "跳过后旧Tween或异步排名回调不得改回状态")


func test_autoplay_completes_while_tree_is_paused() -> void:
	watch_signals(_overlay)
	_overlay.present(_make_snapshot([20, 12, 8]), true)
	assert_true(get_tree().paused)
	assert_eq(_overlay.get_state_name(), &"INTRO")
	await get_tree().create_timer(6.2, true).timeout
	assert_eq(_overlay.get_state_name(), &"COMPLETE")
	assert_signal_emit_count(_overlay, "presentation_finished", 1)
	assert_true(get_tree().paused, "正式结算完成后仍保持终局暂停")


func test_fixed_segments_use_animation_player_and_winner_showcase() -> void:
	var animation_player := _overlay.get_node("FixedAnimationPlayer") as AnimationPlayer
	assert_not_null(animation_player)
	assert_true(animation_player.has_animation(&"intro"))
	assert_true(animation_player.has_animation(&"winner_reveal"))
	_overlay.present(_make_snapshot([20, 20, 8]), true)
	assert_eq(animation_player.current_animation, "intro")
	for _index in range(7):
		_overlay.fast_forward_current_step()
	assert_eq(_overlay.get_state_name(), &"WINNER_REVEAL")
	assert_true(_overlay.get_node("Frame/WinnerShowcase").visible)
	assert_eq(_overlay.get_node("Frame/WinnerShowcase/WinnerList").get_child_count(), 2)
	assert_gt((_overlay.get_node("Sparkles") as CanvasItem).z_index, (_overlay.get_node("Frame") as CanvasItem).z_index)


func test_fast_forward_advances_only_the_current_segment() -> void:
	_overlay.present(_make_snapshot([20, 9]), true)
	_overlay.fast_forward_current_step()
	assert_eq(_overlay.get_state_name(), &"SCORE_REVEAL")
	_overlay.fast_forward_current_step()
	assert_eq(_overlay.get_state_name(), &"SCORE_REVEAL", "一次快进只完成一个计分分项")
	for _index in range(4):
		_overlay.fast_forward_current_step()
	assert_eq(_overlay.get_state_name(), &"RANK_REORDER")


func test_enter_fast_forward_works_even_if_a_background_button_had_focus() -> void:
	var background_button := Button.new()
	add_child_autofree(background_button)
	background_button.grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), background_button)
	_overlay.present(_make_snapshot([20, 9]), true)
	assert_ne(get_viewport().gui_get_focus_owner(), background_button)
	var enter_event := InputEventKey.new()
	enter_event.pressed = true
	enter_event.keycode = KEY_ENTER
	_overlay._input(enter_event)
	assert_eq(_overlay.get_state_name(), &"SCORE_REVEAL")


func test_visible_digital_guide_blocks_result_fast_forward_input() -> void:
	var guide_overlay := Control.new()
	guide_overlay.add_to_group(&"digital_game_guide")
	add_child_autofree(guide_overlay)
	guide_overlay.show()
	_overlay.present(_make_snapshot([20, 9]), true)
	var enter_event := InputEventKey.new()
	enter_event.pressed = true
	enter_event.keycode = KEY_ENTER
	_overlay._input(enter_event)
	assert_eq(_overlay.get_state_name(), &"INTRO", "数字指南打开时不得快进后台结算")


func test_details_is_an_internal_page_and_navigation_uses_signals() -> void:
	_overlay.present(_make_snapshot([20, 9]), false)
	var return_requested := [false]
	var quit_requested := [false]
	_overlay.return_to_main_menu_requested.connect(func(): return_requested[0] = true)
	_overlay.quit_requested.connect(func(): quit_requested[0] = true)
	_overlay.get_node("Frame/ActionBar/DetailsButton").pressed.emit()
	assert_true(_overlay.is_showing_details())
	assert_true(_overlay.get_node("Frame/DetailsPage").visible)
	assert_true(get_tree().paused)
	_overlay.get_node("Frame/ActionBar/DetailsButton").pressed.emit()
	assert_false(_overlay.is_showing_details())
	_overlay.get_node("Frame/ActionBar/ReturnButton").pressed.emit()
	_overlay.get_node("Frame/ActionBar/QuitButton").pressed.emit()
	assert_true(return_requested[0])
	assert_true(quit_requested[0])


func test_two_three_and_six_player_layouts_use_bounded_grid_columns() -> void:
	for player_count in [2, 3, 6]:
		var scores: Array[int] = []
		for index in player_count:
			scores.append(20 - index)
		_overlay.present(_make_snapshot(scores), false)
		var grid := _overlay.get_node("Frame/SummaryPage/GridCenter/PlayerGrid") as GridContainer
		assert_eq(grid.get_child_count(), player_count)
		assert_eq(grid.columns, 2 if player_count == 2 else 3)
		_overlay.reset_overlay(false)


func _make_snapshot(scores: Array[int]) -> Dictionary:
	var entries: Array[Dictionary] = []
	for index in scores.size():
		entries.append({
			"player_index": index,
			"player_name": "P%d" % (index + 1),
			"profession": "旅行博主",
			"alive": index != scores.size() - 1,
			"breakdown": {
				"base_score": scores[index] - 4,
				"category_combo_score": 2,
				"category_completion_score": 0,
				"regional_combo_score": 1,
				"achievement_score": 1,
				"total_score": scores[index],
			},
			"achievements": [{"name": "幸运儿", "score": 3}],
		})
	return {"end_reason": "score_limit", "entries": entries}
