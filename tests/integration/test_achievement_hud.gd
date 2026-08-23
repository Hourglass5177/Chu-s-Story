extends GutTest

const HUD_SCENE := preload("res://HUDs/HUD.tscn")

var _hud: HUD
var _player: PlayerClass
var _other_player: PlayerClass
var _players_backup: Array[PlayerClass] = []
var _turn_state_backup: Dictionary = {}
var _resource_hud_backup: HUD = null
var _paused_backup := false


func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_turn_state_backup = {
		"player_num": TurnManager.player_num,
		"now_player_index": TurnManager.now_player_index,
		"next_player_index": TurnManager.next_player_index,
		"now_phase": TurnManager.now_phase,
		"now_turn": TurnManager.now_turn,
		"game_on": TurnManager.GameOn,
		"hud": TurnManager.hud,
		"map": TurnManager.map,
		"result": TurnManager._last_game_result,
	}
	_resource_hud_backup = ResourceManager.hud
	_paused_backup = get_tree().paused
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	_player = PlayerClass.new()
	_player.player_name = "HUD成就玩家"
	_player.player_index = 0
	var score_probe := Label.new()
	_player.add_child(score_probe)
	_player.score_label = score_probe
	_other_player = PlayerClass.new()
	_other_player.player_name = "另一位玩家"
	_other_player.player_index = 1
	var other_score_probe := Label.new()
	_other_player.add_child(other_score_probe)
	_other_player.score_label = other_score_probe
	var players: Array[PlayerClass] = [_player, _other_player]
	AchievementManager.reset_for_new_game(players)
	TurnManager.players.assign(players)
	TurnManager.player_num = 2
	TurnManager.now_player_index = 0
	TurnManager.next_player_index = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.now_turn = 1
	TurnManager.GameOn = true
	TurnManager._last_game_result = null
	ResourceManager.hud = null
	_hud = HUD_SCENE.instantiate() as HUD
	add_child_autofree(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	if _hud.map != null and not _hud.map.grid_map.is_empty():
		_player.now_pos = _hud.map.grid_map.keys()[0]


func after_each() -> void:
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	if is_instance_valid(_hud):
		if _hud.game_result_overlay != null:
			_hud.game_result_overlay.reset_overlay(false)
		if _hud.achievement_detail_overlay != null and _hud.achievement_detail_overlay.visible:
			_hud.achievement_detail_overlay.close_panel()
		if _hud.score_overlay != null and _hud.score_overlay.visible:
			_hud.score_overlay.close_panel()
	AchievementManager.reset_for_new_game([])
	ResourceManager.hud = _resource_hud_backup
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = int(_turn_state_backup["player_num"])
	TurnManager.now_player_index = int(_turn_state_backup["now_player_index"])
	TurnManager.next_player_index = int(_turn_state_backup["next_player_index"])
	TurnManager.now_phase = int(_turn_state_backup["now_phase"])
	TurnManager.now_turn = int(_turn_state_backup["now_turn"])
	TurnManager.GameOn = bool(_turn_state_backup["game_on"])
	TurnManager.hud = _turn_state_backup["hud"] as HUD
	TurnManager.map = _turn_state_backup["map"] as MAP
	TurnManager._last_game_result = _turn_state_backup["result"] as GameResult
	if is_instance_valid(_player):
		_player.free()
	if is_instance_valid(_other_player):
		_other_player.free()
	get_tree().paused = _paused_backup


func test_achievement_section_is_absent_until_owned_and_thumbnail_is_read_only() -> void:
	_hud.refresh_feiyi_list(_player)
	assert_null(_hud.feiyi_list.get_node_or_null("成就牌列表区"), "没有成就时连标题也不得显示")
	_player.current_energy = 11
	TurnManager.turn_timer.start(8.0)
	assert_true(ResourceManager.modify_energy(_player, 1, "HUD成就测试"))
	await get_tree().process_frame

	var section := _hud.feiyi_list.get_node_or_null("成就牌列表区")
	assert_not_null(section)
	if section == null:
		return
	assert_eq(section.get_node("标题").text, "成就")
	var grid := section.get_node("卡牌列表") as GridContainer
	assert_eq(grid.get_child_count(), 1)
	var thumbnail := grid.get_child(0) as 成就牌缩略图
	assert_false(thumbnail.has_signal(&"request_use_card"), "成就缩略图只能查看详情")
	assert_eq(thumbnail.score_label.text, "2", "计分徽章应像非遗牌一样只显示数字")
	var badge_style := thumbnail.get_node("ScoreBadge").get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(badge_style.corner_radius_top_left, 50, "成就计分徽章应使用与非遗牌相同的圆形轮廓")
	thumbnail.pressed.emit()
	assert_true(_hud.achievement_detail_overlay.visible)
	assert_null(_hud.achievement_detail_overlay.get_node_or_null("Panel/UseButton"))
	_hud.achievement_detail_overlay.close_panel()
	assert_false(get_tree().paused)


func test_off_turn_achievement_cannot_replace_current_players_profile_or_hand_section() -> void:
	var food := 食物牌.new()
	for _index: int in 6:
		AchievementManager.record_food_consumed(_player, food)
	await get_tree().process_frame
	_assert_single_visible_achievement(AchievementManager.ID_TAO_TIE)

	_other_player.current_energy = 11
	_hud.achievement_toast.clear_queue()
	assert_true(ResourceManager.modify_energy(_other_player, 1, "非当前玩家达成成就"))
	await get_tree().process_frame
	assert_eq(_hud.name_label.text, _player.player_name, "后台玩家数值变化不得替换当前玩家档案")
	assert_eq(_other_player.score_label.text, "2", "后台玩家自己的地图分数徽章仍须即时更新")
	assert_eq(_hud.achievement_toast.name_label.text, "%s · 超越人类" % _other_player.player_name, "跨玩家提示必须明确领取者")
	_assert_single_visible_achievement(AchievementManager.ID_TAO_TIE)

	# 即使某个外围系统错误地请求刷新后台玩家，HUD 自身也必须守住当前玩家边界。
	_hud.refresh_achievement_list(_other_player)
	_assert_single_visible_achievement(AchievementManager.ID_TAO_TIE)


func test_claim_toast_is_queued_concise_and_never_pauses_or_resets_action_timer() -> void:
	_player.current_energy = 11
	TurnManager.turn_timer.start(8.0)
	ResourceManager.modify_energy(_player, 1, "第一项成就")
	var remaining_after_first := TurnManager.turn_timer.time_left
	var food := 食物牌.new()
	for _index: int in 6:
		AchievementManager.record_food_consumed(_player, food)
	await get_tree().process_frame

	assert_true(_hud.achievement_toast.visible)
	assert_eq(_hud.achievement_toast._queue.size(), 1, "连续获得成就时应排队展示")
	assert_false(get_tree().paused)
	assert_lt(TurnManager.turn_timer.time_left, 9.0, "提示不能把ACTION计时重置到15秒")
	assert_lte(TurnManager.turn_timer.time_left, remaining_after_first)
	assert_null(_hud.achievement_toast.get_node_or_null("Panel/Margin/Content/Text/Caption"))
	assert_false(_hud.achievement_toast.name_label.text.is_empty())
	assert_true(_hud.achievement_toast.score_label.text.begins_with("+"))


func test_score_details_include_achievement_score_and_owned_names() -> void:
	_player.current_energy = 11
	ResourceManager.modify_energy(_player, 1, "计分详情成就")
	_hud.score_overlay.open_for_player(_player)
	assert_eq(_hud.score_overlay.get_node("Panel/详情/成就分/数值").text, "+2")
	var owned_label := _hud.score_overlay.get_node("Panel/详情/成就明细") as Label
	assert_true(owned_label.visible)
	assert_true("超越人类 +2" in owned_label.text)
	_hud.score_overlay.close_panel()


func test_turn_manager_game_finished_signal_opens_the_integrated_result_layer() -> void:
	var breakdown := ResourceManager.get_score_breakdown(_player)
	var entry := GameResultEntry.new(_player, breakdown, 1, true)
	var entries: Array[GameResultEntry] = [entry]
	var result := GameResult.new(GameResult.EndReason.SCORE_LIMIT, 3, entries)
	TurnManager.game_finished.emit(result)
	await get_tree().process_frame
	assert_true(_hud.game_result_overlay.visible)
	assert_eq(_hud.game_result_overlay.get_state_name(), &"INTRO")
	assert_true(get_tree().paused)


func _assert_single_visible_achievement(expected_id: StringName) -> void:
	var section := _hud.feiyi_list.get_node_or_null("成就牌列表区")
	assert_not_null(section)
	if section == null:
		return
	var grid := section.get_node("卡牌列表") as GridContainer
	assert_eq(grid.get_child_count(), 1)
	if grid.get_child_count() != 1:
		return
	var thumbnail := grid.get_child(0) as 成就牌缩略图
	assert_eq(thumbnail.card_data.achievement_id, expected_id)
