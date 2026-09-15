extends HeritageStageTask

const Pattern := preload("res://InheritanceTasks/Data/paper_cut_pattern.gd")
const KNIFE_SPEED: float = 230.0
const MOUSE_TOLERANCE: float = 18.0
const CONTROL_TOLERANCE: float = 24.0
var contours: Array[PackedVector2Array] = []
var segment: int = 0
var cut_distance: float = 0.0
var cut_length: float = 0.0
var pointer := Vector2.ZERO
var last_pointer := Vector2.ZERO
var dragging: bool = false
var off_path_seconds: float = 0.0
var path_valid: bool = true
var awaiting_release: bool = false
var detached_time: float = 0.0
var lesson_cut_complete: bool = false
var ending_time: float = 0.0

func input_profile_kind() -> StringName: return &"trace"
func play_feedback(good: bool) -> void:
	if is_instance_valid(sfx): sfx.stream = load("res://InheritanceTasks/Audio/action-story-v3/paper-%s.wav"%("good" if good else "miss"))
	super.play_feedback(good)
	if is_instance_valid(sfx):
		sfx.pitch_scale = 1.0
		sfx.volume_db = -16.0

func tutorial_version() -> int: return 5
func tutorial_overlay_bounds() -> Rect2: return Rect2(105,20,790,90)
func feedback_overlay_bounds() -> Rect2: return Rect2(105,20,790,70)

func setup_game() -> void:
	duration_seconds = 30.0
	contours = Pattern.contours()
	if contours.size()!=4:
		complete_technical_error(&"invalid_paper_geometry","纸样数据未就绪")
		return
	segment = 0
	cut_distance = 0.0
	cut_length = Pattern.length(contours[0])
	pointer = contours[0][0]
	last_pointer = pointer
	dragging = false
	off_path_seconds = 0.0
	awaiting_release = false
	path_valid = true
	detached_time = 0.0
	ending_time = 0.0
	lesson_cut_complete = false
	lesson_text = "从金点落刀，沿鸟翼刻一圈"
	status_text = "从金点落刀 · " + Pattern.NAMES[segment]

func begin_game() -> void:
	setup_game()

func practice_tick(delta: float) -> void:
	_advance_knife(delta)
	if lesson_cut_complete and not dragging and not bool(pressed.get(0,false)):
		finish_lesson()
func step_game(delta: float) -> void: _advance_knife(delta)

func is_settling_result() -> bool:
	return ending_time > 0.0

func task_tick(delta: float) -> void:
	if ending_time > 0.0 and resume_countdown <= 0.0:
		detached_time = maxf(0.0,detached_time-delta)
		ending_time = maxf(0.0,ending_time-delta)
		status_text = "纸屑落下" if detached_time>0.0 else "揭纸，双鸟花枝完成"
		if ending_time <= 0.0:
			var metrics := {"off_path_seconds":off_path_seconds,"segments":contours.size(),"pattern_version":4}
			if off_path_seconds <= 2.8: complete_success(metrics,"双鸟花枝刻好了")
			else: complete_failure(&"paper_bridge_cut","几处纸桥切偏了，下次慢一点",metrics)
		return
	super.task_tick(delta)

func demo_tick(delta: float) -> void:
	var distance := minf(cut_length,phase_time/2.1*cut_length)
	var shown := Pattern.prefix(contours[0],distance)
	dragging = true
	_trace_to(shown[-1])
	if delta > 0.0: detached_time = maxf(0.0,detached_time-delta)

func _advance_knife(delta: float) -> void:
	detached_time = maxf(0.0,detached_time-delta)
	if segment >= contours.size(): return
	var direction := Vector2(float(bool(pressed.get(1,false)))-float(bool(pressed.get(-1,false))),float(bool(pressed.get(2,false)))-float(bool(pressed.get(-2,false))))
	if direction.length_squared() > 0.0:
		var next := (pointer+direction.normalized()*KNIFE_SPEED*delta).clamp(Vector2.ZERO,STAGE)
		if bool(pressed.get(0,false)) and not awaiting_release: _trace_to(next)
		else:
			pointer = next
			last_pointer = pointer
	if (dragging or bool(pressed.get(0,false))) and not awaiting_release and not path_valid:
		off_path_seconds += delta
		status_text = "偏了，回到已刻线的末端"

func practice_edge(direction: int, down: bool) -> void: game_edge(direction,down)

func game_edge(direction: int, down: bool) -> void:
	if direction != 0: return
	if not down:
		awaiting_release = false
		dragging = false
	last_pointer = pointer

func _input(event: InputEvent) -> void:
	# Global release precedes Control._gui_input, including releases outside
	# the canvas. Capture its final spatial sample before the profile clears it.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging and not awaiting_release and is_input_active() and resume_countdown <= 0.0:
			var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			_trace_to(logical_point(local_point))
	super._input(event)

