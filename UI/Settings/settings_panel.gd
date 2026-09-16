class_name GameSettingsPanel
extends Control

signal closed
const PAGE_NAMES := {"audio":"声音", "display":"画面", "accessibility":"辅助"}
var current_page := "audio"
var _paper: PanelContainer
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _controls: Dictionary = {}
var _percent: Dictionary = {}
var _status: Label
var _confirm_layer: ColorRect
var _confirm_title: Label
var _confirm_yes: Button
var _confirm_no: Button
var _confirm_kind := ""
var _return_focus: WeakRef
var _last_focus: WeakRef
var _dragging := false
var _refreshing := false
var _sfx_pending := false
var _allow_unsaved_close := false
var _sfx_timer: Timer
var _preview_audio: AudioStreamPlayer
var _content: VBoxContainer
var _joy_axis_state := {JOY_AXIS_LEFT_X: 0, JOY_AXIS_LEFT_Y: 0}
var _open_serial := 0
static var _font: FontFile

static func mount(owner: Node) -> GameSettingsPanel:
	var layer := CanvasLayer.new()
	layer.name = "GeneralSettingsLayer"
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(layer)
	var panel := GameSettingsPanel.new()
	panel.name = "GeneralSettings"
	layer.add_child(panel)
	return panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MainUI.theme()
	if _font == null:
		_font = MainUI.FONT.duplicate() as FontFile
		_font.oversampling = 4.0
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.08, 0.04, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	MainUI.fill(shade)
	_paper = PanelContainer.new()
	_paper.add_theme_stylebox_override("panel", MainUI.box("guide_panel", 0))
	add_child(_paper)
	var margin := MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	_paper.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	margin.add_child(_content)
	var header := HBoxContainer.new()
	_content.add_child(header)
	var balance := Control.new()
	balance.custom_minimum_size.x = 112
	header.add_child(balance)
	var title := _label("设置", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _button("关闭", true)
	close_button.name = "CloseSettings"
	close_button.icon = MainUI.texture("close")
	close_button.expand_icon = true
	close_button.add_theme_constant_override("icon_max_width", 24)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 32)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 170
	sidebar.add_theme_constant_override("separation", 14)
	body.add_child(sidebar)
	for key: String in PAGE_NAMES:
		var tab := _button(PAGE_NAMES[key], true)
		tab.name = key.capitalize() + "Tab"
		tab.custom_minimum_size.y = 58
		tab.pressed.connect(show_page.bind(key))
		sidebar.add_child(tab)
		_tabs[key] = tab
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var page_holder := VBoxContainer.new()
	page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page_holder)
	for key: String in PAGE_NAMES:
		var page := VBoxContainer.new()
		page.name = key.capitalize() + "Settings"
		page.add_theme_constant_override("separation", 16)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_holder.add_child(page)
		_pages[key] = page
	for pair: Array in [["master_volume","总音量"],["music_volume","背景音乐"],["sfx_volume","音效"],["minigame_volume","小游戏音量"]]:
		_add_volume(pair[0], pair[1])
	_note("audio", "小游戏原声、示范与反馈由小游戏音量控制。")
	_add_choices("display", "display_mode", "显示模式", ["窗口","无边框全屏"], [0,1])
	_add_choices("display", "fps_limit", "帧率上限", ["30","60","120","不限"], [30,60,120,0])
	_add_toggle("display", "vsync", "垂直同步")
	_note("display", "开启垂直同步时，帧率也受屏幕刷新率限制。")
	_add_toggle("accessibility", "reduce_motion", "减少装饰动态")
	_note("accessibility", "简化装饰转场，保留必要动作与操作提示。")
	_add_toggle("accessibility", "music_visual_assistance", "音游方向与预备提示")
	_add_choices("accessibility", "gamepad_glyph_style", "手柄按键图标", ["通用位置","字母","符号"], ["position","letters","symbols"])
	_note("accessibility", "关卡改键与节拍校准位于小游戏设置。")
	_status = _label("调整后自动保存", 20)
	_content.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	_content.add_child(footer)
	var reset := _button("恢复本页默认", true)
	reset.name = "ResetSettingsPage"
	reset.pressed.connect(_ask_reset)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var done := _button("完成")
	done.name = "SettingsDone"
	done.custom_minimum_size.x = 170
	done.pressed.connect(close_panel)
	footer.add_child(done)
	_build_confirmation()
	_sfx_timer = Timer.new()
	_sfx_timer.wait_time = 0.3
	_sfx_timer.one_shot = true
	_sfx_timer.timeout.connect(_finish_volume)
	add_child(_sfx_timer)
	_preview_audio = AudioStreamPlayer.new()
	_preview_audio.bus = &"BoardSFX"
	_preview_audio.volume_db = -9.0
	_preview_audio.stream = preload("res://Audio/SFX/confirm.wav")
	add_child(_preview_audio)
	Settings.changed.connect(_on_changed)
	Settings.save_finished.connect(_on_saved)
	Settings.display_preview_changed.connect(_on_display_preview)
	Settings.register_panel(self)
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_page("audio")
	hide()
	set_process(false)

