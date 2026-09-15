class_name HeritageStageTask
extends HeritageTaskBase

var _stage_pixel_font: Font

signal input_device_changed(device: StringName)
signal control_hints_changed

const InputProfile := preload("res://InheritanceTasks/Common/heritage_input_profile.gd")

## Only the rebuilt tasks opt into this stage and lesson lifecycle.
const STAGE: Vector2 = Vector2(1000, 600)
const INK: Color = Color("263e43")
const PAPER: Color = Color("efe5cd")
const GOLD: Color = Color("daab52")
const RED: Color = Color("ad5445")
const TEAL: Color = Color("41867f")
enum Phase { DEMO, PRACTICE, COUNTDOWN, LIVE }
var phase: Phase = Phase.DEMO
var phase_time: float = 0.0
var game_time: float = 0.0
var accumulator: float = 0.0
var resume_countdown: float = 0.0
var lesson_edges: int = 0
var lesson_actions: Dictionary = {}
var lesson_text: String = "按下确认，跟着做一次"
var status_text: String = ""
var pressed: Dictionary = {-2: false, -1: false, 0: false, 1: false, 2: false}
var feedback_age: float = 0.0
var feedback_good: bool = true
var sfx: AudioStreamPlayer
var relearn: Button
var pointer_down_direction: int = 0
var reduced_motion: bool = false
var input_profile: HeritageInputProfile

func _ready() -> void:
	super._ready()
	set_process(false)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_process(delta)

func on_task_started() -> void:
	_ensure_input_profile()
	sfx = AudioStreamPlayer.new()
	add_child(sfx)
	sfx.stream = load("res://InheritanceTasks/Audio/action-feedback.wav")
	relearn = Button.new()
	relearn.text = "重学"
	relearn.position = Vector2(12, 8)
	relearn.pressed.connect(restart_lesson)
	add_child(relearn)
	var motion := CheckButton.new()
	motion.text = "减少动态"
	motion.position = Vector2(220, 8)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		motion.add_theme_color_override(state, INK)
	reduced_motion = bool(context.metadata.get("reduce_motion", false))
	motion.button_pressed = reduced_motion
	motion.toggled.connect(func(value: bool) -> void:
		reduced_motion = value
		grab_focus())
	add_child(motion)
	if bool(context.metadata.get("host_controls", false)):
		relearn.hide()
		motion.hide()
	setup_game()
	if run_state == RunState.FINISHED: return
	_setup_pixel_stage()
	var skip_lesson: bool = bool(context.metadata.get("skip_tutorial", false)) if context.test_mode else bool(context.metadata.get("skip_tutorial", HeritageMinigamePreferences.tutorial_done(task_id, maxi(4,tutorial_version()))))
	if bool(context.metadata.get("force_tutorial", false)): skip_lesson = false
	if skip_lesson:
		phase = Phase.COUNTDOWN
	else:
		phase = Phase.DEMO
	phase_time = 0.0

func restart_lesson() -> void:
	if not is_input_active() or phase == Phase.LIVE: return
	stop_media()
	phase = Phase.DEMO
	phase_time = 0.0
	lesson_edges = 0
	lesson_actions.clear()
	pressed = {-1: false, 0: false, 1: false}
	_clear_profile_input()
	game_time = 0.0
	set_progress(0.0)
	setup_game()
	grab_focus()

func is_task_clock_running() -> bool:
	return false

func get_time_display() -> String:
	if resume_countdown > 0.0: return "准备 %d" % ceili(resume_countdown)
	if phase != Phase.LIVE: return "练习" if phase == Phase.PRACTICE else "准备"
	return super.get_time_display()

func task_tick(delta: float) -> void:
	if resume_countdown > 0.0:
		resume_countdown -= delta
		if resume_countdown <= 0.0:
			pause_media(false)
			if is_instance_valid(sfx): sfx.stream_paused = false
		return
	feedback_age = maxf(0.0, feedback_age - delta)
	phase_time += delta
	if phase == Phase.DEMO:
		demo_tick(delta)
		if phase_time >= 2.5:
			setup_game()
			pressed = {-1: false, 0: false, 1: false}
			_clear_profile_input()
			set_progress(0.0)
			phase = Phase.PRACTICE
			phase_time = 0.0
			begin_practice()
			play_feedback(true)
		return
	if phase == Phase.PRACTICE:
		practice_tick(delta)
		return
	if phase == Phase.COUNTDOWN:
		if phase_time >= 3.0 and not _profile_has_held_input():
			phase = Phase.LIVE
			relearn.disabled = true
			game_time = 0.0
			accumulator = 0.0
			pressed = {-1: false, 0: false, 1: false}
			_clear_profile_input()
			begin_game()
		return
	accumulator += minf(delta, 0.25)
	while accumulator >= 1.0 / 120.0 and run_state == RunState.RUNNING and not is_settling_result():
		accumulator -= 1.0 / 120.0
		game_time += 1.0 / 120.0
		step_game(1.0 / 120.0)
	time_left = maxf(0.0, duration_seconds - game_time)
	if time_left <= 0.0 and run_state == RunState.RUNNING: on_time_expired()

