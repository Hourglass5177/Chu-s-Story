extends GutTest

const HUD_SCENE := preload("res://HUDs/HUD.tscn")

var _viewport: SubViewport
var _hud: HUD
var _player: PlayerClass
var _press_count := 0
var _players_backup: Array[PlayerClass] = []
var _turn_state_backup: Dictionary = {}
var _paused_backup := false


func before_each() -> void:
	_press_count = 0
	_players_backup.assign(TurnManager.players)
	_turn_state_backup = {
		"player_num": TurnManager.player_num,
		"now_player_index": TurnManager.now_player_index,
		"now_phase": TurnManager.now_phase,
		"now_turn": TurnManager.now_turn,
		"game_on": TurnManager.GameOn,
		"hud": TurnManager.hud,
		"map": TurnManager.map,
	}
	_paused_backup = get_tree().paused
	get_tree().paused = false
	InteractionCoordinator.cancel_all(&"hud_pointer_test_setup")
	TurnManager.invalidate_all_modals(&"hud_pointer_test_setup")
	TurnManager.turn_timer.stop()

	_player = PlayerClass.new()
	_player.player_name = "指针测试玩家"
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

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(2560, 1600)
	_viewport.gui_disable_input = false
	add_child_autofree(_viewport)
	_hud = HUD_SCENE.instantiate() as HUD
	_viewport.add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	TurnManager.hud = _hud
	TurnManager.map = _hud.map
	if _hud.map != null and not _hud.map.grid_map.is_empty():
		_player.now_pos = _hud.map.grid_map.keys()[0]


func after_each() -> void:
	get_tree().paused = false
	InteractionCoordinator.cancel_all(&"hud_pointer_test_teardown")
	TurnManager.invalidate_all_modals(&"hud_pointer_test_teardown")
	TurnManager.turn_timer.stop()
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = int(_turn_state_backup["player_num"])
	TurnManager.now_player_index = int(_turn_state_backup["now_player_index"])
	TurnManager.now_phase = int(_turn_state_backup["now_phase"])
	TurnManager.now_turn = int(_turn_state_backup["now_turn"])
	TurnManager.GameOn = bool(_turn_state_backup["game_on"])
	TurnManager.hud = _turn_state_backup["hud"] as HUD
	TurnManager.map = _turn_state_backup["map"] as MAP
	if is_instance_valid(_player):
		_player.free()
	get_tree().paused = _paused_backup


func test_normal_hud_button_accepts_a_real_pointer_click() -> void:
	assert_false(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)
	var food_button := _hud.get_node("操作区域/BtnFood") as Button
	food_button.pressed.connect(_count_press)
	assert_same(await _real_pointer_click(food_button), food_button)
	assert_eq(_press_count, 1, "正常游戏状态下，顶层隐藏界面不得截走 HUD 按钮点击")
	assert_true(_hud.backpack_panel.visible, "真实点击应打开食物背包，而不只是触发测试回调")
	var close_button := _hud.backpack_panel.get_node("BtnClose") as TextureButton
	assert_same(await _real_pointer_click(close_button), close_button)
	assert_false(_hud.backpack_panel.visible)


func test_top_controls_have_three_separate_real_pointer_targets() -> void:
	for node_path in ["BtnGuide", "BtnPause", "BtnClose"]:
		var button := _hud.get_node(node_path) as TextureButton
		assert_same(await _real_pointer_hover(button), button, "%s 的实际命中区域不得被相邻按钮覆盖" % node_path)


func test_pointer_exit_clears_top_button_mask_even_when_button_keeps_focus() -> void:
	var guide_button := _hud.get_node("BtnGuide") as TextureButton
	var pause_button := _hud.get_node("BtnPause") as TextureButton
	var guide_mask := guide_button.get_node("mask") as TextureRect
	guide_button.grab_focus()
	await get_tree().process_frame

	assert_same(await _real_pointer_hover(guide_button), guide_button)
	assert_true(guide_mask.visible)
	assert_same(await _real_pointer_hover(pause_button), pause_button)
	assert_false(guide_mask.visible, "鼠标离开后不得因点击遗留的键盘焦点继续显示暗色遮罩")


