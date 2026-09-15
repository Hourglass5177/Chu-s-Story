class_name BoardPanelLayout
extends Node

var _target: Control
var _panel: Control
var _kind: String

static func install(root: Control, kind: String, close_action: Callable) -> void:
	MainUI.apply(root)
	BoardModalGuard.install(root, close_action)
	var panel := root if root is Panel else root.get_node("Panel") as Control
	panel.add_theme_stylebox_override("panel", MainUI.box())
	MainUI.surface(panel, "shop_header" if kind in ["shop", "backpack", "market"] else "detail_header", "HeaderPlaque")
	var old_backdrop := root.get_node_or_null("Panel") as Panel
	if root is Panel and old_backdrop != null: old_backdrop.hide()
	var closing := panel.get_node_or_null("BtnClose") as TextureButton
	if closing != null: MainUI.icon(closing, "close")
	var guide := panel.get_node_or_null("BtnGuide") as Button
	if guide != null: MainUI.guide_button(guide)
	if kind in ["feiyi", "profession", "achievement"]:
		MainUI.surface(panel, "detail_card_frame", "CardFrame")
		MainUI.surface(panel, "content", "ReadingFrame")
	if kind == "shop":
		MainUI.surface(panel, "balance_banner", "BalanceBanner")
	if kind == "feiyi":
		_scroll_labels(root.get_node("VBoxContainer"), ["LblDesc", "LblEffect"])
	elif kind in ["profession", "achievement"]:
		_scroll_labels(panel.get_node("Content/Info"), ["Description"])
	var layout := BoardPanelLayout.new()
	layout._target = root
	layout._panel = panel
	layout._kind = kind
	root.add_child(layout)
	root.get_viewport().size_changed.connect(layout.update_layout)
	layout.update_layout()

func update_layout() -> void:
	_layout(_target, _panel, _kind)

static func _scroll_labels(parent: Control, names: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var first := parent.get_node(names[0])
	parent.move_child(scroll, first.get_index())
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 22)
	scroll.add_child(text)
	for key in names:
		var item := parent.get_node(key) as Label
		item.reparent(text, false)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.size_flags_vertical = Control.SIZE_FILL
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.custom_minimum_size = Vector2(1, 0)
		MainUI.label(item)

static func _layout(root: Control, panel: Control, kind: String) -> void:
	var viewport := root.get_viewport_rect().size
	var dimensions := Vector2(minf(2360, viewport.x - 112), minf(1360, viewport.y - 160))
	if kind == "score": dimensions = Vector2(minf(1500, viewport.x-112), minf(1200, viewport.y-160))
	MainUI.rect(panel, Rect2((viewport - dimensions) * 0.5, dimensions))
	if panel != root: MainUI.fill(root)
	var w := dimensions.x
	var h := dimensions.y
	for title in ["标题", "Title"]:
		var node := panel.get_node_or_null(title) as Label
		if node != null:
			MainUI.rect(node, Rect2(w*0.5-390, 10, 780, 108))
			node.text = node.text.replace("==", "").strip_edges()
			MainUI.label(node, 56, true)
			node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if kind in ["feiyi", "profession", "achievement", "score"]: node.add_theme_color_override("font_color", Color("fff8e4"))
	var closing := panel.get_node_or_null("BtnClose") as Control
	if closing != null: MainUI.rect(closing, Rect2(w-156, 16, 118, 118))
	var guide := panel.get_node_or_null("BtnGuide") as Button
	if guide != null: MainUI.rect(guide, Rect2(54, 20, 220, 108))
	MainUI.rect(panel.get_node("HeaderPlaque"), Rect2(w*0.5-420, -10, 840, 150))
	if kind in ["feiyi", "profession", "achievement"]:
		MainUI.rect(panel.get_node("CardFrame"), Rect2(72,190,w*0.30,h-270))
		MainUI.rect(panel.get_node("ReadingFrame"), Rect2(w*0.35,190,w*0.65-80,h-270))
	match kind:
		"score":
			MainUI.rect(panel.get_node("详情"), Rect2(160, 210, w-320, h-450))
			MainUI.rect(panel.get_node("计分规则"), Rect2(w*0.5-240, h-185, 480, 120))
		"feiyi":
			var picture := root.get_node("TextureRect") as TextureRect
			MainUI.rect(picture, Rect2(112, 240, w*0.30-80, h-370))
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			MainUI.rect(root.get_node("VBoxContainer"), Rect2(w*0.35+48, 236, w*0.65-176, h-370))
			for key in ["LblName","LblCate","LblScore"]:
				var label := root.get_node("VBoxContainer/"+key) as Label
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.size_flags_vertical = Control.SIZE_FILL
				MainUI.label(label, 54 if key == "LblName" else 42)
		"profession", "achievement":
			MainUI.rect(panel.get_node("Content"), Rect2(110, 242, w-228, h-390))
			panel.get_node("Content").add_theme_constant_override("separation", int(w*0.05+18))
			var image_key := "Portrait" if kind == "profession" else "CardImage"
			var picture := panel.get_node("Content/"+image_key) as TextureRect
			picture.custom_minimum_size = Vector2(w*0.30-80, 0)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		"shop":
			MainUI.rect(root.get_node("HBoxContainer"), Rect2(112, 210, w-224, h-300))
			MainUI.rect(root.get_node("余额"), Rect2(w-736, 34, 560, 86))
			MainUI.label(root.get_node("余额"), 44, true)
			root.get_node("余额").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			root.get_node("余额").vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			root.get_node("余额").add_theme_color_override("font_color", Color("fff8e4"))
			MainUI.rect(panel.get_node("BalanceBanner"), Rect2(w-758, 20, 600, 116))
			root.get_node("HBoxContainer").add_theme_constant_override("separation", 42)
			MainUI.rect(root.get_node("BtnRefresh"), Rect2(300, 26, 230, 108))
		"backpack":
			MainUI.rect(root.get_node("ScrollContainer"), Rect2(112, 204, w-224, h-286))
			root.get_node("ScrollContainer/GridContainer").columns = 3
			root.get_node("ScrollContainer/GridContainer").add_theme_constant_override("h_separation", 42)
			root.get_node("ScrollContainer/GridContainer").add_theme_constant_override("v_separation", 36)
		"market":
			MainUI.rect(root.get_node("状态栏"), Rect2(120, 162, w-240, 76))
			MainUI.rect(root.get_node("页签"), Rect2(114, 250, w-228, 112))
			MainUI.rect(root.get_node("ScrollContainer"), Rect2(830, 394, w-930, h-480))
			if root.has_node("SelectedPreview"):
				MainUI.rect(root.get_node("SelectedPreview"), Rect2(92, 394, 690, h-480))
