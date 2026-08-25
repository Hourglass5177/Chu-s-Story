extends GutTest

const ROSTER_SCENE: PackedScene = preload("res://UI/Frontend/roster_page.tscn")
const TEST_VIEWPORT_SIZE := Vector2(2560.0, 1600.0)


func test_one_player_uses_one_column_and_shows_complete_card_content() -> void:
	var setup := _valid_setup(1)
	var page: FrontendRosterPage = await _mount_page(setup)

	_assert_roster_content(page, setup, 1)


func test_two_players_use_a_centered_two_column_lineup() -> void:
	var setup := _valid_setup(2)
	var page: FrontendRosterPage = await _mount_page(setup)

	_assert_roster_content(page, setup, 2)


func test_three_players_use_three_columns_and_show_complete_card_content() -> void:
	var setup := _valid_setup(3)
	var page: FrontendRosterPage = await _mount_page(setup)

	_assert_roster_content(page, setup, 3)


func test_four_players_use_a_symmetric_two_by_two_lineup() -> void:
	var setup := _valid_setup(4)
	var page: FrontendRosterPage = await _mount_page(setup)

	_assert_roster_content(page, setup, 2)


func test_five_players_center_the_short_second_row() -> void:
	var setup := _valid_setup(5)
	var page: FrontendRosterPage = await _mount_page(setup)
	var cards_flow := page.get_node("%CardsFlow") as HFlowContainer

	_assert_roster_content(page, setup, 3)
	var fourth_card := cards_flow.get_child(3) as FrontendRosterPlayerCard
	var fifth_card := cards_flow.get_child(4) as FrontendRosterPlayerCard
	var second_row_center := (
		fourth_card.position.x + fourth_card.size.x * 0.5
		+ fifth_card.position.x + fifth_card.size.x * 0.5
	) * 0.5
	assert_almost_eq(second_row_center, cards_flow.size.x * 0.5, 1.0)


func test_six_players_use_three_columns_and_show_complete_card_content() -> void:
	var setup := _valid_setup(6)
	var page: FrontendRosterPage = await _mount_page(setup)

	_assert_roster_content(page, setup, 3)


func test_invalid_roster_disables_start_and_does_not_emit_start_request() -> void:
	var page: FrontendRosterPage = await _mount_page(SessionSetup.new())
	var start_button := page.get_node("%StartButton") as Button
	var validation_error := page.get_node("%ValidationError") as Label
	var ready_count := page.get_node("%ReadyCountLabel") as Label
	var ready_caption := page.get_node("%ReadyCaption") as Label
	watch_signals(page)

	assert_true(start_button.disabled)
	assert_true(validation_error.visible)
	assert_false(validation_error.text.is_empty())
	assert_eq(ready_count.text, "0 / 1")
	assert_eq(ready_caption.text, "等待配置")
	start_button.pressed.emit()
	assert_signal_not_emitted(page, "start_requested")


func test_valid_roster_emits_one_start_request_without_changing_scene() -> void:
	var page: FrontendRosterPage = await _mount_page(_valid_setup(3))
	var start_button := page.get_node("%StartButton") as Button
	watch_signals(page)

	assert_false(start_button.disabled)
	start_button.pressed.emit()
	assert_signal_emit_count(page, "start_requested", 1)


func test_each_player_card_emits_its_own_edit_index() -> void:
	var page: FrontendRosterPage = await _mount_page(_valid_setup(6))
	var cards_flow := page.get_node("%CardsFlow") as HFlowContainer
	watch_signals(page)

	for index: int in cards_flow.get_child_count():
		var card := cards_flow.get_child(index) as FrontendRosterPlayerCard
		card._activate()
		assert_signal_emitted_with_parameters(page, "edit_player_requested", [index])
	assert_signal_emit_count(page, "edit_player_requested", 6)


func test_focus_and_hover_update_the_player_preview() -> void:
	var setup := _valid_setup(3)
	var page: FrontendRosterPage = await _mount_page(setup)
	var cards_flow := page.get_node("%CardsFlow") as HFlowContainer
	var preview_identity := page.get_node("%PreviewIdentity") as Label
	var preview_meta := page.get_node("%PreviewMeta") as Label
	var preview_skill := page.get_node("%PreviewSkill") as Label
	var preview_accent := page.get_node("%PreviewAccent") as ColorRect
	var second_card := cards_flow.get_child(1) as FrontendRosterPlayerCard
	var third_card := cards_flow.get_child(2) as FrontendRosterPlayerCard

	second_card.grab_focus()
	await get_tree().process_frame
	_assert_preview(
		preview_identity,
		preview_meta,
		preview_skill,
		preview_accent,
		setup.players[1],
	)

	third_card.mouse_entered.emit()
	await get_tree().process_frame
	_assert_preview(
		preview_identity,
		preview_meta,
		preview_skill,
		preview_accent,
		setup.players[2],
	)


