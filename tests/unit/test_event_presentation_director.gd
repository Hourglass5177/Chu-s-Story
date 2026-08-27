extends GutTest

var _saved_seed: int
var _saved_profile: GameManager.RuntimeProfile

func before_each() -> void:
	_saved_seed = GameManager.get_session_seed()
	_saved_profile = GameManager.runtime_profile

func after_each() -> void:
	GameManager.configure_session(_saved_seed, _saved_profile)

func test_all_implemented_events_have_a_presentation_tier() -> void:
	assert_eq(EventPresentationDirector.PRESENTATION_TIERS.size(), 40)
	for event_id: StringName in EventManager.IMPLEMENTED_EVENT_IDS:
		assert_true(EventPresentationDirector.PRESENTATION_TIERS.has(event_id), str(event_id))

func test_mei_mei_yu_gong_is_sequential_and_uses_a_single_d6() -> void:
	var director := EventPresentationDirector.new()
	assert_eq(director.get_tier(&"mei_mei_yu_gong"), EventPresentationDirector.Tier.SEQUENTIAL)
	director.free()
	GameManager.configure_session(551122, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	for _index: int in 100:
		var value := EventManager._roll_d6()
		assert_between(value, 1, 6)

func test_settlement_panel_does_not_block_the_full_screen() -> void:
	var director := EventPresentationDirector.new()
	add_child_autofree(director)
	await get_tree().process_frame
	director.begin_sequence(&"chen_jin_ti_yan", "沉浸体验")
	var panel: PanelContainer = director.get_node("EventSettlementPanel")
	assert_eq(director.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"透明的全屏演出层不能吞掉地图和 HUD 的鼠标输入")
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP,
		"只有可见的小弹窗自身应接收点击快进")
	assert_lt(panel.size.x, director.size.x if director.size.x > 0.0 else 2560.0)
	assert_lt(panel.size.y, director.size.y if director.size.y > 0.0 else 1600.0)
	director.cancel_and_restore(&"test_complete")
	assert_eq(director.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(panel.visible)

func test_settlement_panel_uses_clear_title_hierarchy_and_keeps_click_to_fast_forward() -> void:
	var director := EventPresentationDirector.new()
	add_child_autofree(director)
	await get_tree().process_frame
	director.begin_sequence(&"chen_jin_ti_yan", "沉浸体验")
	var panel: PanelContainer = director.get_node("EventSettlementPanel")
	var title: Label = panel.get_node("ContentMargin/SettlementContent/EventSettlementTitle")
	var message: Label = panel.get_node("ContentMargin/SettlementContent/EventSettlementMessage")
	assert_eq(title.text, "【沉浸体验】")
	assert_eq(message.text, "结算中…")
	assert_gte(title.get_theme_font_size("font_size"), 40)
	assert_gt(title.get_theme_font_size("font_size"), message.get_theme_font_size("font_size"))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)
	assert_true(director._fast_forward_requested,
		"点击可见弹窗仍应快进当前演出步骤")