func task_gui_input(event: InputEvent) -> bool:
	if not is_input_active() or resume_countdown > 0.0: return false
	if event is InputEventMouseMotion:
		if input_profile != null: input_profile.note_pointer_motion(event.relative)
		if dragging and not awaiting_release: _trace_to(logical_point(event.position))
		return dragging
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := logical_point(event.position)
		if event.pressed:
			if not Rect2(Vector2.ZERO,STAGE).has_point(point): return false
			pointer = point
			last_pointer = point
			dragging = true
			if input_profile != null: input_profile.pointer_edge(0,true)
			_trace_to(point)
		else:
			# Final position is sampled BEFORE releasing input ownership.
			if dragging and not awaiting_release: _trace_to(point)
			dragging = false
			awaiting_release = false
			if input_profile != null: input_profile.pointer_edge(0,false)
		return true
	return false

func _trace_to(point: Vector2) -> void:
	if segment >= contours.size() or awaiting_release: return
	var from := last_pointer
	var samples := maxi(1,ceili(from.distance_to(point)/5.0))
	for sample: int in samples:
		var at := from.lerp(point,float(sample+1)/samples)
		_sample_cut(at)
		if awaiting_release or segment >= contours.size(): break
	pointer = point
	last_pointer = point

func _sample_cut(at: Vector2) -> void:
	var path := contours[segment]
	var traveled := 0.0
	var best_distance := INF
	var best_progress := cut_distance
	# Restrict arc search: the coincident start/end never skips a closed loop.
	for i: int in path.size()-1:
		var a := path[i]
		var b := path[i+1]
		var length := a.distance_to(b)
		if traveled+length >= cut_distance-22.0 and traveled <= cut_distance+22.0:
			var t := clampf((at-a).dot(b-a)/maxf(.001,length*length),0.0,1.0)
			var along := traveled+length*t
			var distance := at.distance_to(a.lerp(b,t))
			if distance < best_distance and along <= cut_distance+22.0:
				best_distance = distance
				best_progress = along
		traveled += length
	path_valid = best_distance <= (MOUSE_TOLERANCE if dragging else CONTROL_TOLERANCE)
	if path_valid:
		cut_distance = maxf(cut_distance,best_progress)
		set_progress((segment+cut_distance/cut_length)/float(contours.size()))
		status_text = "%d/%d · %s" % [segment+1,contours.size(),Pattern.NAMES[segment]]
		# The last native pixel must be reachable with discrete key/DPAD steps.
		# Progress still comes from the legal arc; release never grants completion.
		if cut_distance >= cut_length-2.5 and at.distance_to(path[-1]) <= 8.0: _finish_contour()

func _finish_contour() -> void:
	play_feedback(true)
	if phase == Phase.PRACTICE:
		lesson_cut_complete = true
		awaiting_release = true
		lesson_text = "松开，停刀"
		return
	if phase != Phase.LIVE: return
	segment += 1
	detached_time = .6
	awaiting_release = true
	if segment >= contours.size():
		ending_time = 1.05
		dragging = false
		_clear_profile_input()
		pressed.clear()
		return
	cut_distance = 0.0
	cut_length = Pattern.length(contours[segment])
	status_text = "松开，再从下一处金点落刀"

func on_suspension_changed(suspended: bool) -> void:
	dragging = false
	awaiting_release = false
	last_pointer = pointer
	super.on_suspension_changed(suspended)

func on_time_expired() -> void:
	if ending_time>0.0: return
	complete_failure(&"trace_incomplete","还差几刀，再试一次",{"segments":segment,"progress":progress})

func get_presentation_state() -> Dictionary:
	return {"contours":contours,"segment":segment,"cut_distance":cut_distance,"cut_length":cut_length,"pointer":pointer,"cutting":dragging or bool(pressed.get(0,false)),"path_valid":path_valid,"finished":segment==contours.size(),"detached_time":detached_time,"action":&"action" if dragging else &"ready"}

func draw_scene() -> void:
	if contours.size()!=4: return
	draw_rect(Rect2(Vector2.ZERO,STAGE),Color("bf9d69"))
	draw_rect(Pattern.PAPER_RECT.grow(15),Color("423426"))
	draw_rect(Pattern.PAPER_RECT,Color("b63836"))
	for i: int in contours.size():
		if i < segment: draw_colored_polygon(contours[i],Color("423426"))
		else: draw_polyline(contours[i],Color("e58b69"),3)
	if segment < contours.size():
		var path := contours[segment]
		draw_polyline(Pattern.prefix(path,cut_distance),Color("352a24"),5)
		draw_circle(path[0],8,GOLD)
	draw_circle(pointer,5,Color("eee5c8"))
