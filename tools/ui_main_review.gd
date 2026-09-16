extends Node

## Actual window viewport; no alternate scaling or replacement of production logic.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var page := "home"
	var avatar := -1
	var review_phase := -1
	var capture_tag := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="): page = arg.trim_prefix("--page=")
		if arg.begins_with("--avatar="): avatar = arg.trim_prefix("--avatar=").to_int()
		if arg.begins_with("--phase="): review_phase = arg.trim_prefix("--phase=").to_int()
		if arg.begins_with("--capture-tag="): capture_tag = arg.trim_prefix("--capture-tag=")
	if page.begins_with("minigame_gallery") or page in ["home", "credits", "mode", "local_count", "loading", "menu_confirm", "guide", "guide_topic", "compendium", "player_setup", "player_setup_bot", "birthplace_map", "roster"]:
		var menu := load("res://main_menu.tscn").instantiate() as MainMenu
		add_child(menu)
		await get_tree().process_frame
		if page in ["player_setup", "player_setup_bot", "birthplace_map", "roster"]:
			menu.set_local_player_counts(2, 1)
			for index in range(3):
				menu._draft.players[index].profession_type = index
				menu._draft.players[index].starting_region = [MapSection.REGION.十堰, MapSection.REGION.随州, MapSection.REGION.孝感][index]
		if page == "credits":
			menu._show_credits_modal(null)
		elif page == "menu_confirm":
			menu._show_confirmation("放弃本次配置？", "返回首页后，需要重新配置本地游戏。", "放弃配置", func(): pass)
		elif page.begins_with("minigame_gallery"):
			menu.open_game_guide()
			var guide := menu.get_game_guide()
			# Process-local preview only; never unlock or save player discoveries.
			guide._developer_view_enabled = page != "minigame_gallery"
			guide.open_minigame_gallery()
			if page.ends_with("last"):
				var gallery := guide.find_child("MinigameGallery", true, false) as GuideMinigameGallery
				gallery._page = 2
				gallery._rebuild()
		elif page in ["guide", "guide_topic", "compendium"]:
			menu.open_game_guide()
			if page == "compendium": menu.get_game_guide()._render_compendium(DiscoveryManager.KIND_FEIYI, 0)
			if page == "guide_topic": menu.get_game_guide()._open_topic_by_index(&"quick", 0)
		elif page == "birthplace_map":
			menu.show_screen(&"player_setup", false)
			menu._show_birthplace_map()
		elif page == "player_setup_bot": menu._open_player_setup(2, false)
		else: menu.show_screen(StringName(page), false)
	else:
		GameManager.player_data = [
			{"name":"江城旅人", "job":"美食博主", "location":"十堰"},
			{"name":"楚地访客", "job":"商业博主", "location":"随州"}]
		if page == "hud_ai": GameManager.player_data[1]["is_bot"] = true
		if avatar >= 0 and avatar < 6:
			GameManager.player_data[0]["job"] = SimulationSchedule.PROFESSION_NAMES[avatar]
			if GameManager.player_data[0]["job"] == GameManager.player_data[1]["job"]:
				GameManager.player_data[1]["job"] = "美食博主"
		if page == "result_six":
			GameManager.player_data.clear()
			for index in range(6):
				GameManager.player_data.append({"name":"楚地旅人" + str(index + 1), "job":SimulationSchedule.PROFESSION_NAMES[index], "location":SimulationSchedule.LOCATION_NAMES[index]})
		add_child(load("res://main_map.tscn").instantiate())
		for frame in range(12): await get_tree().process_frame
		TurnManager.change_phase(clampi(review_phase, 0, 4) as TurnManager.TurnPhase if review_phase >= 0 else TurnManager.TurnPhase.ACTION)
		TurnManager.get_node("TurnTimer").stop()
		if review_phase == TurnManager.TurnPhase.MOVING: TurnManager.get_node("TurnTimer").start(120)
		var hud := get_tree().get_first_node_in_group("HUD") as HUD
		var player: PlayerClass = TurnManager.players[0]
		var card := load("res://Cards/非遗牌/鄂州/牌子锣.tres") as 非遗牌
		player.非遗牌手牌.append(card)
		hud.refresh_feiyi_list(player)
		match page:
			"hud_message":
				hud.current_status.text = "【艺径寻踪】请选择移动终点"
				hud.information.text = (load("res://Cards/事件牌/艺径寻踪.tres") as 事件牌).description + "\n无事发生！"
			"exit": hud._on_close_pressed()
			"profession_draw":
				var choices: Array = []
				for title: String in ["妙手回春", "天降横财", "水逆退散"]:
					var path := "res://Cards/事件牌/" + title + ".tres"
					if ResourceLoader.exists(path): choices.append(load(path))
				if choices.size() < 3:
					choices.assign(ResourceManager.事件牌库.slice(0, 3))
				hud.profession_draw_overlay._request = ProfessionDrawRequest.new(player, choices, &"event")
				hud.profession_draw_overlay._cards.assign(choices)
				hud.profession_draw_overlay._selected_card = choices[0]
				hud.profession_draw_overlay.context_label.text = player.player_name
				hud.profession_draw_overlay._render_cards()
				hud.profession_draw_overlay.show()
			"achievement": hud.achievement_detail_overlay.show_detail(load("res://Cards/成就牌/饕餮.tres"))
			"national_detail":
				var national := load("res://Cards/非遗牌/黄石/西塞神舟会.tres") as 非遗牌
				player.非遗牌手牌.append(national)
				hud.detail_panel.show_detail(national, player)
			"hud_crowded":
				for path in ["黄石/阳新布贴", "黄石/采茶戏", "黄石/大冶石雕", "武汉/湖北小曲", "武汉/湖北评书"]:
					player.非遗牌手牌.append(load("res://Cards/非遗牌/"+path+".tres"))
				player.事件牌手牌.append(load("res://Cards/事件牌/妙手回春.tres"))
				hud.refresh_feiyi_list(player)
			"result", "result_six":
				var entries: Array[GameResultEntry] = []
				for index in range(TurnManager.players.size()):
					var points := 20 - index * 2
					entries.append(GameResultEntry.new(TurnManager.players[index], {"base_score":points,"total_score":points}, index + 1, index == 0))
				hud.game_result_overlay.present(GameResult.new(GameResult.EndReason.SCORE_LIMIT, 8, entries), false)
			"pause": hud.pause_overlay.open_pause()
			"score": hud.score_overlay.open_for_player(player)
			"detail": hud.detail_panel.show_detail(card, player)
			"profession": hud.profession_detail_overlay.show_for_player(player)
			"shop":
				for coord: Vector3i in player.map.grid_map:
					var section: MapSection = player.map.grid_map[coord]
					if section.type == MapSection.SectionType.商店:
						player.now_pos = coord
						player._record_action_arrival(section, true)
						break
				hud.open_shop_panel(player)
			"backpack":
				player.食物牌手牌.assign(ResourceManager.draw_shop_foods(6))
				hud.backpack_panel.open_backpack(player)
			"market":
				for coord: Vector3i in player.map.grid_map:
					var section: MapSection = player.map.grid_map[coord]
					if section.type == MapSection.SectionType.研究所:
						player.now_pos = coord
						player._record_action_arrival(section, true)
						break
				MarketManager.deposit_card(card, &"preview")
				for path in ["黄石/阳新布贴", "黄石/磁湖采莲船", "随州/随州花鼓戏", "孝感/董永传说"]:
					if ResourceLoader.exists("res://Cards/非遗牌/"+path+".tres"):
						MarketManager.deposit_card(load("res://Cards/非遗牌/"+path+".tres"), &"preview")
				MarketManager.begin_visit(player, player.arrival_id)
				hud.open_market_panel(player)
			"event":
				var event := load("res://Cards/事件牌/妙手回春.tres") as 事件牌
				hud.get_event_overlay().show_retained_card_detail(player, event)
			"event_choice":
				var event := load("res://Cards/事件牌/妙手回春.tres") as 事件牌
				hud.get_event_overlay()._on_event_revealed(player, event)
				var request := EventChoiceRequest.new(player, "是否使用妙手回春，复活一位已淘汰的玩家？", [true], PackedStringArray(["使用妙手回春"]), true)
				hud.get_event_overlay()._show_request(request, false)
			"dice":
				hud.show_dice_faces(player, [2,5], func(): return true)
	for frame in range(40): await get_tree().process_frame
	var sizes := [get_window().size]
	if "--all-sizes" in OS.get_cmdline_user_args(): sizes = [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1600)]
	for dimensions: Vector2i in sizes:
		get_window().borderless = true
		get_window().size = dimensions
		for frame in range(20): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if page == "exit":
			var exit_hud := get_tree().get_first_node_in_group("HUD") as HUD
			var dialog := exit_hud._exit_confirmation
			print("EXIT_LAYOUT ", dimensions, " dialog=", dialog.size, " cancel=", dialog.get_cancel_button().size, " minimum=", dialog.get_cancel_button().custom_minimum_size)
		if not _verify_layout(page):
			get_tree().quit(1)
			return
		var output := "res://artifacts/ui-main/final-review/%s-%dx%d.png" % [capture_tag if not capture_tag.is_empty() else page, get_window().size.x, get_window().size.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		get_viewport().get_texture().get_image().save_png(output)
		print("MAIN_UI_REVIEW ", output)
	if "--verify-input" in OS.get_cmdline_user_args(): await _verify_board_input(page)
	if not "--interactive" in OS.get_cmdline_user_args(): get_tree().quit()

func _verify_layout(page: String) -> bool:
	if page == "hud_message":
		var hud := get_tree().get_first_node_in_group("HUD") as HUD
		var content := hud.get_node("手牌信息/InformationContent") as Control
		var scroll := content.get_node("MessageScroll") as ScrollContainer
		var frame := (hud.get_node("手牌信息/LogFrame") as Control).get_global_rect()
		if not frame.encloses(content.get_global_rect()) or hud.current_status.get_global_rect().intersects(scroll.get_global_rect()):
			push_error("HUD information exceeds frame or overlaps its heading")
			return false
		if content.get_global_rect().intersects(hud.btn_action.get_global_rect()): return false
		print("MESSAGE_LAYOUT ", get_window().size, " visible=", scroll.size, " text=", hud.information.size)
	if page in ["player_setup", "player_setup_bot"]:
		var menu := get_child(0) as MainMenu
		var setup := menu._player_setup_page
		var bounds := get_viewport().get_visible_rect().grow(1)
		for path in ["SafeArea/PagePanel", "SafeArea/PagePanel/Content/Actions"]:
			if not bounds.encloses((setup.get_node(path) as Control).get_global_rect()):
				push_error("UI layout outside viewport: %s/%s rect=%s viewport=%s" % [page, path, (setup.get_node(path) as Control).get_global_rect(), bounds])
				for child in setup.get_node("SafeArea/PagePanel/Content").get_children():
					if child is Control: print("LAYOUT_MIN ", child.name, " ", child.get_combined_minimum_size())
				for child in setup.get_node("SafeArea/PagePanel/Content/MainRow").get_children():
					print("LAYOUT_COLUMN ", child.name, " ", child.get_combined_minimum_size())
				return false
		var map := setup.get_node("%BirthMap/MapTexture") as TextureRect
		if map.texture.resource_path != "res://arts/地图/地图完整版.png" or map.size.x < 700 or map.size.y < 460:
			push_error("UI map: wrong board texture or preview still too small: %s" % map.size)
			return false
		for control: Control in setup.birthplace_list.get_children():
			if not bounds.encloses(control.get_global_rect()): return false
	if page == "birthplace_map":
		var menu := get_child(0) as MainMenu
		if not get_viewport().get_visible_rect().grow(1).encloses(menu._modal_panel.get_global_rect()):
			push_error("Enlarged map outside viewport")
			return false
	if page == "hud_ai":
		var controller := get_tree().get_first_node_in_group("AI_SESSION")
		var speed := controller.find_child("AISpeedButton", true, false) as Control
		var hud := TurnManager.hud
		for key in ["BtnGuide", "BtnPause", "BtnClose"]:
			if speed.get_global_rect().intersects((hud.get_node(key) as Control).get_global_rect()):
				push_error("UI layout: AI speed overlaps " + key)
				return false
	if page in ["player_setup", "player_setup_bot", "hud_ai"]:
		print("MAIN_UI_LAYOUT verified: ", page, " ", get_window().size)
	return true

func _verify_birthplace_map_input() -> void:
	var menu := get_child(0) as MainMenu
	var setup := menu._player_setup_page
	var driver = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
	var selected := menu._draft.players[menu._editing_slot].starting_region
	await driver.click(setup.map_zoom_button)
	assert(menu._modal_layer.visible and not setup.is_interaction_enabled(), "Map click must open a modal")
	var close := menu._modal_body.find_child("CloseMapPreview", true, false) as Button
	assert(get_viewport().gui_get_focus_owner() == close, "Map must focus its return button")
	# An underlying selection must not activate through the full-screen shield.
	await driver.click(setup.birthplace_list.get_child(5))
	assert(menu._draft.players[menu._editing_slot].starting_region == selected, "Map must block underlying birthplace buttons")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert(not menu._modal_layer.visible and setup.is_interaction_enabled(), "Esc must only close the map")
	assert(get_viewport().gui_get_focus_owner() == setup.map_zoom_button, "Map must restore preview focus")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter)
	await get_tree().process_frame
	enter = InputEventKey.new()
	enter.keycode = KEY_ENTER
	get_viewport().push_input(enter)
	await get_tree().process_frame
	assert(menu._modal_layer.visible, "Enter must open the focused map")
	close = menu._modal_body.find_child("CloseMapPreview", true, false) as Button
	await driver.click(close)
	assert(not menu._modal_layer.visible and setup.is_interaction_enabled(), "Map return button must close")
	await driver.click(setup.birthplace_list.get_child(5))
	assert(menu._draft.players[menu._editing_slot].starting_region == int(setup.birthplace_list.get_child(5).get_meta(&"region")), "Birthplace selection must still work after zoom")
	print("MAIN_UI_INPUT verified map pointer/Enter entry, Esc/button return, focus, click shield and subsequent birthplace selection")


