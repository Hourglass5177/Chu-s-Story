extends HeritageStageTask

const PLAYER_SIZE := Vector2(30, 44)
const GRAVITY: float = 1150.0
const JUMP_SPEED: float = 470.0
const MOVE_SPEED: float = 245.0
const MAX_JUMP_HEIGHT: float = JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY)
var _platforms: Array[Rect2] = []
var _hazards: Array[Rect2] = []
var _low_branches: Array[Rect2] = []
var _goal := Rect2(8150, 85, 120, 120)
var _player_position := Vector2(60, 456)
var _velocity := Vector2.ZERO
var _checkpoint := Vector2(60, 456)
var grounded: bool = true
var coyote: float = 0.12
var jump_buffer: float = 0.0
var camera_x: float = 0.0
var recover: float = 0.0
var mouse_direction: int = 0
var mouse_walk_direction: int = 0
var mistakes: int = 0
var pose: StringName = &"idle"
var section: StringName = &"forest"
var landing_feedback: float = 0.0
var obstacle_warning: float = 0.0
var _jump_cut: bool = false
var _airborne_jump: bool = false
var _practiced_short: bool = false
var _practiced_long: bool = false
const LEFT_MOUSE_BUTTON := Rect2(40, 505, 132, 72)
const RIGHT_MOUSE_BUTTON := Rect2(184, 505, 132, 72)
var _mouse_controls: Array[Button] = []

func input_profile_kind() -> StringName:
	return &"platform"

func tutorial_version() -> int:
	return 4

func setup_game() -> void:
	duration_seconds = 45.0
	lesson_text = "轻点跳，松开后落地"
	# Three readable sections: low branches in the forest, broad creek gaps,
	# then 60–65 px climbs. Every rise stays below 75% of the actual jump apex.
	_platforms = [Rect2(0,500,720,180), Rect2(790,455,310,225),
		Rect2(1180,395,360,285), Rect2(1650,450,450,230),
		Rect2(2180,395,410,285), Rect2(2680,395,520,285),
		Rect2(3325,450,260,230), Rect2(3685,390,330,290),
		Rect2(4105,330,430,350), Rect2(4650,395,420,285),
		Rect2(5160,395,340,285), Rect2(5570,330,330,350),
		Rect2(5990,265,370,415), Rect2(6465,330,420,350),
		Rect2(6975,265,330,415), Rect2(7395,205,930,475)]
	_hazards = [Rect2(480,484,28,16), Rect2(1390,373,28,22),
		Rect2(1900,434,28,16), Rect2(2920,373,30,22),
		Rect2(3860,368,28,22), Rect2(4350,308,30,22),
		Rect2(4880,375,28,20), Rect2(5740,310,28,20),
		Rect2(6660,310,30,20), Rect2(7130,249,28,16), Rect2(7670,185,28,20)]
	_low_branches = [Rect2(400,380,210,22), Rect2(1810,330,220,22), Rect2(7050,145,200,22)]
	_player_position = Vector2(60,456)
	_velocity = Vector2.ZERO
	_checkpoint = _player_position
	grounded = true
	coyote = 0.12
	jump_buffer = 0.0
	camera_x = 0.0
	recover = 0.0
	mistakes = 0
	mouse_walk_direction = 0
	pose = &"idle"
	section = &"forest"
	landing_feedback = 0.0
	obstacle_warning = 0.0
	_jump_cut = false
	_airborne_jump = false
	_practiced_short = false
	_practiced_long = false
	status_text = "入山"
	_ensure_mouse_controls()

func practice_tick(delta: float) -> void:
	step_game(delta)

func demo_tick(delta: float) -> void:
	pressed[1] = true
	if grounded and phase_time > 0.4 and phase_time < 0.6: game_edge(0, true)
	step_game(delta)

func practice_edge(direction: int, down: bool) -> void:
	game_edge(direction, down)

func game_edge(direction: int, down: bool) -> void:
	if direction != 0: return
	if down: jump_buffer = 0.14
	elif _velocity.y < -160.0:
		_velocity.y *= 0.45
		_jump_cut = true

