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
	if page in ["home", "mode", "local_count", "guide", "guide_topic", "compendium", "player_setup", "player_setup_bot", "roster"]:
		var menu := load("res://main_menu.tscn").instantiate() as MainMenu
		add_child(menu)
		await get_tree().process_frame
		if page in ["player_setup", "player_setup_bot", "roster"]:
			menu.set_local_player_counts(2, 1)
			for index in range(3):
				menu._draft.players[index].profession_type = index
				menu._draft.players[index].starting_region = [MapSection.REGION.十堰, MapSection.REGION.随州, MapSection.REGION.孝感][index]
		if page in ["guide", "guide_topic", "compendium"]:
			menu.open_game_guide()
			if page == "compendium": menu.get_game_guide()._render_compendium(DiscoveryManager.KIND_FEIYI, 0)
			if page == "guide_topic": menu.get_game_guide()._open_topic_by_index(&"quick", 0)
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
		var hotspots := setup.birthplace_hotspots.get_children()
		for index in range(hotspots.size()):
			for other in range(index + 1, hotspots.size()):
				if hotspots[index].get_global_rect().intersects(hotspots[other].get_global_rect()):
					push_error("UI layout: birthplace labels overlap %s %s / %s %s" % [hotspots[index].name, hotspots[index].get_global_rect(), hotspots[other].name, hotspots[other].get_global_rect()])
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

func _verify_board_input(page: String) -> void:
	var hud := get_tree().get_first_node_in_group("HUD") as HUD
	if hud == null: return
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
