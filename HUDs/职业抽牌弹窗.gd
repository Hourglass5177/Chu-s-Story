extends Control
class_name ProfessionDrawPanel

@onready var context_label: Label = $Frame/Header/Context
@onready var countdown_label: Label = $Frame/Header/Countdown
@onready var cards_row: HBoxContainer = $Frame/CardsRow
@onready var confirm_button: Button = $Frame/Confirm

var _request = null
var _cards: Array = []
var _selected_card = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	confirm_button.pressed.connect(_confirm)
	ProfessionManager.draw_choice_requested.connect(_on_choice_requested)
	ProfessionManager.draw_choice_resolved.connect(_on_choice_resolved)
	set_process(false)
	hide()


func _process(_delta: float) -> void:
	if _request == null:
		return
	var remaining := ProfessionManager.get_draw_choice_time_left(_request.request_id)
	countdown_label.text = format_countdown(remaining)


func _on_choice_requested(request) -> void:
	if request == null:
		return
	_request = request
	_cards.assign(request.cards)
	_selected_card = _cards[0] if not _cards.is_empty() else null
	context_label.text = request.player.player_name
	countdown_label.text = format_countdown(request.timeout_seconds)
	_render_cards()
	set_process(true)
	show()
	confirm_button.grab_focus()

static func format_countdown(seconds: float) -> String:
	return "剩余 %02d 秒" % int(ceil(maxf(seconds, 0.0)))


func _render_cards() -> void:
	for child: Node in cards_row.get_children():
		cards_row.remove_child(child)
		child.queue_free()
	for index: int in _cards.size():
		var card = _cards[index]
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(390, 640)
		column.add_theme_constant_override("separation", 10)
		var shell := PanelContainer.new()
		shell.custom_minimum_size = Vector2(370, 520)
		shell.add_theme_stylebox_override("panel", _card_style(card == _selected_card))
		var image_button := TextureButton.new()
		image_button.texture_normal = card.image_of_front
		image_button.custom_minimum_size = Vector2(350, 500)
		image_button.ignore_texture_size = true
		image_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		image_button.tooltip_text = card.card_name
		image_button.pressed.connect(_select_card.bind(card))
		shell.add_child(image_button)
		column.add_child(shell)
		var name_label := Label.new()
		name_label.text = card.card_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", _font())
		name_label.add_theme_font_size_override("font_size", 31)
		name_label.add_theme_color_override("font_color", Color("542c1d"))
		column.add_child(name_label)
		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		controls.add_theme_constant_override("separation", 8)
		var left_button := _small_button("左移")
		left_button.disabled = index == 0
		left_button.pressed.connect(_move_card.bind(index, -1))
		controls.add_child(left_button)
		var select_button := _small_button("已选" if card == _selected_card else "选择")
		select_button.disabled = card == _selected_card
		select_button.pressed.connect(_select_card.bind(card))
		controls.add_child(select_button)
		var right_button := _small_button("右移")
		right_button.disabled = index == _cards.size() - 1
		right_button.pressed.connect(_move_card.bind(index, 1))
		controls.add_child(right_button)
		column.add_child(controls)
		cards_row.add_child(column)


func _select_card(card) -> void:
	if _request == null or not _cards.has(card):
		return
	_selected_card = card
	_render_cards()


func _move_card(index: int, offset: int) -> void:
	var target := index + offset
	if index < 0 or index >= _cards.size() or target < 0 or target >= _cards.size():
		return
	var card = _cards[index]
	_cards[index] = _cards[target]
	_cards[target] = card
	ProfessionManager.update_draw_choice_order(_request.request_id, _cards)
	_render_cards()


func _confirm() -> void:
	if _request == null or _selected_card == null:
		return
	var return_order: Array = []
	for card in _cards:
		if card != _selected_card:
			return_order.append(card)
	ProfessionManager.submit_draw_choice(_request.request_id, _selected_card, return_order)


func _on_choice_resolved(request_id: int, _result, _timed_out: bool) -> void:
	if _request == null or _request.request_id != request_id:
		return
	_reset_panel()


func reset_panel() -> void:
	_reset_panel()


func _reset_panel() -> void:
	_request = null
	_cards.clear()
	_selected_card = null
	set_process(false)
	for child: Node in cards_row.get_children():
		cards_row.remove_child(child)
		child.queue_free()
	hide()


func _small_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(104, 52)
	button.add_theme_font_override("font", _font())
	button.add_theme_font_size_override("font_size", 27)
	button.add_theme_color_override("font_color", Color("5a3325"))
	button.add_theme_color_override("font_hover_color", Color("5a3325"))
	button.add_theme_color_override("font_disabled_color", Color("8d816e"))
	button.add_theme_stylebox_override("normal", _button_style(Color("f2cf8c")))
	button.add_theme_stylebox_override("hover", _button_style(Color("f8dea8")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("c96a2b")))
	button.add_theme_stylebox_override("disabled", _button_style(Color("d5c8aa")))
	return button


func _card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8e4b9") if selected else Color("d8c5a1")
	style.border_color = Color("e49a2d") if selected else Color("a8764f")
	style.set_border_width_all(7 if selected else 3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(10.0)
	return style


func _button_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color("7b3e27")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _font() -> Font:
	return get_theme_default_font()
