extends GutTest

const HUD_SCENE := preload("res://HUDs/HUD.tscn")
const REAL_POINTER_DRIVER := preload("res://tests/helpers/real_pointer_driver.gd")

var _viewport: SubViewport
var _hud: HUD
var _player: PlayerClass
var _pointer
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
	_pointer = REAL_POINTER_DRIVER.new(_viewport, get_tree())
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
	assert_same(await _pointer.click(food_button), food_button)
	assert_eq(_press_count, 1, "正常游戏状态下，顶层隐藏界面不得截走 HUD 按钮点击")
	assert_true(_hud.backpack_panel.visible, "真实点击应打开食物背包，而不只是触发测试回调")
	var close_button := _hud.backpack_panel.get_node("BtnClose") as TextureButton
	assert_same(await _pointer.click(close_button), close_button)
	assert_false(_hud.backpack_panel.visible)


func test_top_controls_have_three_separate_real_pointer_targets() -> void:
	for node_path in ["BtnGuide", "BtnPause", "BtnClose"]:
		var button := _hud.get_node(node_path) as TextureButton
		assert_same(await _pointer.hover(button), button, "%s 的实际命中区域不得被相邻按钮覆盖" % node_path)


func test_pointer_exit_clears_top_button_mask_even_when_button_keeps_focus() -> void:
	var guide_button := _hud.get_node("BtnGuide") as TextureButton
	var pause_button := _hud.get_node("BtnPause") as TextureButton
	var guide_mask := guide_button.get_node("mask") as TextureRect
	guide_button.grab_focus()
	await get_tree().process_frame

	assert_same(await _pointer.hover(guide_button), guide_button)
	assert_true(guide_mask.visible)
	assert_same(await _pointer.hover(pause_button), pause_button)
	assert_false(guide_mask.visible, "鼠标离开后不得因点击遗留的键盘焦点继续显示暗色遮罩")


func test_pause_round_trip_restores_normal_hud_pointer_input() -> void:
	var pause_button := _hud.get_node("BtnPause") as TextureButton
	assert_same(await _pointer.click(pause_button), pause_button)
	assert_true(_hud.pause_overlay.visible)
	assert_true(get_tree().paused)

	var continue_button := _hud.pause_overlay.get_node("Center/Panel/Margin/Content/ContinueButton") as Button
	assert_same(await _pointer.click(continue_button), continue_button)
	assert_false(_hud.pause_overlay.visible)
	assert_false(get_tree().paused)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _pointer.click(view_button), view_button)
	assert_eq(_press_count, 1, "暂停关闭后必须恢复普通 HUD 的鼠标命中")


func test_uncovered_map_choice_keeps_pause_button_available() -> void:
	var existing_lease := TurnManager.acquire_modal(&"pointer_test_map_choice", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	var pause_button := _hud.get_node("BtnPause") as TextureButton

	assert_same(await _pointer.click(pause_button), pause_button)
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

	assert_ne(await _pointer.hover(pause_button), pause_button, "二级弹窗遮罩应盖住暂停按钮")
	assert_ne(await _pointer.hover(close_button), close_button, "暂停与关闭按钮应受同一遮罩层级约束")
	await _pointer.click(pause_button)
	assert_false(_hud.pause_overlay.visible, "被二级弹窗遮住时不能穿透打开暂停")

	_hud.event_overlay.hide()


func test_guide_round_trip_restores_normal_hud_pointer_input() -> void:
	var guide_button := _hud.get_node("BtnGuide") as TextureButton
	assert_same(await _pointer.click(guide_button), guide_button)
	assert_true(_hud.game_guide.is_guide_open())

	var close_button := _hud.game_guide.get_node("SafeArea/Frame/Layout/Header/CloseButton") as Button
	assert_same(await _pointer.click(close_button), close_button)
	await get_tree().process_frame
	assert_false(_hud.game_guide.is_guide_open())
	assert_false(get_tree().paused)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _pointer.click(view_button), view_button)
	assert_eq(_press_count, 1, "指南关闭后必须恢复普通 HUD 的鼠标命中")


