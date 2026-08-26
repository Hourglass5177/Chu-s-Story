extends VBoxContainer
class_name FoodCardView

signal action_requested(card: 食物牌)
signal guide_requested(card: 食物牌, source: Control)

var card: 食物牌
var icon: TextureButton
var info_label: Label
var action_button: Button
var _face_recorded: bool = false


func _ready() -> void:
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
	card = p_card
	_face_recorded = false
	set_process(true)
	add_theme_constant_override("separation", 10)
	set_meta("card_data", card)
	icon = TextureButton.new()
	icon.texture_normal = card.image_of_front
	icon.custom_minimum_size = Vector2(400, 500)
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	icon.focus_mode = Control.FOCUS_ALL
	icon.tooltip_text = "查看%s" % card.card_name
	icon.pressed.connect(func() -> void: guide_requested.emit(card, icon))
	add_child(icon)
	info_label = Label.new()
	info_label.text = "%s\n￥%d" % [card.card_name, card.cost] if show_price else card.card_name
	if font != null:
		info_label.add_theme_font_override("font", font)
	info_label.add_theme_font_size_override("font_size", 64)
	info_label.add_theme_color_override("font_color", Color.BLACK)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(info_label)
	action_button = Button.new()
	action_button.text = action_text
	if font != null:
		action_button.add_theme_font_override("font", font)
	action_button.add_theme_font_size_override("font_size", 64)
	action_button.disabled = disabled
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_button.pressed.connect(func(): action_requested.emit(card))
	add_child(action_button)