func is_settling_result() -> bool:
	return false

func finish_lesson() -> void:
	if not context.test_mode: HeritageMinigamePreferences.complete_tutorial(task_id, maxi(4,tutorial_version()))
	phase = Phase.COUNTDOWN
	phase_time = 0.0
	pressed = {-1: false, 0: false, 1: false}
	setup_game()
	set_progress(0.0)

func on_suspension_changed(suspended: bool) -> void:
	pressed = {-1: false, 0: false, 1: false}
	_clear_profile_input()
	if is_instance_valid(sfx): sfx.stream_paused = true
	pause_media(true)
	if not suspended: resume_countdown = 1.5

func on_task_finished(result: HeritageTaskResult) -> void:
	_clear_profile_input()
	result.metrics["challenge_seconds"] = game_time
	stop_media()
	if is_instance_valid(relearn): relearn.disabled = true
	if is_instance_valid(sfx): sfx.stop()

func _exit_tree() -> void:
	stop_media()

func input_profile_kind() -> StringName:
	return InputProfile.for_task(task_id)

func _ensure_input_profile() -> void:
	if input_profile != null or input_profile_kind().is_empty(): return
	input_profile = InputProfile.new(input_profile_kind(),task_id)
	input_profile.semantic_edge.connect(receive_action)
	input_profile.bindings_changed.connect(func() -> void: control_hints_changed.emit())
	input_profile.value_changed.connect(func(_action: StringName,_value: float) -> void: control_hints_changed.emit())
	input_profile.device_changed.connect(func(device: StringName) -> void:
		input_device_changed.emit(device)
		control_hints_changed.emit())

func _clear_profile_input() -> void:
	if input_profile != null:
		input_profile.clear()
		control_hints_changed.emit()

func get_input_device() -> StringName:
	_ensure_input_profile()
	return input_profile.device if input_profile != null else &"keyboard"

func get_control_hints() -> Array[Dictionary]:
	_ensure_input_profile()
	return input_profile.control_hints() if input_profile != null else []

func get_input_profile() -> HeritageInputProfile:
	_ensure_input_profile()
	return input_profile

func receive_action(action: StringName, down: bool) -> void:
	if input_profile == null: return
	var direction := input_profile.direction_for_action(action)
	if direction != 99: receive_edge(direction,down)

func is_tutorial_active() -> bool:
	return phase in [Phase.DEMO,Phase.PRACTICE]

func restart_current_step() -> void:
	if not is_tutorial_active() or not is_input_active(): return
	restart_lesson()

func skip_tutorial() -> void:
	if not is_tutorial_active() or not is_input_active(): return
	stop_media()
	_clear_profile_input()
	pressed = {-2:false,-1:false,0:false,1:false,2:false}
	phase = Phase.COUNTDOWN
	phase_time = 0.0
	setup_game()
	set_progress(0.0)

func get_instruction_state() -> Dictionary:
	var phase_name: String = ["demo","practice","countdown","live"][phase]
	var instruction := lesson_text if phase != Phase.LIVE else status_text
	var count := 0
	if phase == Phase.COUNTDOWN:
		count = maxi(1,ceili(3.0-phase_time))
		instruction = "松开按键" if _profile_has_held_input() else "准备开始"
	if resume_countdown > 0.0:
		phase_name = "resume"
		count = ceili(resume_countdown)
		instruction = "准备继续"
	return {"phase":phase_name,"teaching":phase in [Phase.DEMO,Phase.PRACTICE],"text":instruction,"countdown":count,"step_id":str(lesson_actions.get("step",0))}

func _profile_has_held_input() -> bool:
	if input_profile == null: return false
	if context != null and context.test_mode: return input_profile.has_pressed_sources()
	return input_profile.physical_input_held()

func profile_pointer_direction(point: Vector2) -> int:
	return pointer_direction(point)

func _is_gameplay_ui_event(event: InputEvent) -> bool:
	if input_profile != null and input_profile.handles_event(event): return true
	return super._is_gameplay_ui_event(event)

func _input(event: InputEvent) -> void:
	# A captured mouse button may be released over another Control. Its release
	# still belongs to the game that accepted the press.
	if input_profile != null and event is InputEventMouseButton and not event.pressed:
		input_profile.release_pointer(event)

