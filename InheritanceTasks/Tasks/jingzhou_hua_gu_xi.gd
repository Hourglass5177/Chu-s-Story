extends HeritageTaskBase

const WINDOWS: Array[Vector2] = [
	Vector2(2.0, 3.5),
	Vector2(6.0, 7.8),
	Vector2(10.2, 11.5),
	Vector2(14.2, 16.1),
	Vector2(19.0, 21.2),
]

var _holding: bool = false
var _press_started: float = -1.0
var _resolved: Array[int] = [-1, -1, -1, -1, -1]
var _phrases_passed: int = 0


func on_task_started() -> void:
	_holding = false
	_press_started = -1.0
	_resolved = [-1, -1, -1, -1, -1]
	_phrases_passed = 0


func task_tick(_delta: float) -> void:
	for index: int in WINDOWS.size():
		if _resolved[index] < 0 and elapsed_seconds > WINDOWS[index].y + 0.45:
			_resolve_window(index, elapsed_seconds if _holding else -1.0)
	var resolved_count: int = 0
	for state: int in _resolved:
		if state >= 0:
			resolved_count += 1
	set_progress(float(resolved_count) / float(WINDOWS.size()))
	if resolved_count == WINDOWS.size():
		_finish_chorus()


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	if event.is_action_pressed(&"ui_accept") or (joy_accept and (event as InputEventJoypadButton).pressed):
		_set_holding(true)
		return true
	if event.is_action_released(&"ui_accept") or (joy_accept and not (event as InputEventJoypadButton).pressed):
		_set_holding(false)
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_set_holding(button.pressed)
			return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_holding = false
		_press_started = -1.0


func on_time_expired() -> void:
	_finish_chorus()


func _set_holding(value: bool) -> void:
	if value == _holding:
		return
	_holding = value
	if value:
		_press_started = elapsed_seconds
		pulse_feedback(&"chorus_start")
	else:
		for index: int in WINDOWS.size():
			if _resolved[index] < 0 and elapsed_seconds >= WINDOWS[index].x - 0.30 \
					and elapsed_seconds <= WINDOWS[index].y + 0.45:
				_resolve_window(index, elapsed_seconds)
				break
		_press_started = -1.0


func _resolve_window(index: int, release_time: float) -> void:
	if _resolved[index] >= 0:
		return
	var window: Vector2 = WINDOWS[index]
	var start_ok: bool = _press_started >= window.x - 0.28 and _press_started <= window.x + 0.38
	var release_ok: bool = release_time >= window.y - 0.34 and release_time <= window.y + 0.45
	var passed: bool = start_ok and release_ok
	_resolved[index] = 1 if passed else 0
	if passed:
		_phrases_passed += 1
		pulse_feedback(&"chorus_complete")


func _finish_chorus() -> void:
	if _phrases_passed >= 4:
		complete_success({"phrases_passed": _phrases_passed}, "一唱众和")
	else:
		complete_failure(&"chorus_timing", "等唱句收住，再把帮腔接进来", {
			"phrases_passed": _phrases_passed,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.10, 0.12, 1.0), true)
	var timeline := Rect2(size.x * 0.08, size.y * 0.60, size.x * 0.84, 18.0)
	draw_rect(timeline, Color(0.87, 0.64, 0.30, 0.32), true)
	for index: int in WINDOWS.size():
		var window: Vector2 = WINDOWS[index]
		var x1: float = timeline.position.x + timeline.size.x * window.x / duration_seconds
		var x2: float = timeline.position.x + timeline.size.x * window.y / duration_seconds
		var color := Color(0.92, 0.63, 0.18, 0.85)
		if _resolved[index] == 1:
			color = Color(0.26, 0.71, 0.43, 0.9)
		elif _resolved[index] == 0:
			color = Color(0.68, 0.30, 0.25, 0.75)
		draw_rect(Rect2(x1, timeline.position.y - 22.0, x2 - x1, 62.0), color, true)
	var cursor_x: float = timeline.position.x + timeline.size.x * elapsed_seconds / duration_seconds
	draw_line(Vector2(cursor_x, timeline.position.y - 45.0), Vector2(cursor_x, timeline.position.y + 65.0), Color.WHITE, 5.0, true)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, size.y * 0.26), "按住接入 · 句尾松开", HORIZONTAL_ALIGNMENT_CENTER, size.x, 36)
