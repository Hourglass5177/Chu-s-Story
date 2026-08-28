extends GutTest

const MAIN_MENU_SCENE: PackedScene = preload("res://main_menu.tscn")
const REAL_POINTER_DRIVER := preload("res://tests/helpers/real_pointer_driver.gd")
const STABLE_SCREENS: Array[StringName] = [
	&"home",
	&"mode",
	&"local_count",
	&"player_setup",
	&"roster",
	&"loading",
]
const SCREEN_NODE_NAMES: Dictionary[StringName, StringName] = {
	&"home": &"HomePage",
	&"mode": &"ModePage",
	&"local_count": &"LocalCountPage",
	&"player_setup": &"PlayerSetupPage",
	&"roster": &"RosterPage",
	&"loading": &"LoadingPage",
}


class FakeSessionLauncher:
	extends FrontendSessionLauncher

	var prepare_result: Error = OK
	var scene_result: Error = OK
	var prepare_calls := 0
	var scene_calls := 0
	var rollback_calls := 0
	var prepare_frame := -1
	var received_setup: SessionSetup

	func prepare_local_session(setup: SessionSetup) -> Error:
		prepare_calls += 1
		prepare_frame = Engine.get_process_frames()
		received_setup = setup.duplicate_snapshot()
		return prepare_result

	func change_to_game_scene(_tree: SceneTree, _scene_path: String) -> Error:
		scene_calls += 1
		return scene_result

	func rollback_session() -> void:
		rollback_calls += 1

var _menu: Control
var _paused_backup := false


func before_each() -> void:
	_paused_backup = get_tree().paused
	_menu = MAIN_MENU_SCENE.instantiate() as Control
	add_child_autofree(_menu)


func after_each() -> void:
	get_tree().paused = _paused_backup


