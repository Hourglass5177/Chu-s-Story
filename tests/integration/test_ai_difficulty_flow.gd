extends GutTest

func test_difficulty_controls_preserve_other_seats_and_hide_for_humans() -> void:
	var page := preload("res://UI/Frontend/player_setup_page.tscn").instantiate() as FrontendPlayerSetupPage
	add_child_autofree(page)
	var setup := SessionSetup.new(SessionSetup.GameMode.LOCAL, 1, 3)
	page.bind_setup(setup, 1)
	page.enter_screen(false)
	await get_tree().process_frame
	assert_true(page.difficulty_box.visible)
	page.difficulty_buttons[2].pressed.emit()
	assert_eq(int(setup.players[1].ai_difficulty), 2)
	assert_eq(int(setup.players[2].ai_difficulty), 1)
	assert_true(page.difficulty_buttons[2].text.begins_with("已选"))
	page.bind_setup(setup, 2)
	page.difficulty_buttons[0].pressed.emit()
	page.bind_setup(setup, 1)
	assert_true(page.difficulty_buttons[2].button_pressed)
	assert_eq(page.name_input.focus_neighbor_bottom, page.difficulty_buttons[2].get_path())
	page.bind_setup(setup, 0)
	assert_false(page.difficulty_box.visible)
	page.bind_setup(setup, 2)
	assert_true(page.difficulty_buttons[0].button_pressed)