func _verify_board_input(page: String) -> void:
	if page in ["player_setup", "player_setup_bot"]:
		await _verify_birthplace_map_input()
		return
	if page.begins_with("minigame_gallery"):
		await _verify_gallery_input()
		return
	var hud := get_tree().get_first_node_in_group("HUD") as HUD
	if hud == null: return
	if page == "hud_message":
		var scroll := hud.information.get_parent() as ScrollContainer
		var event := InputEventMouseButton.new()
		event.position = scroll.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		get_viewport().push_input(event)
		await get_tree().process_frame
		assert(scroll.scroll_vertical > 0, "Long messages must scroll")
		hud._update_game_informs("剩余可移动：6 步")
		await get_tree().process_frame
		await get_tree().process_frame
		assert(scroll.scroll_vertical == 0, "A new short message must return to the top")
		print("MAIN_UI_INPUT verified long message wheel scrolling and short message reset")
		return
	if page == "exit":
		await _verify_exit_input(hud)
		return
	if page == "hud":
		var driver = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
		var track := hud.get_node("回合信息/PhaseTrack") as Button
		await driver.click(track)
		if not hud.game_guide.is_guide_open():
			push_error("UI input: phase tracker did not open current phase guide")
			get_tree().quit(1)
			return
		hud.game_guide.close_guide()
		var close_deadline := Time.get_ticks_msec() + 2000
		while hud.game_guide.is_guide_open() and Time.get_ticks_msec() < close_deadline:
			await get_tree().process_frame
		if hud.game_guide.is_guide_open():
			push_error("UI input: phase guide did not close")
			get_tree().quit(1)
			return
		print("MAIN_UI_INPUT verified phase tracker pointer entry and guide return")
		return
	if page == "hud_ai":
		var controller := get_tree().get_first_node_in_group("AI_SESSION")
		var driver = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
		for expected: float in [1.5, 2.0, 3.0, 1.0]:
			var speed_button := controller.find_child("AISpeedButton", true, false) as Button
			var hovered: Control = await driver.click(speed_button)
			if not is_equal_approx(controller.get_speed_multiplier(), expected):
				push_error("UI input: AI speed did not cycle; expected=%s actual=%s button=%s hovered=%s" % [expected, controller.get_speed_multiplier(), speed_button.get_global_rect(), hovered.get_path() if hovered != null else "none"])
				get_tree().quit(1)
				return
		print("MAIN_UI_INPUT verified pointer cycling of all four AI speeds")
		return
	var panel: Control
	var closing: Control
	match page:
		"detail", "national_detail":
			panel = hud.detail_panel
			closing = panel.get_node("BtnClose")
		"profession":
			panel = hud.profession_detail_overlay
			closing = panel.get_node("Panel/BtnClose")
		"achievement":
			panel = hud.achievement_detail_overlay
			closing = panel.get_node("Panel/BtnClose")
		"shop":
			panel = hud.get_node("商店弹窗")
			closing = panel.get_node("BtnClose")
		"market":
			panel = hud.market_overlay
			closing = panel.get_node("BtnClose")
		"backpack":
			panel = hud.backpack_panel
			closing = panel.get_node("BtnClose")
		"score":
			panel = hud.score_overlay
			closing = panel.get_node("Panel/BtnClose")
		"pause":
			panel = hud.pause_overlay
			closing = hud.pause_overlay.continue_button
		"profession_draw":
			panel = hud.profession_draw_overlay
		_: return
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	get_viewport().push_input(key, true)
	await get_tree().process_frame
	key = key.duplicate()
	key.pressed = false
	get_viewport().push_input(key, true)
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not panel.is_ancestor_of(focus):
		push_error("UI review: focus escaped " + page)
		get_tree().quit(1)
		return
	if page == "profession_draw":
		print("MAIN_UI_INPUT verified Tab focus in timed profession choice")
		return
	var pointer = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
	var hovered: Control = await pointer.click(closing)
	if hovered != closing or panel.visible:
		push_error("UI review: close pointer failed " + page)
		get_tree().quit(1)
		return
	print("MAIN_UI_INPUT verified Tab focus and pointer close: ", page)


