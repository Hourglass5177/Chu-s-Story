extends PanelContainer
class_name FoodTooltip

const HOVER_DELAY: float = 0.6
const OFFSET := Vector2(22, 26)
const MIN_PANEL_WIDTH: float = 220.0
const MAX_PANEL_WIDTH: float = 540.0
const HORIZONTAL_PADDING: float = 36.0
const VERTICAL_PADDING: float = 26.0
const MIN_PANEL_HEIGHT: float = 70.0

var _label: Label
var _timer: Timer
var _target: Control = null
var _card: 食物牌 = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8e8bd")
	style.border_color = Color("8a4d2f")
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color("503025"))
	_label.add_theme_font_size_override("font_size", 30)
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = HOVER_DELAY
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_show_for_target)
	add_child(_timer)
	hide()
	set_process(true)

func bind(target: Control, card: 食物牌) -> void:
	if target == null or card == null:
		return
	target.mouse_entered.connect(_on_target_entered.bind(target, card))
	target.mouse_exited.connect(_on_target_exited.bind(target))
	target.tree_exiting.connect(_on_target_exited.bind(target))

func set_display_font(font: Font) -> void:
	if _label != null and font != null:
		_label.add_theme_font_override("font", font)

func _on_target_entered(target: Control, card: 食物牌) -> void:
	_target = target
	_card = card
	hide()
	_timer.start(HOVER_DELAY)

func _on_target_exited(target: Control) -> void:
	if target != _target:
		return
	_timer.stop()
	_target = null
	_card = null
	hide()

func _show_for_target() -> void:
	if _target == null or _card == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return
	_fit_to_text(_card.effect_description)
	show()
	_update_position()

func _fit_to_text(text: String) -> void:
	_label.text = text
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	var min_content_width := MIN_PANEL_WIDTH - HORIZONTAL_PADDING
	var max_content_width := MAX_PANEL_WIDTH - HORIZONTAL_PADDING
	var natural_width := font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var content_width := clampf(natural_width, min_content_width, max_content_width)
	var line_count := 1
	if natural_width > max_content_width:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line_count = _count_wrapped_lines(text, font, font_size, max_content_width)
	else:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	var line_height := ceilf(font.get_height(font_size) * 1.18)
	var text_height := line_height * line_count
	var panel_size := Vector2(
		content_width + HORIZONTAL_PADDING,
		maxf(text_height + VERTICAL_PADDING, MIN_PANEL_HEIGHT)
	)
	_label.custom_minimum_size = Vector2(content_width, text_height)
	custom_minimum_size = panel_size
	size = panel_size

func _count_wrapped_lines(text: String, font: Font, font_size: int, max_width: float) -> int:
	var lines := 1
	var current_line := ""
	for character: String in text:
		if character == "\n":
			lines += 1
			current_line = ""
			continue
		var candidate := current_line + character
		if not current_line.is_empty() and font.get_string_size(
			candidate,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x > max_width:
			lines += 1
			current_line = character
		else:
			current_line = candidate
	return lines

func _process(_delta: float) -> void:
	if visible:
		_update_position()

func _update_position() -> void:
	var viewport_size := get_viewport_rect().size
	var desired := get_viewport().get_mouse_position() + OFFSET
	var measured := size
	if measured.x <= 0.0 or measured.y <= 0.0:
		measured = Vector2(MIN_PANEL_WIDTH, MIN_PANEL_HEIGHT)
	desired.x = clampf(desired.x, 8.0, maxf(viewport_size.x - measured.x - 8.0, 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(viewport_size.y - measured.y - 8.0, 8.0))
	global_position = desired
