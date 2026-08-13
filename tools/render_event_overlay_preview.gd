extends Node

const OUTPUT_PATH := "res://tmp/event-overlay-validation.png"
const STRESS_OUTPUT_PATH := "res://tmp/event-overlay-stress-validation.png"

func _ready() -> void:
	await _render_preview()

func _render_preview() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560, 1600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var background := ColorRect.new()
	background.color = Color("314254")
	background.position = Vector2.ZERO
	background.size = Vector2(viewport.size)
	viewport.add_child(background)

	var overlay := (load("res://HUDs/event_overlay.tscn") as PackedScene).instantiate() as EventOverlay
	background.add_child(overlay)
	await get_tree().process_frame

	var player := PlayerClass.new()
	player.player_name = "界面验证玩家"
	var stress_preview := "--stress-preview" in OS.get_cmdline_user_args()
	var card_path := "res://Cards/事件牌/坐收渔利.tres" if stress_preview else "res://Cards/事件牌/倦艺休整.tres"
	var card := load(card_path) as 事件牌
	overlay._on_event_revealed(player, card)
	var request: EventChoiceRequest
	if stress_preview:
		request = EventChoiceRequest.new(
			player,
			"选择一名合法玩家作为事件目标。目标不足时执行最大合法数量；积分并列、距离并列和禁止状态均按数字版通用裁定处理。",
			[0, 1, 2, 3, 4, 5],
			PackedStringArray(["验证甲 · 美食博主", "验证乙 · 商业博主", "验证丙 · 旅行博主", "验证丁 · 魔术博主", "验证戊 · 探险博主", "验证己 · 生活博主"]),
			true,
			EventChoiceRequest.ChoiceKind.玩家
		)
	else:
		request = EventChoiceRequest.new(
			player,
			"是否跳过本回合行动阶段并恢复3点精力？\n若弃置一张食物牌，还可额外恢复2点精力。",
			[true, false],
			PackedStringArray(["接受休整", "拒绝并继续行动"]),
			false,
			EventChoiceRequest.ChoiceKind.选项
		)
	request.request_id = 1
	request.timeout_seconds = 15.0
	overlay._on_choice_requested(request)
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame

	var image := viewport.get_texture().get_image()
	var output_path := STRESS_OUTPUT_PATH if stress_preview else OUTPUT_PATH
	var error := image.save_png(output_path)
	if error != OK:
		push_error("事件 UI 预览保存失败：%s" % error_string(error))
		get_tree().quit(1)
		return
	print("事件 UI 预览已保存：", ProjectSettings.globalize_path(output_path))
	player.free()
	get_tree().quit()