func test_main_menu_recovers_from_a_paused_scene_tree() -> void:
	# SceneTree.paused 会跨场景保留；主菜单必须始终是可操作的恢复边界。
	get_tree().paused = true
	var paused_menu := MAIN_MENU_SCENE.instantiate() as Control
	add_child_autofree(paused_menu)
	assert_false(get_tree().paused)
	assert_eq(paused_menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(paused_menu.call(&"get_current_screen"), &"home")
	var start_button := _find_button(_get_screen_from(paused_menu, &"home"), "开始游戏")
	assert_not_null(start_button)
	if start_button != null:
		start_button.pressed.emit()
		assert_eq(paused_menu.call(&"get_current_screen"), &"mode")


func test_legacy_controls_cannot_intercept_the_frontend() -> void:
	var background := _menu.get_node_or_null("Background") as Control
	assert_not_null(background)
	assert_eq(background.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for node_name: String in ["MainButtons", "SettingsPanel", "CreditsPanel"]:
		var legacy := _menu.get_node_or_null(node_name) as Control
		assert_not_null(legacy)
		if legacy != null:
			assert_false(legacy.visible)
			assert_eq(legacy.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_null(_menu.get_node_or_null("RulesPanel"), "过期长文本说明子树应从场景中移除")
	var shell := _menu.get_node_or_null("FrontendShell") as Control
	assert_not_null(shell)
	assert_eq(shell.z_index, 100)


func test_home_start_button_accepts_a_real_pointer_click() -> void:
	# GUT 自身也有全屏 UI；使用独立 Viewport 才能验证游戏界面的真实命中顺序。
	var isolated_viewport := SubViewport.new()
	isolated_viewport.size = Vector2i(2560, 1600)
	isolated_viewport.gui_disable_input = false
	add_child_autofree(isolated_viewport)
	var isolated_menu := MAIN_MENU_SCENE.instantiate() as Control
	isolated_viewport.add_child(isolated_menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var pointer = REAL_POINTER_DRIVER.new(isolated_viewport, get_tree())
	var start_button := _find_button(_get_screen_from(isolated_menu, &"home"), "开始游戏")
	assert_not_null(start_button)
	if start_button == null:
		return
	assert_same(await pointer.click(start_button), start_button, "开始按钮必须一次真实点击生效")
	assert_eq(isolated_menu.call(&"get_current_screen"), &"mode")

	var local_card := _find_card(_get_screen_from(isolated_menu, &"mode"), "本地游戏")
	assert_not_null(local_card)
	if local_card == null:
		return
	assert_same(await pointer.click(local_card), local_card, "页面切换后的本地游戏卡片也必须一次点击生效")
	assert_eq(isolated_menu.call(&"get_current_screen"), &"local_count")


func test_scene_exposes_the_stable_frontend_contract() -> void:
	for method_name: StringName in [
		&"get_current_screen",
		&"get_draft_snapshot",
		&"set_local_player_counts",
		&"set_target_score",
		&"show_screen",
		&"request_mode",
		&"request_start_once",
		&"open_game_guide",
		&"get_game_guide",
	]:
		assert_true(_menu.has_method(method_name), "主菜单缺少公开方法 %s" % method_name)
	assert_true(_menu.has_signal(&"mode_requested"))
	assert_true(_menu.has_signal(&"local_setup_confirmed"))


func test_all_stable_screens_can_be_selected_without_deep_node_paths() -> void:
	if not _has_methods([&"get_current_screen", &"show_screen"]):
		return
	assert_eq(_menu.call(&"get_current_screen"), &"home")
	assert_false(bool(_menu.call(&"show_screen", &"unknown")))
	assert_eq(_menu.call(&"get_current_screen"), &"home", "非法页面名不得破坏当前页面")

	for screen_name: StringName in STABLE_SCREENS:
		assert_true(bool(_menu.call(&"show_screen", screen_name)), "页面 %s 应可由前端壳层展示" % screen_name)
		assert_eq(_menu.call(&"get_current_screen"), screen_name)


func test_mode_requests_use_one_signal_and_placeholders_stay_on_mode_screen() -> void:
	if not _has_methods([&"show_screen", &"request_mode", &"get_current_screen"]) \
			or not _menu.has_signal(&"mode_requested"):
		return
	_menu.call(&"show_screen", &"mode")
	watch_signals(_menu)
	var requested_modes: Array[int] = []
	_menu.connect(&"mode_requested", func(mode: int) -> void: requested_modes.append(mode))

	assert_true(bool(_menu.call(&"request_mode", SessionSetup.GameMode.NETWORK)))
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	assert_true(bool(_menu.call(&"request_mode", SessionSetup.GameMode.TUTORIAL)))
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	assert_eq(requested_modes, [SessionSetup.GameMode.NETWORK, SessionSetup.GameMode.TUTORIAL])
	assert_signal_emit_count(_menu, "mode_requested", 2)


func test_local_mode_enters_the_count_screen() -> void:
	if not _has_methods([&"show_screen", &"request_mode", &"get_current_screen"]) \
			or not _menu.has_signal(&"mode_requested"):
		return
	_menu.call(&"show_screen", &"mode")
	watch_signals(_menu)

	assert_true(bool(_menu.call(&"request_mode", SessionSetup.GameMode.LOCAL)))
	assert_eq(_menu.call(&"get_current_screen"), &"local_count")
	assert_signal_emitted_with_parameters(
		_menu,
		"mode_requested",
		[SessionSetup.GameMode.LOCAL],
	)


func test_player_count_boundaries_and_bot_defaults_are_visible_through_the_snapshot() -> void:
	if not _has_methods([&"set_local_player_counts", &"get_draft_snapshot"]):
		return
	assert_true(bool(_menu.call(&"set_local_player_counts", 1, 0)))
	var solo: SessionSetup = _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_not_null(solo)
	assert_eq(solo.human_count, 1)
	assert_eq(solo.bot_count, 0)
	assert_eq(solo.players.size(), 1)
	assert_eq(solo.players[0].control_kind, PlayerSetup.ControlKind.HUMAN)

	assert_false(bool(_menu.call(&"set_local_player_counts", 0, 1)))
	assert_false(bool(_menu.call(&"set_local_player_counts", 1, 6)))
	var after_invalid: SessionSetup = _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(after_invalid.human_count, 1, "非法人数不得污染现有草稿")
	assert_eq(after_invalid.bot_count, 0)

	assert_true(bool(_menu.call(&"set_local_player_counts", 1, 5)))
	var full: SessionSetup = _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(full.players.size(), SessionSetup.MAX_PLAYERS)
	for index: int in range(1, full.players.size()):
		var bot: PlayerSetup = full.players[index]
		assert_eq(bot.control_kind, PlayerSetup.ControlKind.BOT)
		assert_eq(bot.display_name, "电脑%d" % index)
		assert_true(bot.has_valid_profession())
		assert_true(bot.has_valid_starting_region())


func test_target_score_selection_is_preserved_in_the_frontend_snapshot() -> void:
	assert_true(bool(_menu.call(&"set_target_score", 30)))
	assert_eq((_menu.call(&"get_draft_snapshot") as SessionSetup).target_score, 30)
	assert_false(bool(_menu.call(&"set_target_score", 18)))
	assert_eq((_menu.call(&"get_draft_snapshot") as SessionSetup).target_score, 30)


func test_target_score_only_change_requires_discard_confirmation() -> void:
	_menu.call(&"show_screen", &"mode", false)
	assert_true(bool(_menu.call(&"set_target_score", 30)))
	var home_back := _find_button(_get_screen(&"mode"), "返回")
	assert_not_null(home_back)
	home_back.pressed.emit()
	var modal := _find_named_control("ModalLayer")
	assert_true(modal.visible)
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	await get_tree().process_frame
	var discard := _find_button(modal, "放弃")
	assert_not_null(discard)
	discard.pressed.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"home")
	assert_eq((_menu.call(&"get_draft_snapshot") as SessionSetup).target_score, SessionSetup.DEFAULT_TARGET_SCORE)


func test_draft_getter_returns_an_independent_snapshot() -> void:
	if not _has_methods([&"set_local_player_counts", &"get_draft_snapshot"]):
		return
	_menu.call(&"set_local_player_counts", 1, 1)
	var first: SessionSetup = _menu.call(&"get_draft_snapshot") as SessionSetup
	first.players[0].display_name = "不应写回"
	first.players.clear()

	var second: SessionSetup = _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(second.players.size(), 2)
	assert_ne(second.players[0].display_name, "不应写回")


func test_incomplete_and_repeated_start_requests_never_confirm_a_session() -> void:
	if not _has_methods([&"set_local_player_counts", &"request_start_once"]) \
			or not _menu.has_signal(&"local_setup_confirmed"):
		return
	_menu.call(&"set_local_player_counts", 1, 0)
	watch_signals(_menu)

	assert_false(bool(_menu.call(&"request_start_once")))
	assert_false(bool(_menu.call(&"request_start_once")))
	assert_signal_not_emitted(_menu, "local_setup_confirmed")


func test_home_to_roster_flow_configures_each_player_through_page_intents() -> void:
	var home := _get_screen(&"home")
	var start_button := _find_button(home, "开始游戏")
	assert_not_null(start_button)
	start_button.pressed.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"mode")

	var mode := _get_screen(&"mode")
	var local_card := _find_card(mode, "本地游戏")
	assert_not_null(local_card)
	local_card.activated.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"local_count")

	assert_true(bool(_menu.call(&"set_local_player_counts", 2, 0)))
	var count_page := _get_screen(&"local_count")
	var next_button := _find_button(count_page, "下一步")
	assert_not_null(next_button)
	next_button.pressed.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"player_setup")
	await get_tree().create_timer(0.24, true, false, true).timeout

	var setup_page := _get_screen(&"player_setup") as FrontendPlayerSetupPage
	assert_not_null(setup_page)
	watch_signals(setup_page)
	await _configure_current_player(setup_page, 0, 0, "")
	assert_eq(_menu.call(&"get_current_screen"), &"player_setup")
	assert_eq(setup_page.slot_label.text, "P2")
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _configure_current_player(setup_page, 1, 1, "玩家二")

	assert_eq(_menu.call(&"get_current_screen"), &"roster")
	assert_signal_emit_count(setup_page, "player_confirmed", 2)
	var snapshot := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_not_null(snapshot)
	assert_true(snapshot.validate().is_empty(), "逐位确认后草稿应可进入对局")
	assert_eq(snapshot.players[0].display_name, "P1", "空名应在确认时规范为席位名")
	assert_eq(snapshot.players[1].display_name, "玩家二")

	var roster := _get_screen(&"roster") as FrontendRosterPage
	assert_not_null(roster)
	assert_eq(_find_roster_cards(roster).size(), 2)
	var roster_start := _find_button(roster, "开始游戏")
	assert_not_null(roster_start)
	assert_false(roster_start.disabled)


