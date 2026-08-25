extends GutTest

const PLAYER_SETUP_SCENE: PackedScene = preload("res://UI/Frontend/player_setup_page.tscn")

var _page: FrontendPlayerSetupPage
var _setup: SessionSetup


func before_each() -> void:
	_page = PLAYER_SETUP_SCENE.instantiate() as FrontendPlayerSetupPage
	add_child_autofree(_page)
	_setup = SessionSetup.new()
	_page.bind_setup(_setup, 0)
	_page.enter_screen(false)


func test_page_builds_six_focusable_professions_and_six_synchronised_birthplaces() -> void:
	assert_eq(_page.profession_grid.get_child_count(), 6)
	assert_eq(_page.birthplace_list.get_child_count(), MapSection.出生点坐标.size())
	assert_eq(_page.birthplace_hotspots.get_child_count(), MapSection.出生点坐标.size())
	for card_node: Node in _page.profession_grid.get_children():
		var card := card_node as FrontendStatefulCard
		assert_not_null(card)
		assert_eq(card.focus_mode, Control.FOCUS_ALL)
		assert_false(card.focus_neighbor_right.is_empty())
	for option_node: Node in _page.birthplace_list.get_children():
		var option := option_node as Button
		assert_not_null(option)
		assert_eq(option.focus_mode, Control.FOCUS_ALL)
		assert_false(option.focus_neighbor_left.is_empty())


func test_occupied_profession_and_birthplace_stay_inspectable_but_cannot_be_selected() -> void:
	assert_eq(_setup.resize_slots(2, 0), OK)
	var first := _setup.players[0]
	first.profession_type = PlayerClass.PlayerCharacter.美食博主
	first.starting_region = MapSection.REGION.十堰
	_page.bind_setup(_setup, 1)
	watch_signals(_page)

	var occupied_card := _find_profession_card(first.profession_type)
	assert_not_null(occupied_card)
	assert_eq(occupied_card.presentation_state, FrontendStyle.CardState.OCCUPIED)
	assert_eq(occupied_card.focus_mode, Control.FOCUS_ALL)
	occupied_card._activate()
	assert_eq(_setup.players[1].profession_type, PlayerSetup.UNSELECTED)
	assert_signal_emitted_with_parameters(_page, "invalid_action", ["P1 已选择该职业"])
	occupied_card.focus_entered.emit()
	assert_eq(_page.profession_name_label.text, "美食博主", "占用职业仍应可查看详情")

	var occupied_region := _find_region_button(first.starting_region)
	assert_not_null(occupied_region)
	assert_false(occupied_region.disabled)
	occupied_region.button_pressed = true
	occupied_region.pressed.emit()
	assert_eq(_setup.players[1].starting_region, PlayerSetup.UNSELECTED)
	assert_false(occupied_region.button_pressed, "无效点击必须立即回滚 toggle 视觉")
	assert_signal_emitted_with_parameters(_page, "invalid_action", ["该出生点已由P1选择"])


func test_free_card_and_map_hotspot_update_the_same_player_draft() -> void:
	var profession_type := PlayerClass.PlayerCharacter.旅行博主
	var card := _find_profession_card(profession_type)
	card._activate()
	assert_eq(_setup.players[0].profession_type, profession_type)

	var region := MapSection.REGION.恩施
	var hotspot := _find_hotspot(region)
	hotspot.pressed.emit()
	assert_eq(_setup.players[0].starting_region, region)
	assert_true(_find_region_button(region).button_pressed)
	assert_true(_find_hotspot(region).button_pressed)


func test_confirm_normalizes_empty_name_and_returns_to_the_requested_destination() -> void:
	_setup.players[0].display_name = "   "
	_setup.players[0].profession_type = PlayerClass.PlayerCharacter.生活博主
	_setup.players[0].starting_region = MapSection.REGION.荆州
	_page.bind_setup(_setup, 0, true)
	watch_signals(_page)

	_page.confirm_button.pressed.emit()
	assert_eq(_setup.players[0].display_name, "P1")
	assert_signal_emitted_with_parameters(_page, "player_confirmed", [0, true])


func test_incomplete_confirmation_emits_a_short_reason_without_advancing() -> void:
	watch_signals(_page)
	_page.confirm_button.pressed.emit()
	assert_signal_emitted_with_parameters(_page, "invalid_action", ["请选择职业"])
	assert_signal_not_emitted(_page, "player_confirmed")
	assert_eq(_page.message_label.text, "请选择职业")