func logical_point(point: Vector2) -> Vector2:
	var scale_factor: float = minf(size.x / STAGE.x, size.y / STAGE.y)
	return (point - (size - STAGE * scale_factor) * 0.5) / maxf(scale_factor, 0.001)

func task_input(event: InputEvent) -> bool:
	if input_profile != null:
		if event is InputEventMouseButton: return input_profile.release_pointer(event)
		if not is_input_active() or resume_countdown > 0.0: return input_profile.handles_event(event)
		return input_profile.route_event(event)
	if event is InputEventKey and event.echo: return true
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		receive_edge(0, event.pressed)
		return true
	for action: StringName in [&"ui_left", &"ui_right", &"ui_accept", &"ui_up"]:
		if event.is_action(action):
			var direction: int = -1 if action == &"ui_left" else (1 if action == &"ui_right" else 0)
			receive_edge(direction, event.is_pressed())
			return true
	return false

func task_gui_input(event: InputEvent) -> bool:
	if input_profile != null and event is InputEventMouseMotion:
		if context == null or not bool(context.metadata.get("host_controls",false)):
			input_profile.note_pointer_motion(event.relative)
		return false
	if input_profile != null and event is InputEventMouseButton:
		if input_profile.release_pointer(event): return true
		if not is_input_active() or resume_countdown > 0.0: return false
		var point := logical_point(event.position)
		if not Rect2(Vector2.ZERO,STAGE).has_point(point): return false
		if input_profile.kind in [&"primary",&"heat",&"dance",&"bow",&"cart",&"directions",&"spotlight"]:
			return input_profile.route_event(event)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var direction := profile_pointer_direction(point)
			if input_profile.kind == &"platform" and direction == 2: return false
			if input_profile.kind == &"spotlight": direction = -1 if point.x < STAGE.x * 0.5 else 1
			input_profile.pointer_edge(direction,event.pressed)
			return true
		if input_profile.kind == &"platform" and event.button_index == MOUSE_BUTTON_RIGHT:
			input_profile.pointer_edge(0,event.pressed,MOUSE_BUTTON_RIGHT)
			return true
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := logical_point(event.position)
		if event.pressed and (point.x < 0 or point.x > STAGE.x or point.y < 0 or point.y > STAGE.y): return false
		pointer_edge(point, event.pressed)
		return true
	return false

func pointer_edge(point: Vector2, down: bool) -> void:
	if input_profile != null:
		input_profile.pointer_edge(profile_pointer_direction(point),down)
		return
	if down: pointer_down_direction = pointer_direction(point)
	receive_edge(pointer_down_direction, down)

func pointer_direction(_point: Vector2) -> int:
	return 0

func receive_edge(direction: int, down: bool) -> void:
	if not is_input_active() or resume_countdown > 0.0: return
	if bool(pressed.get(direction, false)) == down: return
	pressed[direction] = down
	control_hints_changed.emit()
	if phase == Phase.PRACTICE:
		if down:
			lesson_edges += 1
			lesson_actions[direction] = true
			play_feedback(true)
		practice_edge(direction, down)
	elif phase == Phase.LIVE:
		game_edge(direction, down)

func practice_edge(_direction: int, down: bool) -> void:
	if not down and lesson_edges >= 2: finish_lesson()

func practice_tick(_delta: float) -> void:
	pass

func begin_practice() -> void:
	pass

func demo_tick(_delta: float) -> void:
	pass

func play_feedback(good: bool) -> void:
	feedback_good = good
	feedback_age = 0.45
	if is_instance_valid(sfx):
		sfx.pitch_scale = 1.0 if good else 0.65
		sfx.volume_db = -12.0
		sfx.play()