func test_back_navigation_preserves_draft_then_home_confirmation_clears_it() -> void:
	_menu.call(&"show_screen", &"mode", false)
	assert_true(bool(_menu.call(&"request_mode", SessionSetup.GameMode.LOCAL)))
	assert_true(bool(_menu.call(&"set_local_player_counts", 2, 1)))

	var count_page := _get_screen(&"local_count")
	var count_back := _find_button(count_page, "返回")
	assert_not_null(count_back)
	count_back.pressed.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	_assert_player_counts(2, 1)

	assert_true(bool(_menu.call(&"request_mode", SessionSetup.GameMode.LOCAL)))
	assert_eq(_menu.call(&"get_current_screen"), &"local_count")
	_assert_player_counts(2, 1)
	count_back.pressed.emit()

	var mode := _get_screen(&"mode")
	var home_back := _find_button(mode, "返回")
	assert_not_null(home_back)
	home_back.pressed.emit()
	var modal := _find_named_control("ModalLayer")
	assert_not_null(modal)
	assert_true(modal.visible)
	assert_eq(_menu.call(&"get_current_screen"), &"mode")

	var cancel_button := _find_button(modal, "取消")
	assert_not_null(cancel_button)
	cancel_button.pressed.emit()
	await get_tree().process_frame
	assert_false(modal.visible)
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	_assert_player_counts(2, 1)

	home_back.pressed.emit()
	assert_true(modal.visible)
	# 第二次打开会将上一批模态控件 queue_free；在确认跳页前先完成该清理帧。
	await get_tree().process_frame
	var discard_button := _find_button(modal, "放弃")
	assert_not_null(discard_button)
	discard_button.pressed.emit()
	assert_eq(_menu.call(&"get_current_screen"), &"home")
	assert_false(modal.visible)
	_assert_player_counts(1, 0)
	var cleared := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_false(cleared.players[0].is_configured())


