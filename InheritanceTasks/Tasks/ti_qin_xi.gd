extends HeritageTaskBase

const PHRASE_COUNT: int = 5
const PHRASE_DURATION: float = 4.5
const REQUIRED_INSIDE_SECONDS: float = 2.9

var _bow_x: float = 0.5
var _target_x: float = 0.5
var _phrase_index: int = 0
var _phrase_elapsed: float = 0.0
var _phrase_inside_seconds: float = 0.0
var _phrases_passed: int = 0
var _mouse_active: bool = false


func on_task_started() -> void:
	_bow_x = 0.5
	_target_x = 0.18
	_phrase_index = 0
	_phrase_elapsed = 0.0
	_phrase_inside_seconds = 0.0
	_phrases_passed = 0
	_mouse_active = false


func task_tick(delta: float) -> void:
	var phrase_ratio: float = clampf(_phrase_elapsed / PHRASE_DURATION, 0.0, 1.0)
	var phrase_from: float = 0.18 if _phrase_index % 2 == 0 else 0.82
	var phrase_to: float = 0.82 if _phrase_index % 2 == 0 else 0.18
	_target_x = lerpf(phrase_from, phrase_to, phrase_ratio)
	var input_x: float = Input.get_axis(&"ui_left", &"ui_right")
	if not is_zero_approx(input_x):
		_mouse_active = false
		_bow_x = clampf(_bow_x + input_x * delta * 0.72, 0.05, 0.95)
	elif not _mouse_active:
		_bow_x = clampf(_bow_x + input_x * delta * 0.72, 0.05, 0.95)
	if absf(_bow_x - _target_x) <= 0.11:
		_phrase_inside_seconds += delta
	_phrase_elapsed += delta
	if _phrase_elapsed >= PHRASE_DURATION:
		_resolve_phrase()
	set_progress((float(_phrase_index) + minf(_phrase_elapsed / PHRASE_DURATION, 1.0)) / float(PHRASE_COUNT))


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		_bow_x = clampf((event as InputEventMouseMotion).position.x / maxf(size.x, 1.0), 0.05, 0.95)
		_mouse_active = true
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_active = button.pressed
			_bow_x = clampf(button.position.x / maxf(size.x, 1.0), 0.05, 0.95)
			return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_mouse_active = false


func on_time_expired() -> void:
	_finish_phrases()


func _resolve_phrase() -> void:
	if _phrase_index >= PHRASE_COUNT:
		return
	if _phrase_inside_seconds >= REQUIRED_INSIDE_SECONDS:
		_phrases_passed += 1
		pulse_feedback(&"phrase_followed")
	_phrase_index += 1
	_phrase_elapsed = 0.0
	_phrase_inside_seconds = 0.0
	if _phrase_index >= PHRASE_COUNT:
		_finish_phrases()


func _finish_phrases() -> void:
	if _phrases_passed >= 4:
		complete_success({"phrases_passed": _phrases_passed}, "顺弓成句")
	else:
		complete_failure(&"bow_left_phrase", "有琴句没有跟住弓路", {
			"phrases_passed": _phrases_passed,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.10, 0.16, 1.0), true)
	var phrase_y: float = size.y * 0.50
	var target_center := Vector2(size.x * _target_x, phrase_y)
	draw_rect(Rect2(target_center - Vector2(size.x * 0.11, 65.0), Vector2(size.x * 0.22, 130.0)), Color(0.68, 0.36, 0.74, 0.38), true)
	var bow_x: float = size.x * _bow_x
	draw_line(Vector2(bow_x, phrase_y - 150.0), Vector2(bow_x, phrase_y + 150.0), Color(0.96, 0.78, 0.37, 1.0), 10.0, true)
	draw_circle(target_center, 18.0, Color(0.88, 0.48, 0.78, 1.0))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, size.y * 0.17), "第 %d / %d 句" % [mini(_phrase_index + 1, PHRASE_COUNT), PHRASE_COUNT], HORIZONTAL_ALIGNMENT_CENTER, size.x, 34)