func _label(text: String, font_size: int = 24) -> Label:
	var label := Label.new()
	label.text = text
	MainUI.label(label, font_size)
	label.add_theme_font_override("font", _font)
	return label

func _button(text: String, secondary := false) -> Button:
	var button := Button.new()
	button.text = text
	MainUI.button(button, "secondary" if secondary else "primary")
	MainUI.label(button, 24)
	button.add_theme_font_override("font", _font)
	for color_name: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, MainUI.INK)
	for state: String in ["normal","hover","pressed","disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state,style)
	button.custom_minimum_size = Vector2(112, 48)
	return button

func _row(page: String, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 48
	_pages[page].add_child(row)
	var label := _label(caption)
	label.custom_minimum_size.x = 150 if page == "audio" else 255
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row

func _add_volume(key: String, caption: String) -> void:
	var row := _row("audio", caption)
	var slider := HSlider.new()
	slider.name = key
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(180,48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.accessibility_name = caption
	for state: String in ["slider","grabber_area","grabber_area_highlight"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("d6c6a7") if state == "slider" else Color("b4823e")
		style.set_corner_radius_all(4)
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		slider.add_theme_stylebox_override(state, style)
	slider.add_theme_stylebox_override("focus", MainUI.theme().get_stylebox("focus","Button"))
	row.add_child(slider)
	var value := _label("100%")
	value.custom_minimum_size.x = 76
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_controls[key] = slider
	_percent[key] = value
	slider.value_changed.connect(func(v: float) -> void:
		if _refreshing: return
		Settings.set_value(key, int(v))
		if key == "sfx_volume": _sfx_pending = true
		if not _dragging: _sfx_timer.start())
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		_finish_volume())
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			slider.value += -5 if event.is_action_pressed("ui_left") else 5
			slider.accept_event())

func _finish_volume() -> void:
	if _sfx_pending:
		_sfx_pending = false
		_preview_audio.play()
	Settings.flush()

func _add_choices(page: String, key: String, caption: String, labels: Array, values: Array) -> void:
	var row := _row(page, caption)
	var choices := HBoxContainer.new()
	choices.name = key
	choices.add_theme_constant_override("separation", 8)
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for index in range(labels.size()):
		var option := _button(labels[index],true)
		option.name = "Choice" + str(index)
		option.custom_minimum_size.x = 60
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.toggle_mode = true
		option.button_group = group
		option.add_theme_stylebox_override("pressed",MainUI.box("primary_pressed",6))
		option.set_meta("value", values[index])
		option.accessibility_name = caption + "：" + labels[index]
		option.pressed.connect(func() -> void:
			if not _refreshing: Settings.set_value(key, values[index]))
		choices.add_child(option)
	row.add_child(choices)
	_controls[key] = choices

func _add_toggle(page: String, key: String, caption: String) -> void:
	var row := _row(page, caption)
	var button := _button("开启", true)
	button.name = key
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = caption
	button.toggled.connect(func(enabled: bool) -> void:
		if not _refreshing: Settings.set_value(key, enabled))
	row.add_child(button)
	_controls[key] = button

func _note(page: String, text: String) -> void:
	var note := _label(text,20)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages[page].add_child(note)

func _build_confirmation() -> void:
	_confirm_layer = ColorRect.new()
	_confirm_layer.color = Color(0.12,0.08,0.04,0.65)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)
	var center := CenterContainer.new()
	_confirm_layer.add_child(center)
	MainUI.fill(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",MainUI.box("guide_panel",24))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",24)
	panel.add_child(box)
	_confirm_title = _label("",24)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_confirm_title)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",24)
	box.add_child(buttons)
	_confirm_no = _button("取消",true)
	_confirm_yes = _button("恢复默认")
	buttons.add_child(_confirm_no)
	buttons.add_child(_confirm_yes)
	_confirm_no.pressed.connect(_cancel_confirmation)
	_confirm_yes.pressed.connect(func() -> void:
		if _confirm_kind == "display": Settings.confirm_display()
		else:
			_hide_confirmation()
			Settings.restore_page(current_page))
	_confirm_layer.hide()