func test_roster_card_edit_returns_to_roster_and_keeps_the_change() -> void:
	await _complete_two_player_setup()
	await get_tree().create_timer(0.30, true, false, true).timeout
	var roster := _get_screen(&"roster") as FrontendRosterPage
	assert_not_null(roster)
	watch_signals(roster)
	var player_two_card := _find_roster_card_by_slot(roster, 1)
	assert_not_null(player_two_card)
	if player_two_card == null:
		return
	player_two_card._activate()
	assert_signal_emitted_with_parameters(roster, "edit_player_requested", [1])
	assert_eq(_menu.call(&"get_current_screen"), &"player_setup")
	await get_tree().create_timer(0.24, true, false, true).timeout

	var setup_page := _get_screen(&"player_setup") as FrontendPlayerSetupPage
	assert_eq(setup_page.slot_label.text, "P2")
	setup_page.name_input.text = "修改后的名字"
	setup_page.name_input.text_changed.emit(setup_page.name_input.text)
	await get_tree().process_frame
	setup_page.confirm_button.pressed.emit()

	assert_eq(_menu.call(&"get_current_screen"), &"roster")
	await get_tree().create_timer(0.24, true, false, true).timeout
	var restored_focus := get_viewport().gui_get_focus_owner() as FrontendRosterPlayerCard
	assert_not_null(restored_focus)
	assert_eq(restored_focus.player_setup.slot_index, 1, "编辑完成应回到原玩家卡焦点")
	assert_eq((restored_focus.get_node("%PlayerName") as Label).text, "修改后的名字")
	var snapshot := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(snapshot.players[1].display_name, "修改后的名字")
	assert_true(snapshot.validate().is_empty())


