extends HeritageTaskBase

const TARGETS: Array[Vector2] = [
	Vector2(0.47, 0.58),
	Vector2(0.62, 0.73),
	Vector2(0.52, 0.64),
]
const INFLATION_RATE: float = 0.085

var _segment: int = 0
var _inflation: float = 0.0
var _pressure: float = 0.0
var _holding: bool = false
var _controller_holding: bool = false
var _segments_passed: int = 0
var _severe_overblow: bool = false


func on_task_started() -> void:
	_segment = 0
	_inflation = 0.0
	_pressure = 0.0
	_holding = false
	_controller_holding = false
	_segments_passed = 0
	_severe_overblow = false


func task_tick(delta: float) -> void:
	var blowing: bool = _holding or _controller_holding or Input.is_action_pressed(&"ui_accept")
	_pressure = move_toward(_pressure, 1.0 if blowing else 0.0, delta * (2.2 if blowing else 3.0))
	_inflation += _pressure * delta * INFLATION_RATE
	if not blowing:
		_inflation = maxf(0.0, _inflation - delta * 0.035)
	if _inflation >= 1.06:
		_severe_overblow = true
		_commit_segment()
	set_progress((float(_segment) + minf(_inflation, 1.0)) / 3.0)


func task_input(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
		_controller_holding = (event as InputEventJoypadButton).pressed
		if not _controller_holding:
			_commit_segment()
		return true
	if event.is_action_released(&"ui_accept"):
		_commit_segment()
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	_holding = button.pressed
	if not button.pressed:
		_commit_segment()
	return true


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_holding = false
		_controller_holding = false


func on_time_expired() -> void:
	_finish_shape()


func _commit_segment() -> void:
	if _segment >= TARGETS.size():
		return
	var target: Vector2 = TARGETS[_segment]
	if _inflation >= target.x and _inflation <= target.y:
		_segments_passed += 1
		pulse_feedback(&"segment_formed")
	_segment += 1
	_inflation = 0.0
	_pressure = 0.0
	_holding = false
	if _segment >= TARGETS.size():
		_finish_shape()


func _finish_shape() -> void:
	if _segments_passed >= 2 and not _severe_overblow:
		complete_success({"segments_passed": _segments_passed}, "糖塑成形")
	else:
		var message: String = "这一口气送得太满" if _severe_overblow else "轮廓还差一点"
		complete_failure(&"shape_incomplete", message, {
			"segments_passed": _segments_passed,
			"severe_overblow": _severe_overblow,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.32, 0.18, 0.10, 1.0), true)
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	var target: Vector2 = TARGETS[mini(_segment, TARGETS.size() - 1)]
	var target_radius: float = 170.0 * (target.x + target.y) * 0.5
	draw_circle(center, target_radius, Color(0.96, 0.76, 0.24, 0.18))
	draw_arc(center, target_radius, 0.0, TAU, 64, Color(0.96, 0.73, 0.20, 0.9), 7.0, true)
	draw_circle(center, 170.0 * minf(_inflation, 1.1), Color(0.91, 0.46, 0.12, 0.78))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, size.y * 0.18), "第 %d / 3 口" % mini(_segment + 1, 3), HORIZONTAL_ALIGNMENT_CENTER, size.x, 34)
