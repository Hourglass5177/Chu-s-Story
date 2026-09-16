extends Control

signal confirmed
signal canceled

var _confirm: Button
var _cancel: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 4096
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MainUI.theme()
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ExitPanel"
	panel.custom_minimum_size = Vector2(1320, 660)
	panel.add_theme_stylebox_override("panel", MainUI.box("panel", 72))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 36)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "退出游戏？"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MainUI.label(heading, 60, true)
	content.add_child(heading)
	var message := Label.new()
	message.text = "本局进度不会保存。\n确定要离开本次旅程吗？"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MainUI.label(message, 40)
	content.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 48)
	content.add_child(actions)
	_confirm = Button.new()
	_confirm.text = "退出游戏"
	_cancel = Button.new()
	_cancel.text = "继续游戏"
	MainUI.button(_confirm, "danger")
	MainUI.button(_cancel)
	for button: Button in [_confirm, _cancel]:
		button.custom_minimum_size = Vector2(360, 110)
		MainUI.label(button, 40)
		button.add_theme_color_override("font_focus_color", MainUI.INK)
		actions.add_child(button)
	for button: Button in [_confirm, _cancel]:
		var other := _cancel if button == _confirm else _confirm
		button.focus_next = other.get_path()
		button.focus_previous = other.get_path()
		button.focus_neighbor_left = other.get_path()
		button.focus_neighbor_right = other.get_path()
		button.focus_neighbor_top = other.get_path()
		button.focus_neighbor_bottom = other.get_path()
	_confirm.pressed.connect(func(): confirmed.emit())
	_cancel.pressed.connect(func(): canceled.emit())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_confirm.add_theme_color_override(color_name, Color("fff4dc"))


func open() -> void:
	show()
	_cancel.grab_focus()


func get_cancel_button() -> Button:
	return _cancel


func get_ok_button() -> Button:
	return _confirm


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		canceled.emit()


func _unhandled_input(_event: InputEvent) -> void:
	if is_visible_in_tree(): get_viewport().set_input_as_handled()