func test_game_guide_locks_background_and_restores_the_entry_focus() -> void:
	_menu.call(&"show_screen", &"home", false)
	await get_tree().process_frame
	var home := _get_screen(&"home")
	var rules_button := _find_button(home, "游戏说明")
	assert_not_null(rules_button)
	rules_button.grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), rules_button)

	rules_button.pressed.emit()
	var guide := _menu.call(&"get_game_guide") as DigitalGameGuide
	assert_not_null(guide)
	assert_true(guide.is_guide_open())
	assert_true(get_tree().paused)
	assert_true(guide.can_process(), "指南根节点必须在暂停域继续处理")
	assert_false(home.is_interaction_enabled())
	assert_false(_has_focusable_descendant(home), "指南打开时背景页不应保留可聚焦控件")
	await get_tree().process_frame
	assert_eq(guide.screen_state, FrontendScreen.ScreenState.ACTIVE)
	assert_true(_has_focusable_descendant(guide), "指南必须暴露键盘/手柄焦点目标")
	guide.close_guide(false)
	assert_eq(get_viewport().gui_get_focus_owner(), rules_button)
	await get_tree().process_frame
	assert_false(guide.is_guide_open())
	assert_false(get_tree().paused)
	assert_true(home.is_interaction_enabled())


func test_f1_opens_the_guide_from_the_main_menu_and_restores_focus() -> void:
	_menu.call(&"show_screen", &"home", false)
	await get_tree().process_frame
	var home := _get_screen(&"home")
	var rules_button := _find_button(home, "游戏说明")
	assert_not_null(rules_button)
	rules_button.grab_focus()
	await _send_ui_action(&"guide_toggle")
	var guide := _menu.call(&"get_game_guide") as DigitalGameGuide
	assert_true(guide.is_guide_open(), "指南标注 F1 随时查看，主菜单也必须响应")
	if not guide.is_guide_open():
		return
	assert_eq(guide.get("_context").source, GuideOpenContext.Source.MAIN_MENU)
	guide.close_guide(false)
	await get_tree().process_frame
	assert_same(get_viewport().gui_get_focus_owner(), rules_button)


func test_loading_lock_rejects_guide_modal_and_keeps_the_session_handoff_atomic() -> void:
	_make_live_draft_valid()
	var launcher := FakeSessionLauncher.new()
	_menu.call(&"set_session_launcher", launcher)
	assert_true(bool(_menu.call(&"request_start_once")))
	assert_eq(_menu.call(&"get_current_screen"), &"loading")
	assert_false(bool(_menu.call(&"open_game_guide")), "加载锁定后不得再叠加指南模态")
	await _send_ui_action(&"guide_toggle")
	var guide := _menu.call(&"get_game_guide") as DigitalGameGuide
	assert_false(guide.is_guide_open())
	assert_true(bool(_menu.get("_start_locked")))


func test_rapid_screen_changes_leave_focus_only_on_the_visible_page() -> void:
	var resting_positions: Dictionary[StringName, Vector2] = {}
	for screen_name: StringName in STABLE_SCREENS:
		var resting_page := _get_screen(screen_name)
		var transition_target := resting_page.get_node_or_null(resting_page.transition_target_path) as Control
		if transition_target != null:
			resting_positions[screen_name] = transition_target.position
	for screen_name: StringName in [
		&"mode",
		&"local_count",
		&"player_setup",
		&"roster",
		&"home",
		&"mode",
	]:
		assert_true(bool(_menu.call(&"show_screen", screen_name)))
	await get_tree().create_timer(0.32, true, false, true).timeout

	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	var visible_pages := 0
	for screen_name: StringName in STABLE_SCREENS:
		var page := _get_screen(screen_name)
		assert_not_null(page)
		if page.visible:
			visible_pages += 1
			assert_eq(screen_name, &"mode")
		else:
			var owner := get_viewport().gui_get_focus_owner()
			assert_false(owner != null and page.is_ancestor_of(owner), "%s 不得持有焦点" % screen_name)
		if resting_positions.has(screen_name):
			var target := page.get_node_or_null(page.transition_target_path) as Control
			assert_eq(target.position, resting_positions[screen_name], "%s 快速切换后不得漂移" % screen_name)
	assert_eq(visible_pages, 1)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_true(focus_owner != null and _get_screen(&"mode").is_ancestor_of(focus_owner))