func test_backpack_round_trip_releases_pause_modal_and_pointer_blocker() -> void:
	_hud.backpack_panel.open_backpack(_player)
	assert_true(_hud.backpack_panel.visible)
	assert_true(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 1)

	var close_button := _hud.backpack_panel.get_node("BtnClose") as TextureButton
	assert_same(await _pointer.click(close_button), close_button)
	assert_false(_hud.backpack_panel.visible)
	assert_false(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)

	var view_button := _hud.get_node("地图/BtnViewToggle") as TextureButton
	view_button.pressed.connect(_count_press)
	assert_same(await _pointer.click(view_button), view_button)
	assert_eq(_press_count, 1, "背包关闭后不得残留透明遮罩或暂停状态")


func test_detail_popups_release_only_their_own_modal_lease() -> void:
	var outer_lease := TurnManager.acquire_modal(
		&"hud_pointer_outer_modal",
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		true
	)

	_hud.score_overlay.open_for_player(_player)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	_hud.score_overlay.close_panel()
	_assert_outer_modal_remains(outer_lease, "计分详情")

	var achievement := load("res://Cards/成就牌/超越人类.tres") as 成就牌
	_hud.achievement_detail_overlay.show_detail(achievement)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	_hud.achievement_detail_overlay.close_panel()
	_assert_outer_modal_remains(outer_lease, "成就详情")

	var feiyi := load("res://Cards/非遗牌/十堰/汉调二黄.tres") as 非遗牌
	_hud.detail_panel.show_detail(feiyi, _player)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	_hud.detail_panel.close_detail()
	_assert_outer_modal_remains(outer_lease, "非遗详情")

	var retained_event := load("res://Cards/事件牌/畅行无阻.tres") as 事件牌
	_hud.event_overlay.show_retained_card_detail(_player, retained_event)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 2)
	_hud.event_overlay.close_retained_card_detail()
	_assert_outer_modal_remains(outer_lease, "保留事件详情")

	assert_true(TurnManager.release_modal(outer_lease), "外层租约必须仍可由原所有者精确释放")
	assert_false(get_tree().paused, "最后一个树暂停租约释放后必须恢复进入模态前的状态")


func test_shop_keeps_and_releases_its_exact_modal_lease() -> void:
	var food_deck_backup: Array[食物牌] = []
	food_deck_backup.assign(ResourceManager.食物牌库)
	var shop := _hud.get_node("商店弹窗") as 商店弹窗
	shop.open_shop(_player)
	var shop_lease := int(shop.get("_modal_lease"))
	assert_gt(shop_lease, 0, "商店必须保存 acquire_modal 返回的实际令牌")
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", 0)), 1)
	var nested_lease := TurnManager.acquire_modal(
		&"hud_pointer_nested_modal",
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		true
	)
	shop._on_leave()
	var nested_snapshot := TurnManager.get_modal_snapshot()
	assert_eq(int(nested_snapshot.get("depth", 0)), 1, "商店关闭不得释放后开启的嵌套租约")
	assert_eq(int(nested_snapshot.get("tree_pause_depth", 0)), 1, "商店关闭后嵌套租约仍应持有树暂停")
	assert_true(nested_snapshot.get("tree_pause_owners", []).has(&"hud_pointer_nested_modal"))
	assert_true(get_tree().paused, "嵌套模态仍存在时商店不得解除整棵树暂停")
	assert_true(TurnManager.release_modal(nested_lease))
	var released_snapshot := TurnManager.get_modal_snapshot()
	assert_eq(int(released_snapshot.get("tree_pause_depth", -1)), 0)
	assert_false(bool(released_snapshot.get("tree_paused", true)))
	assert_false(get_tree().paused, "最后一个嵌套树暂停租约释放后应自动恢复")
	ResourceManager.食物牌库.assign(food_deck_backup)


func _count_press() -> void:
	_press_count += 1


func _assert_outer_modal_remains(outer_lease: int, popup_name: String) -> void:
	assert_eq(
		int(TurnManager.get_modal_snapshot().get("depth", 0)),
		1,
		"%s 关闭后必须保留外层模态" % popup_name
	)
	assert_true(get_tree().paused, "%s 关闭后不得解除外层暂停" % popup_name)
	assert_eq(int(TurnManager.get_modal_snapshot().get("tree_pause_depth", 0)), 1)
	assert_true(
		TurnManager.get_modal_snapshot().get("owners", []).has(&"hud_pointer_outer_modal"),
		"%s 不得误删外层租约 %d" % [popup_name, outer_lease]
	)