func _verify_gallery_input() -> void:
	var menu := get_child(0) as MainMenu
	var guide := menu.get_game_guide()
	var gallery := guide.find_child("MinigameGallery", true, false) as GuideMinigameGallery
	# Exercise selection without changing the user's persisted avatar preference.
	for connection in gallery.avatar_selected.get_connections():
		gallery.avatar_selected.disconnect(connection.callable)
	var pointer = preload("res://tests/helpers/real_pointer_driver.gd").new(get_viewport(), get_tree())
	var choices := gallery.get_node("PracticeAvatarSelector")
	var chosen := choices.get_child(1) as Button
	await pointer.click(chosen)
	if not chosen.button_pressed or gallery.get_selected_avatar_id() != HeritageAvatarCatalog.IDS[1]:
		push_error("Gallery pointer selection failed")
		get_tree().quit(1)
		return
	guide._article_scroll.scroll_vertical = 10000
	for frame in range(8): await get_tree().process_frame
	var next := gallery.get_node("GalleryPager").get_child(2) as Button
	await pointer.click(next)
	for frame in range(8): await get_tree().process_frame
	if gallery._page != 1:
		push_error("Gallery pointer pagination failed")
		get_tree().quit(1)
		return
	# Keyboard activation on the new page must hand focus to a live pager button.
	next = gallery.get_node("GalleryPager").get_child(2) as Button
	next.grab_focus()
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = pressed
		get_viewport().push_input(key, true)
		await get_tree().process_frame
	for frame in range(8): await get_tree().process_frame
	if gallery._page != 2 or get_viewport().gui_get_focus_owner() == null:
		push_error("Gallery keyboard pagination lost page or focus")
		get_tree().quit(1)
		return
	await pointer.click(guide.get_node("%RulesButton"))
	for frame in range(25): await get_tree().process_frame
	await pointer.click(guide.get_node("%MinigameButton"))
	for frame in range(25): await get_tree().process_frame
	if guide._view_mode != DigitalGameGuide.ViewMode.MINIGAME_GALLERY or guide.theme != MainUI.theme():
		push_error("Gallery return changed theme or destination")
		get_tree().quit(1)
		return
	await pointer.click(guide.get_node("%CloseButton"))
	var deadline := Time.get_ticks_msec() + 2000
	while guide.is_guide_open() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if guide.is_guide_open():
		push_error("Gallery close failed")
		get_tree().quit(1)
		return
	print("MAIN_UI_INPUT gallery: avatar, pointer/keyboard pages, live focus, rules roundtrip, close passed")