func test_valid_start_request_accepts_once_and_rejects_rapid_duplicate() -> void:
	_menu.call(&"show_screen", &"local_count", false)
	var next_button := _find_button(_get_screen(&"local_count"), "下一步")
	assert_not_null(next_button)
	next_button.pressed.emit()
	await get_tree().create_timer(0.24, true, false, true).timeout
	var setup_page := _get_screen(&"player_setup") as FrontendPlayerSetupPage
	await _configure_current_player(setup_page, 0, 0, "")
	assert_eq(_menu.call(&"get_current_screen"), &"roster")
	watch_signals(_menu)

	assert_true(bool(_menu.call(&"request_start_once")))
	assert_eq(_menu.call(&"get_current_screen"), &"loading")
	assert_false(bool(_menu.call(&"request_start_once")), "加载锁定后不得重复创建会话")
	assert_signal_not_emitted(_menu, "local_setup_confirmed")

	# _begin_local_session() 会等下一帧；先移出场景树，保证本集成测试不切换 main_map。
	var detached_menu := _menu
	var parent := detached_menu.get_parent()
	if parent != null:
		parent.remove_child(detached_menu)
	await get_tree().process_frame
	detached_menu.free()
	_menu = null


func test_configured_player_reduction_requires_confirmation_and_preserves_survivor() -> void:
	assert_true(bool(_menu.call(&"set_local_player_counts", 2, 0)))
	var live_draft := _menu.get("_draft") as SessionSetup
	var survivor := live_draft.players[0]
	var removed := live_draft.players[1]
	removed.display_name = "将被移除"
	removed.profession_type = PlayerClass.PlayerCharacter.探险博主
	removed.starting_region = MapSection.REGION.恩施
	_menu.call(&"show_screen", &"local_count", false)

	_menu.call(&"_request_count_change", 1, 0)
	var modal := _find_named_control("ModalLayer")
	assert_true(modal.visible)
	_find_button(modal, "取消").pressed.emit()
	await get_tree().process_frame
	assert_eq((_menu.call(&"get_draft_snapshot") as SessionSetup).players.size(), 2)

	_menu.call(&"_request_count_change", 1, 0)
	await get_tree().process_frame
	assert_true(modal.visible)
	_find_button(modal, "移除").pressed.emit()
	var resized := _menu.get("_draft") as SessionSetup
	assert_eq(resized.players.size(), 1)
	assert_same(resized.players[0], survivor)
	assert_eq(resized.players[0].slot_index, 0)


func test_untouched_automatic_bot_can_be_removed_without_confirmation() -> void:
	assert_true(bool(_menu.call(&"set_local_player_counts", 1, 1)))
	_menu.call(&"show_screen", &"local_count", false)
	_menu.call(&"_request_count_change", 1, 0)
	assert_false(_find_named_control("ModalLayer").visible)
	var snapshot := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(snapshot.human_count, 1)
	assert_eq(snapshot.bot_count, 0)
	assert_eq(snapshot.players.size(), 1)


func test_ui_actions_navigate_activate_and_cancel_the_mode_page() -> void:
	_menu.call(&"show_screen", &"mode", false)
	await get_tree().process_frame
	var mode := _get_screen(&"mode")
	var local_card := _find_card(mode, "本地游戏")
	var network_card := _find_card(mode, "网络游戏")
	assert_eq(get_viewport().gui_get_focus_owner(), local_card)
	await _send_ui_action(&"ui_right")
	assert_eq(get_viewport().gui_get_focus_owner(), network_card)
	watch_signals(_menu)
	await _send_ui_action(&"ui_accept")
	assert_signal_emitted_with_parameters(
		_menu,
		"mode_requested",
		[SessionSetup.GameMode.NETWORK],
	)
	assert_eq(_menu.call(&"get_current_screen"), &"mode")
	await _send_ui_action(&"ui_cancel")
	assert_eq(_menu.call(&"get_current_screen"), &"home")