func _layout() -> void:
	var area := get_viewport_rect().size
	var factor := minf(area.x / 1280.0, area.y / 720.0)
	_paper.scale = Vector2.ONE * factor
	_paper.size = Vector2(1040,600)
	_paper.position = (area - _paper.size * factor) * 0.5
	if is_instance_valid(_confirm_layer):
		_confirm_layer.scale = Vector2.ONE * factor
		_confirm_layer.size = area / factor

func open_panel(return_to: Control = null) -> void:
	if Settings.is_panel_open() and not visible: return
	_return_focus = weakref(return_to) if is_instance_valid(return_to) else null
	_allow_unsaved_close = false
	_open_serial += 1
	_joy_axis_state = {JOY_AXIS_LEFT_X: 0, JOY_AXIS_LEFT_Y: 0}
	_refresh()
	show()
	_layout()
	_tabs[current_page].grab_focus()

func close_panel(force := false) -> void:
	if not visible: return
	Settings.revert_display()
	_hide_confirmation()
	var saved := Settings.flush()
	if saved != OK and not _allow_unsaved_close and not force:
		_allow_unsaved_close = true
		_status.text = "未能保存，下次启动可能恢复原值。再次点击完成可关闭。"
		return
	hide()
	_open_serial += 1
	_preview_audio.stop()
	set_process(false)
	if _return_focus != null:
		var target: Variant = _return_focus.get_ref()
		if is_instance_valid(target) and target.is_visible_in_tree(): target.call_deferred("grab_focus")
	closed.emit()

func show_page(key: String) -> void:
	current_page = key
	for id: String in _pages:
		_pages[id].visible = id == key
		var tab: Button = _tabs[id]
		for state: String in ["normal","hover","pressed"]:
			tab.add_theme_stylebox_override(state, MainUI.box("chapter_selected" if id == key else "chapter", 8))
	_refresh()
	if visible: _tabs[key].grab_focus()

func _refresh() -> void:
	_refreshing = true
	for key: String in _controls:
		var control: Control = _controls[key]
		var value: Variant = Settings.get_value(key)
		if control is HSlider:
			control.set_value_no_signal(float(value))
			_percent[key].text = "%d%%" % int(value)
		elif control is HBoxContainer:
			for option: Button in control.get_children():
				var selected: bool = option.get_meta("value") == value
				option.set_pressed_no_signal(selected)
				option.add_theme_color_override("font_color", Color("8b4e16") if selected else MainUI.INK)
		elif control is Button:
			control.set_pressed_no_signal(bool(value))
			control.text = "开启  ✓" if bool(value) else "关闭"
	_refreshing = false

func _on_changed(_key: String, _value: Variant) -> void:
	if visible: _refresh()

func _on_saved(error: Error) -> void:
	_status.text = "已自动保存" if error == OK else "未能保存，下次启动可能恢复原值"

func _ask_reset() -> void:
	_show_confirmation("reset")
	_confirm_title.text = "恢复“%s”的默认设置？\n其他设置与游戏进度不受影响。" % PAGE_NAMES[current_page]
	_confirm_yes.text = "恢复默认"
	_confirm_no.text = "取消"

func _show_confirmation(kind: String) -> void:
	_last_focus = weakref(get_viewport().gui_get_focus_owner())
	_confirm_kind = kind
	_confirm_layer.show()
	_content.process_mode = Node.PROCESS_MODE_DISABLED
	_set_focus_enabled(_content, false)
	_confirm_no.grab_focus()
	set_process(kind == "display")

