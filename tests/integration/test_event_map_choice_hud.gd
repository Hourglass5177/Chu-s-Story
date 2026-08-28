extends GutTest

const HUD_SCENE := preload("res://HUDs/HUD.tscn")

var _hud: HUD
var _player: PlayerClass
var _players_backup: Array[PlayerClass] = []
var _turn_state_backup: Dictionary = {}
var _event_hud_backup: HUD = null
var _event_overlay_backup: Control = null
var _resource_hud_backup: HUD = null
var _market_backup: Array[非遗牌] = []
var _event_discard_backup: Array[事件牌] = []
var _async_done: bool = false
var _hand_wait_done: bool = false


func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_turn_state_backup = {
		"player_num": TurnManager.player_num,
		"now_player_index": TurnManager.now_player_index,
		"now_phase": TurnManager.now_phase,
		"now_turn": TurnManager.now_turn,
		"game_on": TurnManager.GameOn,
		"hud": TurnManager.hud,
		"map": TurnManager.map,
		"modal_depth": TurnManager.modal_resolution_depth,
		"modal_resume_time": TurnManager._modal_resume_time,
		"modal_resume_phase": TurnManager._modal_resume_phase,
	}
	_event_hud_backup = EventManager.hud
	_event_overlay_backup = EventManager.event_overlay
	_resource_hud_backup = ResourceManager.hud
	_market_backup = MarketManager.get_inventory()
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	EventManager.reset_for_new_game()
	MarketManager.reset_for_new_game()
	ResourceManager.事件弃牌堆.clear()

	_player = PlayerClass.new()
	_player.player_name = "地图选择玩家"
	_player.player_index = 0
	var score_probe := Label.new()
	_player.add_child(score_probe)
	_player.score_label = score_probe
	var players: Array[PlayerClass] = [_player]
	TurnManager.players.assign(players)
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.now_turn = 1
	TurnManager.GameOn = true
	TurnManager.modal_resolution_depth = 0
	TurnManager._modal_resume_time = 0.0
	TurnManager._modal_resume_phase = TurnManager.TurnPhase.BEGIN

	_hud = HUD_SCENE.instantiate() as HUD
	add_child_autofree(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	TurnManager.hud = _hud
	TurnManager.map = _hud.map
	ResourceManager.hud = _hud
	_player.map = _hud.map
	_player.now_pos = _hud.map.grid_map.keys()[0]
	EventManager.bind_runtime(_hud, _hud.event_overlay)


func after_each() -> void:
	if is_instance_valid(_hud) and _hud.card_hand_animator != null:
		_hud.card_hand_animator.clear_queue()
	if is_instance_valid(_hud) and _hud.detail_panel != null and _hud.detail_panel.visible:
		_hud.detail_panel._on_close_pressed()
	await get_tree().process_frame
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(_event_hud_backup, _event_overlay_backup)
	ResourceManager.hud = _resource_hud_backup
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = int(_turn_state_backup["player_num"])
	TurnManager.now_player_index = int(_turn_state_backup["now_player_index"])
	TurnManager.now_phase = int(_turn_state_backup["now_phase"])
	TurnManager.now_turn = int(_turn_state_backup["now_turn"])
	TurnManager.GameOn = bool(_turn_state_backup["game_on"])
	TurnManager.hud = _turn_state_backup["hud"] as HUD
	TurnManager.map = _turn_state_backup["map"] as MAP
	TurnManager.modal_resolution_depth = int(_turn_state_backup["modal_depth"])
	TurnManager._modal_resume_time = float(_turn_state_backup["modal_resume_time"])
	TurnManager._modal_resume_phase = int(_turn_state_backup["modal_resume_phase"])
	TurnManager.turn_timer.stop()
	if is_instance_valid(_player):
		_player.free()


func test_grid_choice_uses_map_highlights_bottom_info_and_map_click_submission() -> void:
	var unique_sections: Array[MapSection] = []
	for section: MapSection in _hud.map.grid_map.values():
		if not unique_sections.has(section):
			unique_sections.append(section)
		if unique_sections.size() == 3:
			break
	assert_eq(unique_sections.size(), 3)
	if unique_sections.size() < 3:
		return
	var first := unique_sections[0]
	var second := unique_sections[1]
	var excluded := unique_sections[2]
	var request := EventChoiceRequest.new(
		_player,
		"艺径寻踪：选择移动终点",
		[first, second],
		PackedStringArray([first.section_name, second.section_name]),
		false,
		EventChoiceRequest.ChoiceKind.格子
	)
	request.request_id = 901
	request.timeout_seconds = 15.0
	request.source_name = "艺径寻踪"
	request.source_description = "掷两次骰子，选择其中一次的点数移动。"
	EventManager._pending_request = request
	EventManager._pending_choice = null
	EventManager._choice_waiting = true
	EventManager._choice_timer.start(request.timeout_seconds)

	EventManager.choice_requested.emit(request)
	await get_tree().process_frame

	assert_false(_hud.event_overlay.visible, "格子选择不得继续显示按钮列表遮罩")
	assert_true(first.is_reachable)
	assert_true(second.is_reachable)
	assert_false(excluded.is_reachable)
	assert_eq(_hud.current_status.text, "【艺径寻踪】请选择移动终点")
	assert_eq(_hud.information.text, request.source_description)
	assert_true(_hud.btn_action.disabled)
	assert_true(_hud.btn_food.disabled)
	assert_true(_hud.btn_end_turn.disabled)

	assert_eq(await _hud.map._on_section_clicked(second), "event choice")
	assert_false(EventManager._choice_waiting)
	assert_eq(EventManager._pending_choice, second)
	assert_false(_hud.map.is_event_section_choice_active())
	assert_false(first.is_reachable)
	assert_false(second.is_reachable)


func test_forced_grid_choice_timeout_submits_first_ordered_destination_and_clears_map_mode() -> void:
	var unique_sections: Array[MapSection] = []
	for section: MapSection in _hud.map.grid_map.values():
		if not unique_sections.has(section):
			unique_sections.append(section)
		if unique_sections.size() == 2:
			break
	assert_eq(unique_sections.size(), 2)
	if unique_sections.size() < 2:
		return
	var first := unique_sections[0]
	var second := unique_sections[1]
	var request := EventChoiceRequest.new(
		_player,
		"选择移动终点",
		[first, second],
		PackedStringArray([first.section_name, second.section_name]),
		false,
		EventChoiceRequest.ChoiceKind.格子
	)
	request.request_id = 902
	request.source_name = "日行千里"
	EventManager._pending_request = request
	EventManager._pending_choice = null
	EventManager._choice_waiting = true
	EventManager._choice_timer.start(15.0)
	EventManager.choice_requested.emit(request)

	EventManager._on_choice_timeout()
	await get_tree().process_frame

	assert_eq(EventManager._pending_choice, first, "强制地图选择超时应执行原选项顺序的第一处终点")
	assert_false(_hud.map.is_event_section_choice_active())
	assert_false(first.is_reachable)
	assert_false(second.is_reachable)


func test_player_choice_highlights_target_tiles_and_submits_the_clicked_player() -> void:
	var unique_sections: Array[MapSection] = []
	for section: MapSection in _hud.map.grid_map.values():
		if not unique_sections.has(section):
			unique_sections.append(section)
		if unique_sections.size() == 2:
			break
	assert_eq(unique_sections.size(), 2)
	if unique_sections.size() < 2:
		return
	_player.now_pos = unique_sections[0].location_index
	var target := PlayerClass.new()
	target.player_name = "目标玩家"
	target.player_index = 1
	target.now_pos = unique_sections[1].location_index
	var target_score := Label.new()
	target.add_child(target_score)
	target.score_label = target_score
	autofree(target)
	TurnManager.players.append(target)
	TurnManager.player_num = 2
	var request := EventChoiceRequest.new(
		_player,
		"选择一名玩家",
		[target, _player],
		PackedStringArray([target.player_name, _player.player_name]),
		false,
		EventChoiceRequest.ChoiceKind.玩家
	)
	request.request_id = 903
	request.presentation = EventChoiceRequest.Presentation.地图
	request.source_name = "交换人生"
	request.source_description = "与一名玩家交换职业。"
	EventManager._pending_request = request
	EventManager._pending_choice = null
	EventManager._choice_waiting = true
	EventManager._choice_timer.start(15.0)

	EventManager.choice_requested.emit(request)
	await get_tree().process_frame

	assert_false(_hud.event_overlay.visible, "玩家目标不应继续显示机械按钮列表")
	assert_true(unique_sections[0].is_reachable)
	assert_true(unique_sections[1].is_reachable)
	assert_eq(_hud.current_status.text, "【交换人生】请选择玩家")
	assert_eq(await _hud.map._on_section_clicked(unique_sections[1]), "event choice")
	assert_eq(EventManager._pending_choice, target)
	assert_false(_hud.map.is_event_section_choice_active())


func test_multiple_player_map_choice_waits_until_all_required_players_are_selected() -> void:
	var unique_sections: Array[MapSection] = []
	for section: MapSection in _hud.map.grid_map.values():
		if not unique_sections.has(section):
			unique_sections.append(section)
		if unique_sections.size() == 3:
			break
	assert_eq(unique_sections.size(), 3)
	if unique_sections.size() < 3:
		return
	_player.now_pos = unique_sections[0].location_index
	var first_target := PlayerClass.new()
	first_target.player_name = "第一名玩家"
	first_target.now_pos = unique_sections[1].location_index
	autofree(first_target)
	var second_target := PlayerClass.new()
	second_target.player_name = "第二名玩家"
	second_target.now_pos = unique_sections[2].location_index
	autofree(second_target)
	var request := EventChoiceRequest.new(
		_player,
		"坐收渔利：选择两名打工者",
		[first_target, second_target, _player],
		PackedStringArray([first_target.player_name, second_target.player_name, _player.player_name]),
		false,
		EventChoiceRequest.ChoiceKind.玩家
	)
	request.request_id = 904
	request.presentation = EventChoiceRequest.Presentation.地图
	request.multiple = true
	request.min_selections = 2
	request.max_selections = 2
	request.source_name = "坐收渔利"
	EventManager._pending_request = request
	EventManager._pending_choice = []
	EventManager._choice_waiting = true
	EventManager._choice_timer.start(15.0)
	EventManager.choice_requested.emit(request)
	await get_tree().process_frame

	assert_eq(await _hud.map._on_section_clicked(unique_sections[1]), "event choice")
	assert_true(EventManager._choice_waiting, "选择第一名玩家后不能提前提交")
	assert_eq(EventManager._pending_choice, [first_target])
	assert_true(_hud.map.is_event_section_choice_active())
	assert_eq(_hud.current_status.text, "【坐收渔利】请选择玩家 1/2")

	assert_eq(await _hud.map._on_section_clicked(unique_sections[2]), "event choice")
	assert_false(EventManager._choice_waiting)
	assert_eq(EventManager._pending_choice, [first_target, second_target])
	assert_false(_hud.map.is_event_section_choice_active())


func test_no_effect_event_appends_message_to_information_bar() -> void:
	_hud.information.text = "【日行千里】结算完成。"
	EventManager.event_finished.emit(_player, load("res://Cards/事件牌/日行千里.tres") as 事件牌, "事件【日行千里】：无事发生！")
	assert_true(_hud.information.text.ends_with("无事发生！"))


func test_hand_gain_starts_card_back_flight_on_the_shared_animation_layer() -> void:
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	watch_signals(_hud.card_hand_animator)

	assert_true(ResourceManager.add_event_card(_player, card))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emitted(_hud.card_hand_animator, "animation_started")
	assert_gt(_hud.card_hand_animator.get_child_count(), 0)
	var visual := _hud.card_hand_animator.get_child(0) as TextureRect
	assert_not_null(visual)
	if visual != null:
		assert_eq(visual.texture, card.image_of_back)
	assert_null(_hud.feiyi_list.get_node_or_null("事件牌列表区"), "首张事件牌飞行期间不得抢先显示分类标题")
	assert_true(await _wait_until(func() -> bool: return not _hud.card_hand_animator.is_busy(), 2.0))
	assert_not_null(_hud.feiyi_list.get_node_or_null("事件牌列表区"))


func test_hand_loss_uses_upward_irregular_dissolve_shader() -> void:
	var card := load("res://Cards/非遗牌/鄂州/鄂州雕花剪纸.tres") as 非遗牌
	_player.非遗牌手牌.append(card)
	_hud.refresh_feiyi_list(_player)

	assert_true(ResourceManager.remove_feiyi_card(_player, card))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_gt(_hud.card_hand_animator.get_child_count(), 0)
	var visual := _hud.card_hand_animator.get_child(0) as TextureRect
	assert_not_null(visual)
	if visual != null:
		assert_true(visual.material is ShaderMaterial)
		assert_eq((visual.material as ShaderMaterial).shader, CardHandAnimator.DISSOLVE_SHADER)
		assert_eq(visual.texture, card.image_of_front, "失去动画必须使用具体卡牌正面")
		assert_true(visual.size.is_equal_approx(CardHandAnimator.CARD_SIZE), "消失牌面应与右侧缩略图使用同级尺寸")
		assert_eq(visual.scale, Vector2.ONE)


func test_collected_feiyi_city_header_waits_for_animation_and_detail_close() -> void:
	var card := load("res://Cards/非遗牌/随州/花鼓戏.tres") as 非遗牌
	assert_true(ResourceManager.add_feiyi_card(_player, card, true, true))
	await get_tree().process_frame
	assert_false(_has_label_text("== 随州 =="), "新城市标题不得在获得动画前出现")
	assert_true(await _wait_until(func() -> bool: return _hud.detail_panel.visible, 2.0))
	assert_true(_hud.card_hand_animator.is_busy(), "介绍弹窗关闭前获得流程仍应处于展示中")
	assert_false(_has_label_text("== 随州 =="), "介绍弹窗显示期间仍不得提前出现城市标题")
	_hud.detail_panel.close_detail()
	assert_true(await _wait_until(func() -> bool: return not _hud.card_hand_animator.is_busy(), 1.0))
	assert_true(_has_label_text("== 随州 =="))


func test_jian_wang_uses_market_panel_and_finishes_after_the_hand_animation_queue_is_idle() -> void:
	var inventory_card := load("res://Cards/非遗牌/鄂州/牌子锣.tres") as 非遗牌
	MarketManager.deposit_card(inventory_card, &"test")
	var event_card := load("res://Cards/事件牌/鉴往知来.tres") as 事件牌
	_async_done = false
	_run_event(event_card)
	assert_true(await _wait_until(func() -> bool: return _hud.event_overlay._active_request != null))
	EventManager.submit_choice(_hud.event_overlay._active_request.request_id, true)
	assert_true(await _wait_until(func() -> bool: return _hud.market_overlay.is_event_choice_open()))
	assert_false(_hud.event_overlay.visible)
	assert_eq(TurnManager.modal_resolution_depth, 1, "事件复用研究所弹窗时不得重复占用模态层")
	assert_eq(_hud.market_overlay._event_cards.size(), 1)
	assert_eq(_hud.market_overlay.card_grid.get_child_count(), 1)
	_hud.market_overlay._select_event_card(inventory_card)

	assert_true(await _wait_until(func() -> bool: return _async_done, 2.0), "鉴往知来不得在最后一张手牌动画后永久等待")
	assert_false(_hud.market_overlay.visible)
	assert_false(EventManager.resolving)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_true(_player.非遗牌手牌.has(inventory_card))
	assert_false(MarketManager.get_inventory().has(inventory_card))
	assert_true(ResourceManager.事件弃牌堆.has(event_card))


func test_retainable_event_gain_also_releases_the_event_after_the_animation_queue_finishes() -> void:
	var event_card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	_async_done = false
	_run_event(event_card)
	assert_true(await _wait_until(func() -> bool: return _hud.event_overlay._active_request != null))
	EventManager.submit_choice(_hud.event_overlay._active_request.request_id, true)

	assert_true(await _wait_until(func() -> bool: return _async_done, 2.0))
	assert_true(_player.事件牌手牌.has(event_card))
	assert_false(_hud.event_overlay.visible)
	assert_false(EventManager.resolving)
	assert_eq(TurnManager.modal_resolution_depth, 0)


func test_clearing_the_animation_queue_wakes_shared_waiters() -> void:
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	assert_true(ResourceManager.add_event_card(_player, card))
	_hand_wait_done = false
	_run_hand_wait()
	await get_tree().process_frame
	assert_true(_hud.card_hand_animator.is_busy())
	_hud.card_hand_animator.clear_queue()
	assert_true(await _wait_until(func() -> bool: return _hand_wait_done))
	assert_false(_hud.card_hand_animator.is_busy())


func test_standalone_hand_animation_pauses_and_resumes_original_phase_time() -> void:
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	TurnManager.turn_timer.start(8.0)

	assert_true(ResourceManager.add_event_card(_player, card))
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_eq(TurnManager.modal_resolution_depth, 1)
	await _hud.card_hand_animator.animation_finished
	await get_tree().process_frame

	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_gt(TurnManager.turn_timer.time_left, 7.0)
	assert_lte(TurnManager.turn_timer.time_left, 8.0)


func test_hand_animation_keeps_its_own_lease_inside_an_existing_modal() -> void:
	var card := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	TurnManager.turn_timer.start(8.0)
	var outer_lease := TurnManager.acquire_modal(
		&"animation_outer_event",
		TurnManager.ModalResumePolicy.RESUME_REMAINING
	)

	assert_true(ResourceManager.add_event_card(_player, card))
	assert_eq(TurnManager.modal_resolution_depth, 2, "外层结算与手牌动画必须各自持有租约")
	assert_true(TurnManager.release_modal(outer_lease))
	assert_eq(TurnManager.modal_resolution_depth, 1)
	assert_true(TurnManager.turn_timer.is_stopped(), "外层先结束时，动画租约仍须阻止阶段计时恢复")

	await _hud.card_hand_animator.animation_finished
	await get_tree().process_frame
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_gt(TurnManager.turn_timer.time_left, 7.0)


func _run_event(card: 事件牌) -> void:
	await EventManager.resolve_event(_player, card)
	_async_done = true


func _run_hand_wait() -> void:
	await _hud.wait_for_card_hand_animations()
	_hand_wait_done = true


func _wait_until(predicate: Callable, max_seconds: float = 0.5) -> bool:
	var deadline_msec := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _has_label_text(expected: String) -> bool:
	for child: Node in _hud.feiyi_list.get_children():
		if child is Label and (child as Label).text == expected:
			return true
	return false