func _verify_exit_input(hud: HUD) -> void:
	var dialog := hud._exit_confirmation
	if not get_tree().paused or dialog.get_viewport().gui_get_focus_owner() != dialog.get_cancel_button():
		push_error("Exit confirmation did not pause or focus Continue")
		get_tree().quit(1)
		return
	var pointer = preload("res://tests/helpers/real_pointer_driver.gd").new(dialog.get_viewport(), get_tree())
	await pointer.click(dialog.get_cancel_button())
	await get_tree().process_frame
	if is_instance_valid(hud._exit_confirmation) or get_tree().paused:
		push_error("Continue did not dismiss exit and resume the board")
		get_tree().quit(1)
		return
	var outer_lease := TurnManager.acquire_modal(&"exit_review_outer", TurnManager.ModalResumePolicy.RESUME_REMAINING, true)
	hud._on_close_pressed()
	await get_tree().process_frame
	dialog = hud._exit_confirmation
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = pressed
		if is_instance_valid(dialog): dialog.get_viewport().push_input(key, true)
		await get_tree().process_frame
	if is_instance_valid(hud._exit_confirmation) or not get_tree().paused:
		push_error("Exit Escape did not preserve the outer pause owner")
		get_tree().quit(1)
		return
	TurnManager.release_modal(outer_lease)
	if get_tree().paused:
		push_error("Exit confirmation leaked a pause lease")
		get_tree().quit(1)
		return
	print("MAIN_UI_INPUT exit: Continue pointer, default focus, Escape, nested pause ownership passed")