func _set_focus_enabled(root: Node, enabled: bool) -> void:
	if root is BaseButton or root is Slider: root.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	for child: Node in root.get_children(): _set_focus_enabled(child, enabled)

func _hide_confirmation() -> void:
	_confirm_layer.hide()
	_confirm_kind = ""
	_content.process_mode = Node.PROCESS_MODE_INHERIT
	_set_focus_enabled(_content,true)
	set_process(false)
	if _last_focus != null:
		var target: Variant = _last_focus.get_ref()
		if is_instance_valid(target) and target.is_visible_in_tree(): target.call_deferred("grab_focus")

func _cancel_confirmation() -> void:
	if _confirm_kind == "display": Settings.revert_display()
	else: _hide_confirmation()

func _on_display_preview(active: bool) -> void:
	if not visible: return
	if active:
		_show_confirmation("display")
		_confirm_yes.text = "保留更改"
		_confirm_no.text = "还原"
		_process(0)
	else:
		_hide_confirmation()
		_refresh()

func _process(_delta: float) -> void:
	_confirm_title.text = "保留新的显示模式？\n%d 秒后自动还原" % ceili(Settings.preview_remaining)

func _input(event: InputEvent) -> void:
	if not visible or event.is_echo(): return
	if _forward_gamepad(event): return
	if _popup_visible(): return
	if event.is_action_pressed("ui_cancel"):
		if _confirm_layer.visible: _cancel_confirmation()
		else: close_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		# Keep keyboard/controller focus inside the uppermost sheet, including at its ends.
		var controls: Array[Control] = []
		_collect_focus(_confirm_layer if _confirm_layer.visible else _paper,controls)
		if not controls.is_empty():
			var index := controls.find(get_viewport().gui_get_focus_owner())
			var backward := event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_up")
			controls[posmod(index + (-1 if backward else 1),controls.size())].grab_focus()
		get_viewport().set_input_as_handled()

func _collect_focus(node: Node, result: Array[Control]) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Control and node.focus_mode == Control.FOCUS_ALL:
		if not node is BaseButton or not node.disabled: result.append(node)
	for child: Node in node.get_children(): _collect_focus(child,result)

func _unhandled_input(_event: InputEvent) -> void:
	if visible and not _popup_visible(): get_viewport().set_input_as_handled()

func _popup_visible() -> bool:
	for control: Control in _controls.values():
		if control is OptionButton and control.get_popup().visible: return true
	return false

func _forward_gamepad(event: InputEvent) -> bool:
	var actions := {JOY_BUTTON_A: &"ui_accept", JOY_BUTTON_B: &"ui_cancel", JOY_BUTTON_START: &"ui_cancel", JOY_BUTTON_DPAD_LEFT: &"ui_left", JOY_BUTTON_DPAD_RIGHT: &"ui_right", JOY_BUTTON_DPAD_UP: &"ui_up", JOY_BUTTON_DPAD_DOWN: &"ui_down"}
	if event is InputEventJoypadButton and actions.has(event.button_index):
		_queue_action(actions[event.button_index],event.pressed)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventJoypadMotion and _joy_axis_state.has(event.axis):
		var previous: int = _joy_axis_state[event.axis]
		var direction := previous
		if absf(event.axis_value) < 0.4: direction = 0
		elif absf(event.axis_value) >= 0.6: direction = 1 if event.axis_value > 0 else -1
		if direction != previous:
			var negative := &"ui_left" if event.axis == JOY_AXIS_LEFT_X else &"ui_up"
			var positive := &"ui_right" if event.axis == JOY_AXIS_LEFT_X else &"ui_down"
			if previous != 0: _queue_action(negative if previous < 0 else positive,false)
			_joy_axis_state[event.axis] = direction
			if direction != 0: _queue_action(negative if direction < 0 else positive,true)
		get_viewport().set_input_as_handled()
		return true
	return false

func _queue_action(action: StringName, pressed: bool) -> void:
	var mapped := InputEventAction.new()
	mapped.action = action
	mapped.pressed = pressed
	_deliver_action.call_deferred(mapped,_open_serial)

func _deliver_action(event: InputEventAction, serial: int) -> void:
	if visible and serial == _open_serial: get_viewport().push_input(event,true)

func _exit_tree() -> void:
	if visible:
		Settings.revert_display()
		Settings.flush()