func test_future_bot_defaults_yield_to_the_current_human_without_breaking_uniqueness() -> void:
	assert_eq(_setup.resize_slots(1, 5), OK)
	var claimed_profession := _setup.players[1].profession_type
	var claimed_region := _setup.players[1].starting_region
	_page.bind_setup(_setup, 0)

	_find_profession_card(claimed_profession)._activate()
	_find_region_button(claimed_region).pressed.emit()

	assert_eq(_setup.players[0].profession_type, claimed_profession)
	assert_eq(_setup.players[0].starting_region, claimed_region)
	var professions: Dictionary[int, bool] = {}
	var regions: Dictionary[int, bool] = {}
	for player: PlayerSetup in _setup.players:
		assert_true(player.has_valid_profession())
		assert_true(player.has_valid_starting_region())
		professions[player.profession_type] = true
		regions[player.starting_region] = true
	assert_eq(professions.size(), 6)
	assert_eq(regions.size(), 6)
	assert_true(_setup.validate().is_empty())


func test_confirmed_future_bot_is_not_silently_reassigned_when_returning_to_a_human() -> void:
	assert_eq(_setup.resize_slots(1, 1), OK)
	var human := _setup.players[0]
	var bot := _setup.players[1]
	human.profession_type = PlayerClass.PlayerCharacter.旅行博主
	human.starting_region = MapSection.REGION.恩施
	_page.bind_setup(_setup, 0)
	_page.confirm_button.pressed.emit()
	_page.bind_setup(_setup, 1)
	await wait_seconds(0.3)
	_page.confirm_button.pressed.emit()
	var bot_profession := bot.profession_type
	var bot_region := bot.starting_region

	_page.bind_setup(_setup, 0)
	_find_profession_card(bot_profession)._activate()
	_find_region_button(bot_region).pressed.emit()

	assert_eq(human.profession_type, PlayerClass.PlayerCharacter.旅行博主)
	assert_eq(human.starting_region, MapSection.REGION.恩施)
	assert_eq(bot.profession_type, bot_profession)
	assert_eq(bot.starting_region, bot_region)


func test_confirmed_bot_stays_protected_after_human_count_moves_its_slot() -> void:
	assert_eq(_setup.resize_slots(1, 2), OK)
	var confirmed_bot := _setup.players[1]
	_page.bind_setup(_setup, 1)
	_page.confirm_button.pressed.emit()
	var bot_profession := confirmed_bot.profession_type
	var bot_region := confirmed_bot.starting_region

	assert_eq(_setup.resize_slots(2, 2), OK)
	assert_same(_setup.players[2], confirmed_bot)
	_page.bind_setup(_setup, 1)
	_find_profession_card(bot_profession)._activate()
	_find_region_button(bot_region).pressed.emit()

	assert_eq(_setup.players[1].profession_type, PlayerSetup.UNSELECTED)
	assert_eq(_setup.players[1].starting_region, PlayerSetup.UNSELECTED)
	assert_eq(confirmed_bot.profession_type, bot_profession)
	assert_eq(confirmed_bot.starting_region, bot_region)


func test_current_bot_can_rearrange_an_unconfirmed_later_bot_default() -> void:
	assert_eq(_setup.resize_slots(1, 5), OK)
	var human := _setup.players[0]
	human.profession_type = PlayerClass.PlayerCharacter.生活博主
	human.starting_region = MapSection.REGION.恩施
	_page.bind_setup(_setup, 0)
	_page.confirm_button.pressed.emit()
	await wait_seconds(0.3)
	_page.bind_setup(_setup, 1)
	var desired_profession := _setup.players[2].profession_type
	var desired_region := _setup.players[2].starting_region

	_find_profession_card(desired_profession)._activate()
	_find_region_button(desired_region).pressed.emit()

	assert_eq(_setup.players[1].profession_type, desired_profession)
	assert_eq(_setup.players[1].starting_region, desired_region)
	var professions: Dictionary[int, bool] = {}
	var regions: Dictionary[int, bool] = {}
	for player: PlayerSetup in _setup.players:
		professions[player.profession_type] = true
		regions[player.starting_region] = true
	assert_eq(professions.size(), 6)
	assert_eq(regions.size(), 6)


func test_confirm_button_debounces_repeated_accept_for_the_next_slot() -> void:
	_setup.players[0].profession_type = PlayerClass.PlayerCharacter.生活博主
	_setup.players[0].starting_region = MapSection.REGION.荆州
	watch_signals(_page)

	_page.confirm_button.pressed.emit()
	_page.confirm_button.pressed.emit()

	assert_signal_emit_count(_page, "player_confirmed", 1)


func _find_profession_card(profession_type: int) -> FrontendStatefulCard:
	for node: Node in _page.profession_grid.get_children():
		if int(node.get_meta(&"profession_type", PlayerSetup.UNSELECTED)) == profession_type:
			return node as FrontendStatefulCard
	return null


func _find_region_button(region: int) -> Button:
	for node: Node in _page.birthplace_list.get_children():
		if int(node.get_meta(&"region", PlayerSetup.UNSELECTED)) == region:
			return node as Button
	return null


func _find_hotspot(region: int) -> Button:
	for node: Node in _page.birthplace_hotspots.get_children():
		if int(node.get_meta(&"region", PlayerSetup.UNSELECTED)) == region:
			return node as Button
	return null
