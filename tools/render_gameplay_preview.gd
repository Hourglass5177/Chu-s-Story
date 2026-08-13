extends Node

const OUTPUT_PATH := "res://tmp/gameplay-hud-validation.png"
const EVENT_OUTPUT_PATH := "res://tmp/gameplay-event-validation.png"

func _ready() -> void:
	var interactive_timeout_test := "--interactive-preview" in OS.get_cmdline_user_args()
	var retained_hand_preview := "--retained-hand-preview" in OS.get_cmdline_user_args()
	var market_preview := "--market-preview" in OS.get_cmdline_user_args()
	GameManager.player_data = [
		{"name": "验证甲", "job": "美食博主", "location": "十堰"},
		{"name": "验证乙", "job": "商业博主", "location": "随州"},
	]
	var game_scene := load("res://main_map.tscn") as PackedScene
	var game := game_scene.instantiate()
	add_child(game)
	for _frame in 8:
		await get_tree().process_frame
	var hud := get_tree().get_first_node_in_group("HUD") as HUD
	var player := TurnManager.players[TurnManager.now_player_index]
	if retained_hand_preview:
		player.事件牌手牌.assign([
			load("res://Cards/事件牌/妙手回春.tres") as 事件牌,
			load("res://Cards/事件牌/游目骋怀.tres") as 事件牌,
			load("res://Cards/事件牌/畅行无阻.tres") as 事件牌,
		])
		TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
		hud.refresh_event_list(player)
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var hud_output_path := "res://tmp/gameplay-retained-hand-validation.png" if retained_hand_preview else OUTPUT_PATH
	var error := image.save_png(hud_output_path)
	if error != OK:
		push_error("游戏 HUD 预览保存失败：%s" % error_string(error))
		get_tree().quit(1)
		return
	print("游戏 HUD 预览已保存：", ProjectSettings.globalize_path(hud_output_path))
	if market_preview:
		TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
		player.arrival_id = 1
		MarketManager.deposit_card(load("res://Cards/非遗牌/鄂州/牌子锣.tres") as 非遗牌, &"preview")
		MarketManager.deposit_card(load("res://Cards/非遗牌/襄阳/唢呐艺术.tres") as 非遗牌, &"preview")
		MarketManager.begin_visit(player, player.arrival_id)
		hud.open_market_panel(player)
		for _frame in 3:
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var market_image := get_viewport().get_texture().get_image()
		var market_error := market_image.save_png("res://tmp/gameplay-market-validation.png")
		if market_error != OK:
			push_error("研究所 UI 预览保存失败：%s" % error_string(market_error))
			get_tree().quit(1)
			return
		print("研究所 UI 预览已保存：", ProjectSettings.globalize_path("res://tmp/gameplay-market-validation.png"))
		print("研究所模态状态：阶段=", TurnManager.TurnPhase.find_key(TurnManager.now_phase), "，计时器暂停=", TurnManager.turn_timer.is_stopped(), "，模态深度=", TurnManager.modal_resolution_depth)
		get_tree().quit()
		return

	if retained_hand_preview:
		hud.get_event_overlay().show_retained_card_detail(player, player.事件牌手牌[0])
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var detail_image := get_viewport().get_texture().get_image()
		var detail_error := detail_image.save_png("res://tmp/gameplay-retained-detail-validation.png")
		if detail_error != OK:
			push_error("保留事件牌详情预览保存失败：%s" % error_string(detail_error))
		hud.get_event_overlay().close_retained_card_detail()
		get_tree().quit()
		return

	if interactive_timeout_test:
		await _run_real_timeout_test(hud, player)
		get_tree().quit()
		return

	var card := load("res://Cards/事件牌/倦艺休整.tres") as 事件牌
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	TurnManager.begin_modal_resolution()
	EventManager.event_revealed.emit(player, card)
	var request := EventChoiceRequest.new(
		player,
		"是否跳过本回合行动阶段并恢复3点精力？\n若弃置一张食物牌，还可额外恢复2点精力。",
		[true, false],
		PackedStringArray(["接受休整", "拒绝并继续行动"]),
		false,
		EventChoiceRequest.ChoiceKind.选项
	)
	request.request_id = 2
	request.timeout_seconds = 15.0
	EventManager.choice_requested.emit(request)
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var event_image := get_viewport().get_texture().get_image()
	var event_error := event_image.save_png(EVENT_OUTPUT_PATH)
	if event_error != OK:
		push_error("游戏事件 UI 预览保存失败：%s" % error_string(event_error))
		get_tree().quit(1)
		return
	print("游戏事件 UI 预览已保存：", ProjectSettings.globalize_path(EVENT_OUTPUT_PATH))
	print("事件层可见：", hud.get_event_overlay().visible)
	print("普通按钮禁用状态：行动=", hud.btn_action.disabled, "，食物=", hud.btn_food.disabled, "，结束回合=", hud.btn_end_turn.disabled)
	print("事件模态运行状态：阶段=", TurnManager.TurnPhase.find_key(TurnManager.now_phase), "，计时器暂停=", TurnManager.turn_timer.is_stopped(), "，模态深度=", TurnManager.modal_resolution_depth)
	get_tree().quit()


func _run_real_timeout_test(hud: HUD, player: PlayerClass) -> void:
	var card := load("res://Cards/事件牌/精疲力尽.tres") as 事件牌
	TurnManager.change_phase(TurnManager.TurnPhase.ACTION)
	var started_at := Time.get_ticks_msec()
	EventManager.resolve_event(player, card)
	await get_tree().process_frame
	print(
		"真实超时测试开始：阶段=%s，计时器暂停=%s，模态深度=%d，弹窗可见=%s，精力=%d"
		% [
			TurnManager.TurnPhase.find_key(TurnManager.now_phase),
			TurnManager.turn_timer.is_stopped(),
			TurnManager.modal_resolution_depth,
			hud.get_event_overlay().visible,
			player.current_energy,
		]
	)
	await EventManager.event_finished
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var after_image := get_viewport().get_texture().get_image()
	var after_error := after_image.save_png("res://tmp/gameplay-event-timeout-after.png")
	if after_error != OK:
		push_error("真实事件超时后截图保存失败：%s" % error_string(after_error))
	var elapsed_seconds := float(Time.get_ticks_msec() - started_at) / 1000.0
	print(
		"真实超时测试结束：耗时=%.2f秒，阶段=%s，计时器暂停=%s，剩余=%.2f，模态深度=%d，弹窗可见=%s，精力=%d"
		% [
			elapsed_seconds,
			TurnManager.TurnPhase.find_key(TurnManager.now_phase),
			TurnManager.turn_timer.is_stopped(),
			TurnManager.turn_timer.time_left,
			TurnManager.modal_resolution_depth,
			hud.get_event_overlay().visible,
			player.current_energy,
		]
	)