func test_pause_round_trip_restores_normal_hud_pointer_input() -> void:
	var pause_button := _hud.get_node("BtnPause") as TextureButton
	assert_same(await _real_pointer_click(pause_button), pause_button)
	assert_true(_hud.pause_overlay.visible)
	assert_true(get_tree().paused)

	var continue_button := _hud.pause_overlay.get_node("Center/Panel/Margin/Content/ContinueButton") as Button
	assert_same(await _real_pointer_click(continue_button), continue_button)
	assert_false(_hud.pause_overlay.visible)
	assert_false(get_tree().paused)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _real_pointer_click(view_button), view_button)
	assert_eq(_press_count, 1, "暂停关闭后必须恢复普通 HUD 的鼠标命中")


func test_uncovered_map_choice_keeps_pause_button_available() -> void:
	var existing_lease := TurnManager.acquire_modal(&"pointer_test_map_choice", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	var pause_button := _hud.get_node("BtnPause") as TextureButton

	assert_same(await _real_pointer_click(pause_button), pause_button)
	assert_true(_hud.pause_overlay.visible, "地图选点没有遮罩，暂停按钮应保持可用")
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	assert_true(_hud.pause_overlay.close_pause())
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 1, "关闭暂停后应保留地图选点状态")
	assert_true(TurnManager.release_modal(existing_lease))


func test_secondary_overlay_masks_pause_and_close_at_the_same_layer() -> void:
	var pause_button := _hud.get_node("BtnPause") as TextureButton
	var close_button := _hud.get_node("BtnClose") as TextureButton
	_hud.event_overlay.show()
	await get_tree().process_frame

	assert_ne(await _real_pointer_hover(pause_button), pause_button, "二级弹窗遮罩应盖住暂停按钮")
	assert_ne(await _real_pointer_hover(close_button), close_button, "暂停与关闭按钮应受同一遮罩层级约束")
	await _real_pointer_click(pause_button)
	assert_false(_hud.pause_overlay.visible, "被二级弹窗遮住时不能穿透打开暂停")

	_hud.event_overlay.hide()


func test_guide_round_trip_restores_normal_hud_pointer_input() -> void:
	var guide_button := _hud.get_node("BtnGuide") as TextureButton
	assert_same(await _real_pointer_click(guide_button), guide_button)
	assert_true(_hud.game_guide.is_guide_open())

	var close_button := _hud.game_guide.get_node("SafeArea/Frame/Layout/Header/CloseButton") as Button
	assert_same(await _real_pointer_click(close_button), close_button)
	await get_tree().process_frame
	assert_false(_hud.game_guide.is_guide_open())
	assert_false(get_tree().paused)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _real_pointer_click(view_button), view_button)
	assert_eq(_press_count, 1, "指南关闭后必须恢复普通 HUD 的鼠标命中")


func test_backpack_round_trip_releases_pause_modal_and_pointer_blocker() -> void:
	_hud.backpack_panel.open_backpack(_player)
	assert_true(_hud.backpack_panel.visible)
	assert_true(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 1)

	var close_button := _hud.backpack_panel.get_node("BtnClose") as TextureButton
	assert_same(await _real_pointer_click(close_button), close_button)
	assert_false(_hud.backpack_panel.visible)
	assert_false(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _real_pointer_click(view_button), view_button)
	assert_eq(_press_count, 1, "背包关闭后不得残留透明遮罩或暂停状态")


func _count_press() -> void:
	_press_count += 1


func _real_pointer_click(control: Control) -> Control:
	var hovered := await _real_pointer_hover(control)
	var click_position := control.get_global_rect().get_center()
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = click_position
	pressed.global_position = click_position
	pressed.pressed = true
	_viewport.push_input(pressed, false)
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = click_position
	released.global_position = click_position
	released.pressed = false
	_viewport.push_input(released, false)
	await get_tree().process_frame
	return hovered


func _real_pointer_hover(control: Control) -> Control:
	var click_position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click_position
	motion.global_position = click_position
	_viewport.push_input(motion, false)
	await get_tree().process_frame
	return _viewport.gui_get_hovered_control()
