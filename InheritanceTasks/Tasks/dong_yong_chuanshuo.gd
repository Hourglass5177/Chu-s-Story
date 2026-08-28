extends HeritageTaskBase

var _opening_times: Array[float] = []
var _next_opening: int = 0
var _hits: int = 0
var _last_press_feedback: float = -1.0


func on_task_started() -> void:
	_opening_times.clear()
	for index: int in 8:
		_opening_times.append(2.0 + float(index) * 2.55)
	_next_opening = 0
	_hits = 0


func task_tick(_delta: float) -> void:
	while _next_opening < _opening_times.size() \
			and elapsed_seconds > _opening_times[_next_opening] + 0.48:
		_next_opening += 1
	set_progress(float(_next_opening) / float(_opening_times.size()))
	if _next_opening >= _opening_times.size():
		_finish_weave()


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_accept") or joy_accept:
		_send_shuttle()
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_send_shuttle()
			return true
	return false


func on_time_expired() -> void:
	_finish_weave()


func _send_shuttle() -> void:
	if _next_opening >= _opening_times.size():
		return
	var error: float = absf(elapsed_seconds - _opening_times[_next_opening])
	_last_press_feedback = elapsed_seconds
	if error <= 0.42:
		_hits += 1
		pulse_feedback(&"shuttle_pass")
		_next_opening += 1
	else:
		pulse_feedback(&"shuttle_wait")


func _finish_weave() -> void:
	if _hits >= 6:
		complete_success({"successful_passes": _hits}, "纹样织成了")
	else:
		complete_failure(&"shuttle_timing", "等经线完全打开再送梭", {
			"successful_passes": _hits,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.89, 0.77, 0.57, 1.0), true)
	var opening_strength: float = 0.0
	if _next_opening < _opening_times.size():
		var distance: float = absf(elapsed_seconds - _opening_times[_next_opening])
		opening_strength = clampf(1.0 - distance / 0.75, 0.0, 1.0)
	for index: int in 14:
		var x: float = size.x * (0.15 + float(index) / 13.0 * 0.70)
		var spread: float = opening_strength * (36.0 if index % 2 == 0 else -36.0)
		draw_line(Vector2(x, size.y * 0.16), Vector2(x + spread, size.y * 0.83), Color(0.54, 0.27, 0.18, 0.85), 4.0, true)
	var shuttle_y: float = size.y * 0.52
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.20, shuttle_y),
		Vector2(size.x * 0.30, shuttle_y - 22.0),
		Vector2(size.x * 0.36, shuttle_y),
		Vector2(size.x * 0.30, shuttle_y + 22.0),
	]), Color(0.34, 0.17, 0.10, 1.0))
	for row: int in _hits:
		var y: float = size.y * 0.78 - row * 13.0
		draw_line(Vector2(size.x * 0.18, y), Vector2(size.x * 0.82, y), Color(0.78, 0.24 + row * 0.04, 0.20, 0.90), 10.0, true)