func test_loading_renders_before_prepare_and_prepare_failure_returns_to_roster() -> void:
	_make_live_draft_valid()
	var launcher := FakeSessionLauncher.new()
	launcher.prepare_result = ERR_INVALID_DATA
	_menu.call(&"set_session_launcher", launcher)
	watch_signals(_menu)
	var request_frame := Engine.get_process_frames()

	assert_true(bool(_menu.call(&"request_start_once")))
	assert_eq(_menu.call(&"get_current_screen"), &"loading")
	await get_tree().process_frame
	assert_eq(launcher.prepare_calls, 0, "加载页至少应先完成一帧")
	assert_true(await _wait_until(func() -> bool:
		return launcher.prepare_calls == 1 and _menu.call(&"get_current_screen") == &"roster"
	), "加载失败回滚不得依赖固定动画时长")

	assert_eq(launcher.prepare_calls, 1)
	assert_gte(launcher.prepare_frame - request_frame, 2)
	assert_eq(launcher.scene_calls, 0)
	assert_eq(launcher.rollback_calls, 0)
	assert_eq(_menu.call(&"get_current_screen"), &"roster")
	assert_false(bool(_menu.get("_start_locked")))
	assert_signal_not_emitted(_menu, "local_setup_confirmed")


func test_successful_loading_submission_is_emitted_once_and_stays_locked_for_scene_handoff() -> void:
	_make_live_draft_valid()
	var launcher := FakeSessionLauncher.new()
	_menu.call(&"set_session_launcher", launcher)
	watch_signals(_menu)

	assert_true(bool(_menu.call(&"request_start_once")))
	assert_true(await _wait_until(func() -> bool:
		return launcher.scene_calls == 1
	), "会话交接不得依赖固定动画时长")

	assert_eq(launcher.prepare_calls, 1)
	assert_eq(launcher.scene_calls, 1)
	assert_eq(launcher.rollback_calls, 0)
	assert_not_null(launcher.received_setup)
	assert_true(launcher.received_setup.validate().is_empty())
	assert_signal_emit_count(_menu, "local_setup_confirmed", 1)
	assert_eq(_menu.call(&"get_current_screen"), &"loading")
	assert_true(bool(_menu.get("_start_locked")))
	assert_false(bool(_menu.call(&"request_start_once")))


func _has_methods(method_names: Array[StringName]) -> bool:
	var complete := true
	for method_name: StringName in method_names:
		if not _menu.has_method(method_name):
			assert_true(false, "主菜单缺少公开方法 %s" % method_name)
			complete = false
	return complete


func _get_screen(screen_name: StringName) -> FrontendScreen:
	return _get_screen_from(_menu, screen_name)


func _get_screen_from(menu: Node, screen_name: StringName) -> FrontendScreen:
	var node_name: StringName = SCREEN_NODE_NAMES.get(screen_name, &"")
	if node_name.is_empty():
		return null
	return menu.find_child(String(node_name), true, false) as FrontendScreen


func _find_named_control(node_name: String) -> Control:
	return _menu.find_child(node_name, true, false) as Control


func _find_button(root: Node, text_value: String) -> Button:
	if root == null:
		return null
	for node: Node in _descendants(root):
		if node is Button and (node as Button).text == text_value:
			return node as Button
	return null


func _find_card(root: Node, title: String) -> FrontendStatefulCard:
	if root == null:
		return null
	for node: Node in _descendants(root):
		if node is FrontendStatefulCard and (node as FrontendStatefulCard).title == title:
			return node as FrontendStatefulCard
	return null


func _find_roster_card_by_slot(root: Node, slot_index: int) -> FrontendRosterPlayerCard:
	if root == null:
		return null
	for node: Node in _descendants(root):
		if node is FrontendRosterPlayerCard:
			var card := node as FrontendRosterPlayerCard
			if card.player_setup != null and card.player_setup.slot_index == slot_index:
				return card
	return null


