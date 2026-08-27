extends PanelContainer
class_name GuideVisualDemo

signal media_preview_requested(texture: Texture2D, alt_text: String)

## Authored visual sequence used only when a guide topic explicitly declares
## matching media. Missing assets stay missing: unrelated screenshots must never
## be substituted into a rule page.

const MAP_IMAGE := "res://arts/地图/地图完整版.png"
const EVENT_BACK := "res://arts/事件卡/事件牌（牌背）.png"
const FEIYI_CARD := "res://arts/非遗卡牌/武汉/汉绣.jpg"
const POINT_IMAGE := "res://arts/积分点/500积分点.png"
const FOOD_BACK := "res://arts/食物牌/食物牌（牌背）.jpg"
const GUIDE_SCREEN_DIR := "res://arts/游戏指南/实机截图/v1"
const GAMEPLAY_SCREEN := GUIDE_SCREEN_DIR + "/对局全景.png"
const MODE_SCREEN := GUIDE_SCREEN_DIR + "/模式选择.png"
const PLAYER_SETUP_SCREEN := GUIDE_SCREEN_DIR + "/玩家设置.png"
const EVENT_SCREEN := GUIDE_SCREEN_DIR + "/事件选择.png"
const SHOP_SCREEN := GUIDE_SCREEN_DIR + "/食物商店.png"
const MARKET_SCREEN := GUIDE_SCREEN_DIR + "/非遗研究所.png"
const SCORE_SCREEN := GUIDE_SCREEN_DIR + "/计分详情.png"

const SPECS: Dictionary = {
	&"home_hero": {"title": "从桌面认识一局《楚物志》", "steps": ["玩家信息", "地图与提示", "手牌与总分"], "asset": GAMEPLAY_SCREEN},
	&"quick_turn_flow": {"title": "一回合这样走", "steps": ["准备", "掷骰", "移动", "行动", "结束"], "asset": GAMEPLAY_SCREEN},
	&"quick_move_comparison": {"title": "路线不只看步数", "steps": ["看剩余步数", "比较地形消耗", "选择终点"], "asset": MAP_IMAGE},
	&"session_modes": {"title": "先选择游玩方式", "steps": ["开始游戏", "本地游戏", "配置玩家"], "asset": MODE_SCREEN},
	&"session_player_setup": {"title": "逐位确认阵容", "steps": ["名字", "职业", "起点", "阵容确认"], "asset": PLAYER_SETUP_SCREEN},
	&"session_initial_hud": {"title": "开局先认清三样东西", "steps": ["积分点", "精力", "手牌"], "asset": GAMEPLAY_SCREEN},
	&"interface_overview": {"title": "界面信息从左到右", "steps": ["玩家状态", "地图与提示", "手牌与总分"], "asset": GAMEPLAY_SCREEN},
	&"turn_zero_energy_timeline": {"title": "精力归零不会立刻淘汰", "steps": ["移动后为 0", "仍进入行动", "回合结束再判断"], "asset": FOOD_BACK},
	&"map_camera_modes": {"title": "两种观察方式", "steps": ["全局：自由拖拽", "追踪：跟随棋子", "ALT 切换"], "asset": MAP_IMAGE},
	&"functional_feiyi_collect": {"title": "收集非遗", "steps": ["到达非遗点", "支付精力", "牌进入手牌"], "asset": FEIYI_CARD},
	&"functional_scenery": {"title": "打卡风景", "steps": ["到达风景", "首次打卡", "恢复精力"], "asset": MAP_IMAGE},
	&"functional_event": {"title": "公开并结算事件", "steps": ["抽取事件", "作出选择", "继续行动"], "asset": EVENT_SCREEN},
	&"functional_shop": {"title": "在小吃商店购买", "steps": ["查看商品", "支付积分点", "食物入手"], "asset": SHOP_SCREEN},
	&"functional_work": {"title": "打工换取积分点", "steps": ["到达打工格", "支付精力", "领取工资"], "asset": POINT_IMAGE},
	&"functional_market": {"title": "研究所共享库存", "steps": ["出售非遗", "库存更新", "其他入口可购买"], "asset": MARKET_SCREEN},
	&"feiyi_categories": {"title": "非遗按地域与类别收藏", "steps": ["看地域边框", "看类别标记", "组成收藏"], "asset": FEIYI_CARD},
	&"feiyi_hand_flow": {"title": "手牌会获得、使用与转移", "steps": ["获得", "持有", "使用或转移", "离开手牌"], "asset": FEIYI_CARD},
	&"event_response_chain": {"title": "响应只改变被作用的部分", "steps": ["效果指向玩家", "抵消或转移", "新目标可再响应", "最终结算"], "asset": EVENT_BACK},
	&"event_movement_sequence": {"title": "事件移动按牌面执行", "steps": ["选择目标", "地图标出终点", "移动并反馈结果"], "asset": MAP_IMAGE},
	&"market_price_example": {"title": "研究所买卖价不同", "steps": ["出售：获得售价", "库存保留牌", "购买：支付双倍"], "asset": POINT_IMAGE},
	&"score_breakdown": {"title": "所有得分汇入总分", "steps": ["非遗基础分", "地域与类别组合", "成就分", "总分"], "asset": SCORE_SCREEN},
	&"region_combo_hud": {"title": "地域组合会在手牌区提示", "steps": ["收集同一地域", "满足组合", "提示得分"], "asset": FEIYI_CARD},
	&"elimination_zero_energy": {"title": "回合末才进行淘汰判断", "steps": ["行动阶段可恢复", "结束回合", "精力仍为 0 才淘汰"], "asset": FOOD_BACK},
	&"final_results_sequence": {"title": "结算逐项揭晓", "steps": ["分项计分", "排名重排", "冠军揭晓"], "asset": POINT_IMAGE},
}