func pointer_edge(point: Vector2, down: bool) -> void:
	super.pointer_edge(point,down)

func profile_pointer_direction(point: Vector2) -> int:
	if LEFT_MOUSE_BUTTON.has_point(point): return -1
	if RIGHT_MOUSE_BUTTON.has_point(point): return 1
	return 2

func _ensure_mouse_controls() -> void:
	if not _mouse_controls.is_empty():
		_layout_mouse_controls()
		return
	for direction: int in [-1,1]:
		var button := Button.new()
		button.name = "MoveLeft" if direction < 0 else "MoveRight"
		button.text = "◀" if direction < 0 else "▶"
		button.tooltip_text = "按住向左走；右键跳" if direction < 0 else "按住向右走；右键跳"
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.button_down.connect(_mouse_move_down.bind(direction))
		button.button_up.connect(_mouse_move_up.bind(direction))
		button.gui_input.connect(_mouse_control_gui_input)
		for state: String in ["normal","hover","pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("e5c989") if state == "pressed" else Color("46372b")
			style.border_color = Color("e5c989")
			style.set_border_width_all(2)
			button.add_theme_stylebox_override(state,style)
			button.add_theme_color_override("font_%s_color" % state,Color("241f1c") if state == "pressed" else Color("fff0d1"))
		button.add_theme_color_override("font_color",Color("fff0d1"))
		add_child(button)
		_mouse_controls.append(button)
	resized.connect(_layout_mouse_controls)
	control_hints_changed.connect(_update_mouse_control_state)
	_layout_mouse_controls()
	_update_mouse_control_state()

func _layout_mouse_controls() -> void:
	var factor := maxf(0.001,minf(size.x/STAGE.x,size.y/STAGE.y))
	var offset := (size-STAGE*factor)*0.5
	var rectangles: Array[Rect2] = [LEFT_MOUSE_BUTTON,RIGHT_MOUSE_BUTTON]
	var physical := maxf(0.1,(get_viewport().get_stretch_transform()*get_global_transform_with_canvas()).get_scale().y)
	for i: int in _mouse_controls.size():
		_mouse_controls[i].position = offset + rectangles[i].position*factor
		_mouse_controls[i].size = (rectangles[i].size*factor).max(Vector2.ONE*(48.0/physical))
		_mouse_controls[i].add_theme_font_size_override("font_size",ceili(24.0/physical))

func _update_mouse_control_state() -> void:
	for i: int in _mouse_controls.size():
		_mouse_controls[i].visible = get_input_device() == &"mouse" and run_state != RunState.FINISHED
		_mouse_controls[i].self_modulate = Color("ffe6af") if bool(pressed[-1 if i == 0 else 1]) else Color.WHITE

func _mouse_move_down(direction: int) -> void:
	if is_input_active() and resume_countdown <= 0.0 and input_profile != null:
		input_profile.pointer_edge(direction,true)

func _mouse_move_up(direction: int) -> void:
	if input_profile != null: input_profile.pointer_edge(direction,false)

func _mouse_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_input_active() and resume_countdown <= 0.0 and input_profile != null:
			input_profile.pointer_edge(0,event.pressed,MOUSE_BUTTON_RIGHT)
			accept_event()

func on_suspension_changed(suspended: bool) -> void:
	mouse_walk_direction = 0
	super.on_suspension_changed(suspended)

func step_game(delta: float) -> void:
	landing_feedback = maxf(0.0, landing_feedback - delta)
	if recover > 0.0:
		recover = maxf(0.0, recover - delta)
		pose = &"recover"
		return
	var axis: float = float(bool(pressed[1])) - float(bool(pressed[-1]))
	_velocity.x = move_toward(_velocity.x, axis * MOVE_SPEED, 1400 * delta)
	coyote = 0.12 if grounded else maxf(0.0,coyote-delta)
	jump_buffer = maxf(0.0,jump_buffer-delta)
	if jump_buffer > 0.0 and coyote > 0.0:
		_velocity.y = -JUMP_SPEED
		grounded = false
		coyote = 0.0
		jump_buffer = 0.0
		_jump_cut = false
		_airborne_jump = true
		play_feedback(true)
	var was_grounded: bool = grounded
	var previous_position: Vector2 = _player_position
	var previous_bottom: float = _player_position.y + PLAYER_SIZE.y
	_velocity.y += GRAVITY * delta
	_player_position += _velocity * delta
	_player_position.x = maxf(0.0, _player_position.x)
	# Solid platform sides agree with their drawn rock faces.
	for platform: Rect2 in _platforms:
		if _player_position.y + PLAYER_SIZE.y <= platform.position.y + 1 or _player_position.y >= platform.end.y: continue
		if previous_position.x + PLAYER_SIZE.x <= platform.position.x and _player_position.x + PLAYER_SIZE.x > platform.position.x:
			_player_position.x = platform.position.x - PLAYER_SIZE.x
			_velocity.x = 0.0
		elif previous_position.x >= platform.end.x and _player_position.x < platform.end.x:
			_player_position.x = platform.end.x
			_velocity.x = 0.0
	grounded = false
	if _velocity.y >= 0.0:
		for platform: Rect2 in _platforms:
			if _player_position.x + PLAYER_SIZE.x > platform.position.x and _player_position.x < platform.end.x and previous_bottom <= platform.position.y + 1 and _player_position.y + PLAYER_SIZE.y >= platform.position.y:
				_player_position.y = platform.position.y-PLAYER_SIZE.y
				_velocity.y = 0.0
				grounded = true
				if not was_grounded:
					landing_feedback = 0.12
					if phase == Phase.PRACTICE and _airborne_jump:
						if _jump_cut: _practiced_short = true
						else: _practiced_long = true
					_airborne_jump = false
				# Checkpoints are on the broad left end, before hazards.
				if platform.position.x > _checkpoint.x + 100:
					_checkpoint = platform.position + Vector2(18,-PLAYER_SIZE.y)
				break
	var player_rect := Rect2(_player_position,PLAYER_SIZE)
	for hazard: Rect2 in _hazards:
		if player_rect.intersects(hazard): _respawn(); break
	if recover <= 0.0:
		for branch: Rect2 in _low_branches:
			if player_rect.intersects(branch): _respawn(); break
	if _player_position.y > 680: _respawn()
	camera_x = clampf(_player_position.x-280,0,7450)
	set_progress(clampf(_player_position.x/_goal.position.x,0,1))
	section = &"forest" if _player_position.x < 2600 else (&"creek" if _player_position.x < 5200 else &"ridge")
	status_text = "入山 · 低枝下轻点跳" if section == &"forest" else ("过涧 · 提前起跳，看清落点" if section == &"creek" else "登高 · 连续台阶，落稳再跳")
	obstacle_warning = 0.0
	for hazard: Rect2 in _hazards:
		var ahead: float = hazard.position.x - _player_position.x
		if ahead > 0 and ahead <= 320:
			obstacle_warning = maxf(obstacle_warning, 1.0 - ahead / 360.0)
	pose = &"recover" if recover > 0 else (&"land" if landing_feedback > 0 else (&"run" if grounded and absf(_velocity.x)>10 else &"idle"))
	if not grounded: pose = (&"jump_short" if _jump_cut else &"jump_long") if _velocity.y < 0 else &"fall"
	if phase == Phase.PRACTICE:
		status_text = "短跳完成，再按住跳一次" if _practiced_short else "先轻点跳跃，再松开"
		lesson_text = "按住跳，落地后松开" if _practiced_short else "轻点跳，松开后落地"
		if _practiced_short and _practiced_long:
			finish_lesson()
			return
	if phase == Phase.LIVE and player_rect.intersects(_goal):
		pose = &"gather"
		set_progress(1.0)
		complete_success({"falls":mistakes, "route_length":_goal.position.x, "route_version":2}, "药草采到了")

func _respawn() -> void:
	_player_position = _checkpoint
	_velocity = Vector2.ZERO
	grounded = true
	coyote = 0.12
	jump_buffer = 0.0
	_airborne_jump = false
	recover = 0.45
	mistakes += 1
	play_feedback(false)

func get_presentation_state() -> Dictionary:
	return {"pose": pose, "section": section, "position": _player_position,
		"velocity": _velocity, "camera_x": camera_x, "feet": _player_position + Vector2(15,44),
		"checkpoint": _checkpoint, "recovery": recover, "warning": obstacle_warning,
		"platforms": _platforms, "rocks": _hazards, "branches": _low_branches,
		"goal": _goal, "grounded": grounded}

func on_time_expired() -> void:
	complete_failure(&"summit_not_reached", "沿检查点再试一次", {"falls": mistakes})

func draw_pixel_overlay() -> void:
	var art: Resource = context.metadata.get(&"presentation") if context != null else null
	if art != null and int(art.get("version")) >= 2: return
	var host_instructions := context != null and bool(context.metadata.get("host_instruction_overlay",false))
	if not host_instructions:
		draw_rect(Rect2(342,537,598,37),Color(.1,.14,.11,.87))
		label_at(Vector2(354,563),"A / D 移动 · 空格跳｜鼠标按左右走，右键跳",18,PAPER)
	for branch: Rect2 in _low_branches:
		if branch.end.x > _player_position.x and branch.position.x-_player_position.x<650:
			var point := branch.position-Vector2(camera_x,0)+Vector2(4,-10)
			draw_rect(Rect2(point-Vector2(4,23),Vector2(186,29)),Color(.14,.12,.1,.88))
			label_at(point,"低枝 · 轻点跳",18,PAPER)

func draw_scene() -> void:
	hills(camera_x*0.2)
	for platform: Rect2 in _platforms:
		var rect := Rect2(platform.position-Vector2(camera_x,0),platform.size)
		draw_rect(rect, Color("698474"))
		draw_line(rect.position,Vector2(rect.end.x,rect.position.y), GOLD,5)
	for hazard: Rect2 in _hazards:
		var p := hazard.position-Vector2(camera_x,0)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,20),p+Vector2(16,0),p+Vector2(32,20)]), RED)
		if hazard.position.x - _player_position.x > 0 and hazard.position.x - _player_position.x < 320:
			draw_line(p+Vector2(5,-8),p+Vector2(10,-14),GOLD,3)
	for branch: Rect2 in _low_branches:
		var p := branch.position - Vector2(camera_x,0)
		draw_rect(Rect2(p,branch.size),Color("654e3e"))
		if branch.end.x > _player_position.x and branch.position.x - _player_position.x < 650:
			label_at(p+Vector2(18,-12),"低枝 · 轻点跳",18)
	for platform: Rect2 in _platforms:
		if platform.position.x <= 0: continue
		var point := platform.position + Vector2(18,0) - Vector2(camera_x,0)
		draw_line(point,point-Vector2(0,24),GOLD,3)
	var goal_point := Vector2(8210-camera_x,205)
	draw_line(goal_point,goal_point-Vector2(0,100),INK,5)
	draw_colored_polygon(PackedVector2Array([goal_point-Vector2(0,100),goal_point+Vector2(55,-83),goal_point-Vector2(0,65)]),GOLD)
	for i: int in 3:
		draw_line(goal_point+Vector2(-30+i*14,0),goal_point+Vector2(-30+i*14,-30),TEAL,4)
	# Temporary drawing is fitted to the 30×44 collision footprint; the pixel
	# presentation replaces it using the same feet anchor.
	var p := _player_position-Vector2(camera_x,0)
	draw_rect(Rect2(p+Vector2(4,15),Vector2(22,23)),RED if recover>0 else TEAL)
	draw_circle(p+Vector2(15,9),9,Color("cfaa7f"))
	draw_line(p+Vector2(8,35),p+Vector2(8,44),INK,4)
	draw_line(p+Vector2(22,35),p+Vector2(22,44),INK,4)
	label_at(Vector2(345,565),"A / D 移动 · 空格跳；鼠标右键跳",19)