func _find_roster_cards(root: Node) -> Array[FrontendRosterPlayerCard]:
	var cards: Array[FrontendRosterPlayerCard] = []
	if root == null:
		return cards
	for node: Node in _descendants(root):
		if node is FrontendRosterPlayerCard:
			cards.append(node as FrontendRosterPlayerCard)
	return cards


func _group_controls(root: Node, group_name: StringName) -> Array[Control]:
	var controls: Array[Control] = []
	for node: Node in _descendants(root):
		if node is Control and node.is_in_group(group_name):
			controls.append(node as Control)
	return controls


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child: Node in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var current: Node = pending.pop_front()
		result.append(current)
		for child: Node in current.get_children():
			pending.append(child)
	return result


func _configure_current_player(
		page: FrontendPlayerSetupPage,
		profession_position: int,
		region_position: int,
		display_name: String
) -> void:
	assert_not_null(page)
	var profession_cards := _group_controls(page, &"frontend_profession_card")
	profession_cards.sort_custom(func(left: Control, right: Control) -> bool:
		return int(left.get_meta(&"profession_type")) < int(right.get_meta(&"profession_type"))
	)
	var region_buttons := _group_controls(page, &"frontend_birthplace_option")
	region_buttons.sort_custom(func(left: Control, right: Control) -> bool:
		return int(left.get_meta(&"region")) < int(right.get_meta(&"region"))
	)
	assert_gt(profession_cards.size(), profession_position)
	assert_gt(region_buttons.size(), region_position)
	(profession_cards[profession_position] as FrontendStatefulCard).activated.emit()
	(region_buttons[region_position] as Button).pressed.emit()
	if not display_name.is_empty():
		page.name_input.text = display_name
		page.name_input.text_changed.emit(display_name)
	var current_index := int(page.slot_label.text.trim_prefix("P")) - 1
	var before_confirm := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_eq(
		before_confirm.players[current_index].profession_type,
		int(profession_cards[profession_position].get_meta(&"profession_type")),
		"职业卡意图应写入当前席位草稿"
	)
	assert_eq(
		before_confirm.players[current_index].starting_region,
		int(region_buttons[region_position].get_meta(&"region")),
		"出生点意图应写入当前席位草稿"
	)
	# 地图出生点选择会延迟一帧恢复列表焦点；模拟真实输入节奏后再确认。
	await get_tree().process_frame
	page.confirm_button.pressed.emit()
	assert_eq(page.message_label.text, "", "配置确认不应被页面拒绝")


func _complete_two_player_setup() -> void:
	_menu.call(&"show_screen", &"local_count", false)
	assert_true(bool(_menu.call(&"set_local_player_counts", 2, 0)))
	var next_button := _find_button(_get_screen(&"local_count"), "下一步")
	assert_not_null(next_button)
	next_button.pressed.emit()
	await get_tree().create_timer(0.24, true, false, true).timeout
	var page := _get_screen(&"player_setup") as FrontendPlayerSetupPage
	await _configure_current_player(page, 0, 0, "玩家一")
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _configure_current_player(page, 1, 1, "玩家二")
	assert_eq(_menu.call(&"get_current_screen"), &"roster")


func _assert_player_counts(expected_humans: int, expected_bots: int) -> void:
	var snapshot := _menu.call(&"get_draft_snapshot") as SessionSetup
	assert_not_null(snapshot)
	assert_eq(snapshot.human_count, expected_humans)
	assert_eq(snapshot.bot_count, expected_bots)
	assert_eq(snapshot.players.size(), expected_humans + expected_bots)


func _make_live_draft_valid() -> void:
	var live_draft := _menu.get("_draft") as SessionSetup
	var player := live_draft.players[0]
	player.profession_type = PlayerClass.PlayerCharacter.美食博主
	player.starting_region = MapSection.REGION.十堰


func _send_ui_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame


func _wait_until(predicate: Callable, max_seconds: float = 1.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _has_focusable_descendant(root: Node) -> bool:
	for node: Node in _descendants(root):
		if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
			return true
	return false
