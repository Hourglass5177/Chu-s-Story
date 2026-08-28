extends HeritageTaskBase

const PROMPT_COUNT: int = 12

var _prompts: Array[Dictionary] = []
var _next_prompt: int = 0
var _hits: int = 0


func on_task_started() -> void:
	_prompts.clear()
	for index: int in PROMPT_COUNT:
		_prompts.append({
			"time": 1.5 + float(index) * 1.82,
			"direction": get_rng().randi_range(0, 2),
		})
	_next_prompt = 0
	_hits = 0


func task_tick(_delta: float) -> void:
	while _next_prompt < _prompts.size() \
			and elapsed_seconds > float(_prompts[_next_prompt]["time"]) + 0.48:
		_next_prompt += 1
	set_progress(float(_next_prompt) / float(PROMPT_COUNT))
	if _next_prompt >= PROMPT_COUNT:
		_finish_dance()


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_left"):
		_answer(0)
		return true
	if event.is_action_pressed(&"ui_accept") or joy_accept or event.is_action_pressed(&"ui_up"):
		_answer(1)
		return true
	if event.is_action_pressed(&"ui_right"):
		_answer(2)
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		var third: float = size.x / 3.0
		_answer(clampi(int(button.position.x / maxf(third, 1.0)), 0, 2))
		return true
	return false


func on_time_expired() -> void:
	_finish_dance()


func _answer(direction: int) -> void:
	if _next_prompt >= _prompts.size():
		return
	var prompt: Dictionary = _prompts[_next_prompt]
	var timing_error: float = absf(elapsed_seconds - float(prompt["time"]))
	if timing_error <= 0.46 and direction == int(prompt["direction"]):
		_hits += 1
		pulse_feedback(&"step_hit")
		_next_prompt += 1
	elif timing_error <= 0.46:
		pulse_feedback(&"step_miss")
		_next_prompt += 1


func _finish_dance() -> void:
	if _hits >= 9:
		complete_success({"steps_hit": _hits}, "鼓声与舞步合上了")
	else:
		complete_failure(&"dance_steps_missed", "看准领舞，再踩进应和拍", {
			"steps_hit": _hits,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.17, 0.12, 0.09, 1.0), true)
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	draw_arc(center, 180.0, 0.0, TAU, 64, Color(0.82, 0.50, 0.18, 0.65), 18.0, true)
	for index: int in 6:
		var angle: float = -PI * 0.5 + TAU * float(index) / 6.0
		draw_circle(center + Vector2.from_angle(angle) * 180.0, 15.0, Color(0.93, 0.72, 0.30, 0.90))
	var direction: int = int(_prompts[_next_prompt]["direction"]) if _next_prompt < _prompts.size() else 1
	var symbols: Array[String] = ["←", "↑", "→"]
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, center.y + 28.0), symbols[direction], HORIZONTAL_ALIGNMENT_CENTER, size.x, 82)
	draw_string(font, Vector2(0, size.y * 0.84), "%d / %d" % [_hits, PROMPT_COUNT], HORIZONTAL_ALIGNMENT_CENTER, size.x, 30)
