class_name TutorialOverlay
extends Control

const GUIDE_ART := preload("res://arts/素材合集/sprite及立绘/水墨风格立绘/旅行博主.png")

signal primary_requested
signal exit_requested
signal hint_requested

var badge: Label
var prompt: Label
var hint: Button
var strip: PanelContainer
var keycap: Label
var portrait: TextureRect
var modal: PanelContainer
var modal_title: Label
var modal_text: Label
var illustration: TextureRect
var primary: Button
var secondary: Button
var rules: Button
var shade: ColorRect
var highlight := Rect2()
var unit := 1.0
var flash := 0.0
var instruction_rect := Rect2()
var _labels: Array[Label] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL
	theme = MainUI.theme()
	badge = _label("入门教学", 24)
	add_child(badge)
	badge.z_index = 5
	var badge_paper := _paper()
	badge_paper.content_margin_left = 14
	badge_paper.content_margin_right = 14
	badge_paper.content_margin_top = 6
	badge_paper.content_margin_bottom = 6
	badge.add_theme_stylebox_override("normal", badge_paper)
	badge.add_theme_color_override("font_color", Color("276b70"))
	strip = PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", _paper())
	add_child(strip)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	strip.add_child(row)
	portrait = TextureRect.new()
	var face := AtlasTexture.new()
	face.atlas = GUIDE_ART
	face.region = Rect2(400, 200, 960, 960)
	portrait.texture = face
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	prompt = _label("", 24)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prompt)
	keycap = _label("左键\n点击", 20)
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keycap.add_theme_stylebox_override("normal", _paper())
	row.add_child(keycap)
	hint = _button("看提示")
	hint.pressed.connect(func() -> void: hint_requested.emit())
	row.add_child(hint)
	hint.hide()
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.12, 0.09, 0.05, 0.56)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", MainUI.box("panel", 44))
	add_child(modal)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	modal.add_child(content)
	modal_title = _label("", 32)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(modal_title)
	illustration = TextureRect.new()
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(illustration)
	modal_text = _label("", 24)
	modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(modal_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	content.add_child(buttons)
	primary = _button("开始练习")
	secondary = _button("返回主菜单")
	buttons.add_child(primary)
	buttons.add_child(secondary)
	primary.pressed.connect(func() -> void: primary_requested.emit())
	secondary.pressed.connect(func() -> void: exit_requested.emit())
	rules = _button("查看详细规则")
	rules.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(rules)
	rules.hide()
	resized.connect(layout)
	layout()

func _paper() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff2d6")
	style.border_color = Color("bc9056")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _label(value: String, points: int) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_meta(&"points", points)
	_labels.append(label)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.theme = MainUI.theme()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

func layout() -> void:
	if not is_instance_valid(badge): return
	unit = minf(size.x / 1120.0, size.y / 720.0)
	for label in _labels:
		MainUI.label(label, roundi(float(label.get_meta(&"points")) * unit), label == modal_title)
	badge.add_theme_color_override("font_color", Color("276b70"))
	for button in [hint, primary, secondary, rules]:
		button.add_theme_font_size_override("font_size", roundi(24 * unit))
		button.custom_minimum_size = Vector2(160, 48) * unit
	primary.custom_minimum_size.x = 220 * unit
	secondary.custom_minimum_size.x = 180 * unit
	keycap.custom_minimum_size = Vector2(92, 52) * unit
	portrait.custom_minimum_size = Vector2(64, 64) * unit
	badge.position = Vector2(30, 76) * unit
	badge.size = Vector2(460, 34) * unit
	var box := instruction_rect
	if box.size.x < 1: box = Rect2(Vector2(30, size.y / unit - 116) * unit, Vector2(640, 86) * unit)
	strip.position = box.position
	strip.size = box.size
	hint.custom_minimum_size = Vector2(108, 48) * unit
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	modal.position = (size - Vector2(940, 590) * unit) / 2
	modal.size = Vector2(940, 590) * unit
	illustration.custom_minimum_size.y = (285 if illustration.texture != null else 100) * unit
	queue_redraw()

func show_page(title: String, text: String, action: String, picture: Texture2D = null) -> void:
	modal_title.text = title
	modal_text.text = text
	illustration.texture = picture if picture != null else GUIDE_ART
	modal.show()
	badge.hide()
	shade.show()
	primary.text = action
	primary.disabled = false
	rules.hide()
	strip.hide()
	hint.hide()
	highlight = Rect2()
	layout()
	layout.call_deferred()
	primary.call_deferred(&"grab_focus")

func close_page() -> void:
	modal.hide()
	badge.show()
	shade.hide()
	strip.show()
	queue_redraw()

func set_input_device(device: StringName) -> void:
	keycap.text = "Enter\n确认" if device == &"keyboard" else ("南键\n确认" if device == &"gamepad" else "左键\n点击")

func set_step(step: int, text: String) -> void:
	badge.text = "入门教学  ·  %d/7  %s" % [mini(step + 1, 7), TutorialDefinition.TITLES[step]]
	prompt.text = text
	hint.hide()
	flash = 0.3
	queue_redraw()

func _draw() -> void:
	if highlight.size.x > 0 and not modal.visible:
		draw_rect(highlight.grow(5 * unit), Color("daaa52"), false, (3.0 + flash * 5.0) * unit)
		var point := highlight.get_center() - Vector2(0, highlight.size.y * 0.5 + 14 * unit)
		draw_colored_polygon(PackedVector2Array([point, point + Vector2(-8,-12)*unit, point+Vector2(8,-12)*unit]), Color("276b70"))
