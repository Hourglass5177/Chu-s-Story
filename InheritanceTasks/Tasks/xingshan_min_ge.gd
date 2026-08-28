extends HeritageTaskBase

var _round_index: int = 0
var _targets: Array[float] = []
var _pitch: float = 0.5
var _hits: int = 0
var _mouse_dragging: bool = false


func on_task_started() -> void:
	_round_index = 0
	_hits = 0
	_pitch = 0.5
	_targets.clear()
	for index: int in 3:
		_targets.append(get_rng().randf_range(0.25, 0.75))


func task_tick(delta: float) -> void:
	if not _mouse_dragging:
		var input_y: float = Input.get_axis(&"ui_down", &"ui_up")
		_pitch = clampf(_pitch + input_y * delta * 0.55, 0.08, 0.92)
	queue_redraw()


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_accept") or joy_accept:
		_confirm_pitch()
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and _mouse_dragging:
		_set_pitch_from_mouse((event as InputEventMouseMotion).position)
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		_mouse_dragging = button.pressed
		_set_pitch_from_mouse(button.position)
		if not button.pressed:
			_confirm_pitch()
		return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_mouse_dragging = false


func on_time_expired() -> void:
	_finish_notes()


func _set_pitch_from_mouse(position: Vector2) -> void:
	_pitch = clampf(1.0 - position.y / maxf(size.y, 1.0), 0.08, 0.92)


func _confirm_pitch() -> void:
	if _round_index >= _targets.size():
		return
	var error: float = absf(_pitch - _targets[_round_index])
	if error <= 0.075:
		_hits += 1
		pulse_feedback(&"tone_found")
	else:
		pulse_feedback(&"tone_nearby")
	_round_index += 1
	set_progress(float(_round_index) / float(_targets.size()))
	_pitch = 0.5
	if _round_index >= _targets.size():
		_finish_notes()


func _finish_notes() -> void:
	if _hits >= 2:
		complete_success({"tones_found": _hits}, "山谷回声重合了")
	else:
		complete_failure(&"tones_not_aligned", "让两道波纹再靠近一些", {
			"tones_found": _hits,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.18, 0.20, 1.0), true)
	var target: float = _targets[_round_index] if _round_index < _targets.size() else 0.5
	var target_y: float = size.y * (1.0 - target)
	var pitch_y: float = size.y * (1.0 - _pitch)
	for index: int in 6:
		var radius: float = 60.0 + index * 42.0
		draw_arc(Vector2(size.x * 0.37, target_y), radius, -0.72, 0.72, 24, Color(0.35, 0.72, 0.78, 0.42), 5.0, true)
		draw_arc(Vector2(size.x * 0.63, pitch_y), radius, PI - 0.72, PI + 0.72, 24, Color(0.94, 0.70, 0.26, 0.55), 5.0, true)
	draw_circle(Vector2(size.x * 0.63, pitch_y), 24.0 + feedback_strength * 5.0, Color(0.96, 0.77, 0.32, 1.0))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, size.y * 0.15), "第 %d / 3 音" % mini(_round_index + 1, 3), HORIZONTAL_ALIGNMENT_CENTER, size.x, 34)
