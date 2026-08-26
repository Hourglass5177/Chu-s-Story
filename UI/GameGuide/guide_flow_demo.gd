extends PanelContainer
class_name GuideFlowDemo

const STEP_INTERVAL := 0.75

var _steps: Array[Button] = []
var _active_index := 0
var _timer: Timer
var _reduce_motion := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "确认：显示完整流程"
	gui_input.connect(_on_gui_input)
	focus_entered.connect(_refresh_frame)
	focus_exited.connect(_refresh_frame)
	_timer = Timer.new()
	_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_timer.wait_time = STEP_INTERVAL
	_timer.timeout.connect(_advance)
	add_child(_timer)
	_refresh_steps()
	_refresh_frame()
	if not _reduce_motion and _steps.size() > 1:
		_timer.start()


func setup(flow_title: String, reduce_motion: bool = false) -> void:
	_reduce_motion = reduce_motion
	var raw_steps := flow_title.split("→", false)
	if raw_steps.size() <= 1:
		raw_steps = PackedStringArray(["基础分", "组合分", "成就分", "总分"])
	var row := HFlowContainer.new()
	row.name = "FlowSteps"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	add_child(row)
	for index: int in raw_steps.size():
		if index > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_size_override("font_size", 28)
			arrow.add_theme_color_override("font_color", FrontendStyle.BROWN_MUTED)
			row.add_child(arrow)
		var chip := Button.new()
		chip.text = String(raw_steps[index]).strip_edges()
		chip.alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.custom_minimum_size = Vector2(150, 62)
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_font_size_override("font_size", 24)
		row.add_child(chip)
		_steps.append(chip)
	if is_node_ready():
		_refresh_steps()


func show_final() -> void:
	_reduce_motion = true
	if _timer != null:
		_timer.stop()
	for chip: Button in _steps:
		chip.add_theme_color_override("font_color", FrontendStyle.BROWN_DARK)
		chip.add_theme_stylebox_override("normal", FrontendStyle.make_box(Color("#F5D89A"), FrontendStyle.GOLD, 2, 12, Vector4(12, 8, 12, 8)))


func _advance() -> void:
	if _steps.is_empty() or _reduce_motion:
		return
	_active_index = (_active_index + 1) % _steps.size()
	_refresh_steps()


func _refresh_steps() -> void:
	for index: int in _steps.size():
		var chip := _steps[index]
		var active := index == _active_index
		chip.add_theme_color_override("font_color", Color.WHITE if active else FrontendStyle.BROWN_DARK)
		chip.add_theme_stylebox_override(
			"normal",
			FrontendStyle.make_box(
				FrontendStyle.ORANGE if active else Color("#F8E7BE"),
				FrontendStyle.GOLD,
				3 if active else 2,
				12,
				Vector4(12, 8, 12, 8)
			)
		)


func _on_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	var clicked: bool = mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed
	if clicked or event.is_action_pressed("ui_accept"):
		show_final()
		accept_event()


func _refresh_frame() -> void:
	add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color(1.0, 0.96, 0.84, 0.08),
			Color(1.0, 0.96, 0.82, 0.96) if has_focus() else Color(FrontendStyle.BROWN_MUTED, 0.48),
			3 if has_focus() else 2,
			14,
			Vector4(16, 10, 16, 10)
		)
	)