func test_only_bot_slots_show_the_short_ai_badge() -> void:
	var setup := SessionSetup.new()
	assert_eq(setup.resize_slots(1, 1), OK)
	var professions: Array = PlayerClass.PlayerCharacter.values()
	var regions: Array = MapSection.出生点坐标.keys()
	for index: int in setup.players.size():
		var player: PlayerSetup = setup.players[index]
		player.profession_type = int(professions[index])
		player.starting_region = int(regions[index])
	var page: FrontendRosterPage = await _mount_page(setup)
	var cards_flow := page.get_node("%CardsFlow") as HFlowContainer
	var human_card := cards_flow.get_child(0) as FrontendRosterPlayerCard
	var bot_card := cards_flow.get_child(1) as FrontendRosterPlayerCard

	assert_false((human_card.get_node("%ControlBadge") as PanelContainer).visible)
	assert_eq((human_card.get_node("%ControlLabel") as Label).text, "")
	assert_true((bot_card.get_node("%ControlBadge") as PanelContainer).visible)
	assert_eq((bot_card.get_node("%ControlLabel") as Label).text, "AI")


func _mount_page(setup: SessionSetup) -> FrontendRosterPage:
	var page := ROSTER_SCENE.instantiate() as FrontendRosterPage
	page.visible = true
	page.custom_minimum_size = TEST_VIEWPORT_SIZE
	add_child_autofree(page)
	page.bind_setup(setup)
	await get_tree().process_frame
	page.refresh_view()
	await get_tree().process_frame
	return page


func _assert_roster_content(
		page: FrontendRosterPage,
		setup: SessionSetup,
		expected_columns: int
) -> void:
	var cards_flow := page.get_node("%CardsFlow") as HFlowContainer
	var ready_count := page.get_node("%ReadyCountLabel") as Label
	var ready_caption := page.get_node("%ReadyCaption") as Label
	assert_eq(page.get_layout_columns(), expected_columns)
	assert_eq(cards_flow.get_child_count(), setup.players.size())
	assert_eq(ready_count.text, "%d / %d" % [setup.players.size(), setup.players.size()])
	assert_eq(ready_caption.text, "全员就绪")
	for index: int in setup.players.size():
		var player: PlayerSetup = setup.players[index]
		var card := cards_flow.get_child(index) as FrontendRosterPlayerCard
		var definition: ProfessionDefinition = ProfessionManager.get_definition_by_type(
			player.profession_type
		)
		assert_not_null(card)
		assert_not_null(definition)
		assert_same(card.player_setup, player)
		assert_eq((card.get_node("%SlotLabel") as Label).text, "P%d" % (index + 1))
		assert_false((card.get_node("%ControlBadge") as PanelContainer).visible)
		assert_eq((card.get_node("%ControlLabel") as Label).text, "")
		assert_eq((card.get_node("%ReadyLabel") as Label).text, "就绪")
		assert_eq((card.get_node("%PlayerName") as Label).text, player.display_name)
		assert_eq((card.get_node("%ProfessionLabel") as Label).text, definition.profession_name)
		assert_eq(
			(card.get_node("%RegionLabel") as Label).text,
			String(MapSection.REGION.find_key(player.starting_region)),
		)
		assert_same((card.get_node("%Portrait") as TextureRect).texture, definition.selection_portrait)
		assert_same(card.artwork, definition.selection_portrait)


func _assert_preview(
		identity: Label,
		meta: Label,
		skill: Label,
		accent: ColorRect,
		player: PlayerSetup
) -> void:
	var definition := ProfessionManager.get_definition_by_type(player.profession_type)
	var region_name := String(MapSection.REGION.find_key(player.starting_region))
	assert_eq(identity.text, "P%d  %s" % [player.slot_index + 1, player.display_name])
	assert_eq(meta.text, "%s · %s" % [definition.profession_name, region_name])
	assert_eq(skill.text, "%s · %s" % [definition.skill_name, definition.short_description])
	assert_eq(accent.color, FrontendRosterPlayerCard.accent_for_slot(player.slot_index))


func _valid_setup(player_count: int) -> SessionSetup:
	var setup := SessionSetup.new()
	assert_eq(setup.resize_slots(player_count, 0), OK)
	var professions: Array = PlayerClass.PlayerCharacter.values()
	var regions: Array = MapSection.出生点坐标.keys()
	for index: int in player_count:
		var player: PlayerSetup = setup.players[index]
		player.display_name = "玩家%d" % (index + 1)
		player.profession_type = int(professions[index])
		player.starting_region = int(regions[index])
	assert_true(setup.validate().is_empty())
	return setup