func setup(
	dynamic_id: StringName,
	layout: String,
	alt: String,
	narrow_layout: bool,
	declared_id: StringName = &"",
	declared_paths: Array = [],
	declared_captions: Array = []
) -> void:
	name = "GuideVisualDemo"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 260 if narrow_layout else 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F5E2B9"), Color(FrontendStyle.GOLD, 0.72), 2, 16, Vector4(20, 18, 20, 18)))
	set_meta(&"guide_media_path", "")
	set_meta(&"guide_media_layout", layout)
	set_meta(&"guide_media_kind", &"guide_capture")
	var media_id := declared_id if not declared_id.is_empty() else dynamic_id
	set_meta(&"guide_media_id", media_id)
	var spec := SPECS.get(dynamic_id, {}) as Dictionary
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	add_child(content)
	var title := String(spec.get("title", alt if not alt.is_empty() else "规则演示"))
	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", FrontendStyle.BROWN_DARK)
	content.add_child(title_label)
	var asset_paths := _resolve_asset_paths(spec, declared_paths)
	if dynamic_id == &"quick_turn_flow":
		_build_round_flow(content, asset_paths, alt, narrow_layout, media_id)
		return
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 12)
	content.add_child(stage)
	var pair_layout := layout.to_lower() == "pair" and not narrow_layout and asset_paths.size() > 1
	var image_group: Container = HBoxContainer.new() if pair_layout else VBoxContainer.new()
	image_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_group.add_theme_constant_override("separation", 14)
	stage.add_child(image_group)
	for index: int in range(asset_paths.size()):
		var asset_path := asset_paths[index]
		var preview_alt := alt if not alt.is_empty() else title
		var caption := String(declared_captions[index]).strip_edges() if index < declared_captions.size() else ""
		if asset_paths.size() > 1:
			preview_alt = "%s（%d/%d）" % [preview_alt, index + 1, asset_paths.size()]
		_add_asset_preview(
			image_group,
			asset_path,
			layout,
			media_id,
			preview_alt,
			300 if narrow_layout else (360 if pair_layout else 460),
			caption
		)
	var steps: Array = spec.get("steps", ["查看示意", "阅读规则", "回到游戏"]) as Array
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	stage.add_child(flow)
	for index: int in range(steps.size()):
		if index > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_size_override("font_size", 28)
			arrow.add_theme_color_override("font_color", FrontendStyle.BROWN_MUTED)
			flow.add_child(arrow)
		var chip := Label.new()
		chip.text = String(steps[index])
		chip.custom_minimum_size = Vector2(170, 64)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chip.add_theme_font_size_override("font_size", 27)
		chip.add_theme_color_override("font_color", FrontendStyle.BROWN_DARK)
		chip.add_theme_stylebox_override("normal", FrontendStyle.make_box(Color("#FFF4D8"), Color(FrontendStyle.GOLD, 0.62), 2, 11, Vector4(11, 8, 11, 8)))
		flow.add_child(chip)


