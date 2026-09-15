extends VBoxContainer
class_name FoodCardView

signal action_requested(card: 食物牌)
signal guide_requested(card: 食物牌, source: Control)

var card: 食物牌
var icon: TextureButton
var info_label: Label
var action_button: Button
var _face_recorded: bool = false
var _content: VBoxContainer

func _draw() -> void:
	MainUI.box("card", 0).draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


func _ready() -> void:
	resized.connect(queue_redraw)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	if _face_recorded or card == null or not is_visible_in_tree() or modulate.a <= 0.01:
		return
	_face_recorded = true
	set_process(false)
	DiscoveryManager.record_food_face_presented(card)

func setup(
	p_card: 食物牌,
	font: Font,
	action_text: String,
	disabled: bool,
	show_price: bool = false
) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(620, 1090)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_"+side, 38)
	add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	margin.add_child(_content)
	card = p_card
	_face_recorded = false
	set_process(true)
	add_theme_constant_override("separation", 10)
	set_meta("card_data", card)
	icon = TextureButton.new()
	icon.texture_normal = card.image_of_front
	icon.custom_minimum_size = Vector2(0, 600)
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	icon.focus_mode = Control.FOCUS_ALL
	icon.tooltip_text = "查看%s" % card.card_name
	icon.pressed.connect(func() -> void: guide_requested.emit(card, icon))
	_content.add_child(icon)
	info_label = Label.new()
	info_label.text = "%s\n%d 积分点" % [card.card_name, card.cost] if show_price else card.card_name
	if font != null:
		info_label.add_theme_font_override("font", font)
	info_label.add_theme_font_size_override("font_size", 40)
	info_label.add_theme_color_override("font_color", Color.BLACK)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MainUI.label(info_label, 48, true)
	info_label.custom_minimum_size.y = 150 if show_price else 80
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(info_label)
	var effect := Label.new()
	effect.text = card.effect_description
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.custom_minimum_size = Vector2(1, 112)
	effect.max_lines_visible = 2
	effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect.tooltip_text = card.effect_description
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MainUI.label(effect, 36)
	_content.add_child(effect)
	action_button = Button.new()
	action_button.text = action_text
	if font != null:
		action_button.add_theme_font_override("font", font)
	action_button.add_theme_font_size_override("font_size", 40)
	action_button.disabled = disabled
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_button.pressed.connect(func(): action_requested.emit(card))
	MainUI.button(action_button)
	action_button.custom_minimum_size = Vector2(360, 124)
	MainUI.label(action_button, 48, true)
	_content.add_child(action_button)