func _draw() -> void:
	var factor: float = minf(size.x / STAGE.x, size.y / STAGE.y)
	draw_set_transform((size - STAGE * factor) * 0.5, 0.0, Vector2.ONE * factor)
	if is_instance_valid(pixel_stage):
		layout_pixel_stage()
		pixel_stage.update_state(get_visual_state())
		draw_pixel_overlay()
	else:
		draw_rect(Rect2(Vector2.ZERO, STAGE), PAPER)
		draw_scene()
	var host_instructions := input_profile != null and context != null and bool(context.metadata.get("host_instruction_overlay",false))
	if phase != Phase.LIVE and not host_instructions:
		var lesson_box := tutorial_overlay_bounds()
		draw_rect(lesson_box, Color(0.94, 0.9, 0.8, 0.97))
		label_at(lesson_box.position + Vector2(30, 33), "看一次示范" if phase == Phase.DEMO else ("你来试试" if phase == Phase.PRACTICE else "准备 %d" % maxi(1, ceili(3.0 - phase_time))), 24)
		label_at(lesson_box.position + Vector2(30, 71), lesson_text, 22)
	elif phase == Phase.LIVE and not status_text.is_empty() and not host_instructions:
		var feedback_box := feedback_overlay_bounds()
		var has_art := context != null and context.metadata.get(&"presentation") != null
		if has_art: draw_rect(feedback_box,Color(.12,.11,.1,.88))
		label_at(feedback_box.position + Vector2(20, 36), status_text, 24, PAPER if has_art else INK)
	if resume_countdown > 0.0 and not host_instructions:
		draw_rect(Rect2(350, 220, 300, 100), PAPER)
		label_at(Vector2(410, 280), "继续 %d" % ceili(resume_countdown), 32)
	draw_set_transform(Vector2.ZERO)
	var margin: Vector2 = (size - STAGE * factor) * 0.5
	if margin.x > 0:
		draw_rect(Rect2(0,0,margin.x,size.y),INK)
		draw_rect(Rect2(size.x-margin.x,0,margin.x,size.y),INK)
	if margin.y > 0:
		draw_rect(Rect2(0,0,size.x,margin.y),INK)
		draw_rect(Rect2(0,size.y-margin.y,size.x,margin.y),INK)

func feedback_overlay_bounds() -> Rect2:
	return Rect2(30, 46, 740, 50)

func tutorial_overlay_bounds() -> Rect2:
	return Rect2(110, 25, 780, 105)

func label_at(point: Vector2, text: String, font_size: int = 22, color: Color = INK) -> void:
	if is_instance_valid(pixel_stage) and _stage_pixel_font == null:
		_stage_pixel_font = HeritageTelevisionStyle.pixel_font()
	var label_font := _stage_pixel_font if is_instance_valid(pixel_stage) else get_theme_font("font")
	draw_string(label_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func person(point: Vector2, color: Color = TEAL, pose: float = 0.0, facing: float = 1.0) -> void:
	# Cloth silhouette, head, distinct arms and legs; pose drives anticipation/action.
	draw_circle(point + Vector2(0, -77 + absf(pose) * 3), 16, Color("cfaa7f"))
	draw_arc(point + Vector2(0, -80), 16, PI, TAU, 12, INK, 7)
	draw_colored_polygon(PackedVector2Array([point + Vector2(-19,-58),point + Vector2(19,-58),point + Vector2(26,-12),point + Vector2(-26,-12)]), color)
	var left_foot := point + Vector2(-18-minf(pose,0)*-14,12+minf(pose,0)*22)
	var right_foot := point + Vector2(18+maxf(pose,0)*14,12-maxf(pose,0)*22)
	draw_line(point + Vector2(-13,-15), left_foot, INK, 9)
	draw_line(point + Vector2(13,-15), right_foot, INK, 9)
	draw_line(left_foot+Vector2(-5,0),left_foot+Vector2(7,0),GOLD,5)
	draw_line(right_foot+Vector2(-5,0),right_foot+Vector2(7,0),GOLD,5)
	draw_line(point + Vector2(-18,-48), point + Vector2(-35*facing,-30-pose*25), color, 9)
	draw_line(point + Vector2(18,-48), point + Vector2(38*facing,-30+pose*25), color, 9)

func hills(offset: float = 0.0) -> void:
	if reduced_motion: offset = 0.0
	for i: int in 8:
		var x: float = i * 180.0 - fmod(offset, 180.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x-120,490),Vector2(x+20,150+(i%3)*60),Vector2(x+200,490)]), Color("b7c5ac") if i%2 else Color("cbd1b6"))
	draw_rect(Rect2(0,490,1000,110), Color("728e70"))

func setup_game() -> void: pass
func tutorial_version() -> int: return 4

func get_visual_state() -> Dictionary:
	var state: Dictionary = {"task_id": task_id, "animation_time": game_time if phase == Phase.LIVE else phase_time, "progress": progress, "action": &"ready", "reduced_motion": reduced_motion}
	if has_method("get_presentation_state"): state.merge(call("get_presentation_state"), true)
	if has_method("get_performance_visual_state"):
		state.merge(call("get_performance_visual_state"), true)
		state.action = StringName(state.get("motion_phase", "ready"))
	return state

func draw_pixel_overlay() -> void:
	pass
func begin_game() -> void: pass
func step_game(_delta: float) -> void: pass
func game_edge(_direction: int, _down: bool) -> void: pass
func draw_scene() -> void: pass
func pause_media(_value: bool) -> void: pass
func stop_media() -> void: pass