func _build_round_flow(
	parent: VBoxContainer,
	asset_paths: Array[String],
	alt: String,
	narrow_layout: bool,
	media_id: StringName
) -> void:
	var phases: Array[Dictionary] = [
		{"title": "准备", "note": "处理回合开始效果"},
		{"title": "掷骰", "note": "投 2D6，得到基础步数"},
		{"title": "移动", "note": "选择蓝色终点"},
		{"title": "行动", "note": "处理落点并使用卡牌"},
		{"title": "结束", "note": "结算回合末并交接"},
	]
	var phase_flow: Container = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	phase_flow.name = "RoundFlow"
	phase_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_flow.add_theme_constant_override("separation", 10)
	parent.add_child(phase_flow)
	for index: int in range(phases.size()):
		if index > 0:
			var arrow := Label.new()
			arrow.text = "↓" if narrow_layout else "→"
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			arrow.custom_minimum_size = Vector2(42, 42)
			arrow.add_theme_font_size_override("font_size", 30)
			arrow.add_theme_color_override("font_color", FrontendStyle.ORANGE)
			phase_flow.add_child(arrow)
		var phase := phases[index]
		var card := PanelContainer.new()
		card.name = "RoundPhase%s" % String(phase.title)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0 if narrow_layout else 136, 112 if narrow_layout else 132)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override(
			"panel",
			FrontendStyle.make_box(
				Color("#FFF4D8"),
				Color(FrontendStyle.GOLD, 0.66),
				2,
				12,
				Vector4(12, 10, 12, 10)
			)
		)
		phase_flow.add_child(card)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 7)
		card.add_child(column)
		var phase_title := Label.new()
		phase_title.text = String(phase.title)
		phase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		phase_title.add_theme_font_size_override("font_size", 30)
		phase_title.add_theme_color_override("font_color", FrontendStyle.BROWN_DARK)
		column.add_child(phase_title)
		var note := Label.new()
		note.text = String(phase.note)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.size_flags_vertical = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 24 if narrow_layout else 22)
		note.add_theme_color_override("font_color", FrontendStyle.BROWN)
		column.add_child(note)

	# The five-stage ribbon explains order. The three stages requiring player
	# input receive a second, larger row of audited visuals, instead of squeezing
	# screenshots into five narrow columns.
	var visual_titles := ["掷骰", "移动", "行动"]
	var visual_group: Container = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	visual_group.name = "RoundInteractionVisuals"
	visual_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual_group.add_theme_constant_override("separation", 16)
	parent.add_child(visual_group)
	for asset_index: int in range(mini(asset_paths.size(), visual_titles.size())):
		_add_asset_preview(
			visual_group,
			asset_paths[asset_index],
			"sequence",
			media_id,
			"%s · %s" % [alt, visual_titles[asset_index]],
			360 if narrow_layout else 260,
			String(visual_titles[asset_index])
		)


func _resolve_asset_paths(_spec: Dictionary, declared_paths: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_path: Variant in declared_paths:
		var path := String(raw_path)
		if not path.is_empty() and ResourceLoader.exists(path) and not result.has(path):
			result.append(path)
	return result


func _add_asset_preview(
	parent: Container,
	asset_path: String,
	layout: String,
	media_id: StringName,
	alt_text: String,
	minimum_height: int,
	caption: String = ""
) -> void:
	var texture := load(asset_path) as Texture2D
	if texture == null:
		return
	var item := VBoxContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_constant_override("separation", 8)
	parent.add_child(item)
	var image_holder := PanelContainer.new()
	image_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_holder.custom_minimum_size.y = minimum_height
	image_holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	item.add_child(image_holder)
	var image := TextureRect.new()
	image.name = "GuideVisualAsset"
	image.texture = texture
	image.custom_minimum_size = Vector2.ZERO
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The holder defines an equal storyboard slot. Ignoring the texture's native
	# minimum keeps portrait and landscape captures from stealing width from one
	# another, while KEEP_ASPECT_CENTERED preserves every image's proportions.
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_meta(&"guide_media_path", asset_path)
	image.set_meta(&"guide_media_layout", layout)
	image.set_meta(&"guide_media_kind", &"guide_capture")
	image.set_meta(&"guide_media_id", media_id)
	image_holder.add_child(image)
	image_holder.add_child(_make_preview_button(texture, alt_text))
	if not caption.is_empty():
		var caption_label := Label.new()
		caption_label.text = caption
		caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption_label.add_theme_font_size_override("font_size", 27)
		caption_label.add_theme_color_override("font_color", FrontendStyle.BROWN_MUTED)
		item.add_child(caption_label)


func _make_preview_button(texture: Texture2D, alt_text: String) -> Button:
	var button := Button.new()
	button.name = "GuideMediaPreviewButton"
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(96, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.accessibility_name = "查看大图"
	button.accessibility_description = alt_text
	button.add_theme_stylebox_override("normal", _preview_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _preview_style(Color(FrontendStyle.GOLD, 0.08), Color(FrontendStyle.GOLD, 0.9), 3))
	button.add_theme_stylebox_override("focus", _preview_style(Color(FrontendStyle.GOLD, 0.05), Color("#FFF1C7"), 5))
	button.add_theme_stylebox_override("pressed", _preview_style(Color(FrontendStyle.ORANGE, 0.12), Color(FrontendStyle.GOLD), 4))
	button.pressed.connect(func() -> void: media_preview_requested.emit(texture, alt_text))
	return button


func _preview_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	return style
