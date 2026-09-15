extends RefCounted

static func key(task: HeritageTaskBase, code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	task.task_input(event)

static func tap(task: HeritageTaskBase, code: Key) -> void:
	key(task,code,true)
	key(task,code,false)

static func tick(task: HeritageTaskBase, seconds: float) -> void:
	for i: int in ceili(seconds*120): task._process(1.0/120.0)

static func escort(task: HeritageTaskBase, maximum_only: bool = false, reaction_seconds: float = .45) -> void:
	# Inspect only visible boats, with a human-scale delay after a row clears.
	# Never read a hard-coded sequence of route distances or teleport state.
	var visible: Array = task.get_presentation_state().obstacles
	var next_distance := INF
	var blocked: Array[int] = []
	for obstacle: Dictionary in visible:
		if float(obstacle.gap) < -task.Route.COLLISION_HALF_LENGTH: continue
		if float(obstacle.distance) < next_distance:
			next_distance = float(obstacle.distance)
			blocked.clear()
		if float(obstacle.distance) == next_distance: blocked.append(int(obstacle.lane))
	if next_distance != float(task.get_meta(&"driver_row",-1.0)):
		task.set_meta(&"driver_row",next_distance)
		task.set_meta(&"driver_decision_at",float(task.get("game_time"))+reaction_seconds)
	if float(task.get("game_time")) >= float(task.get_meta(&"driver_decision_at",0.0)):
		var current: int = task.get("target_lane")
		var desired := current
		if blocked.has(current):
			var cost := 10
			for candidate: int in 3:
				if not blocked.has(candidate) and absi(candidate-current)<cost:
					cost=absi(candidate-current); desired=candidate
		if current != desired: tap(task,KEY_D if current<desired else KEY_A)
	if maximum_only:
		if task.get("target_speed") < 320.0: tap(task,KEY_W)
	elif task.get("target_speed") < 275.0:
		var wheel := InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true
		task.task_gui_input(wheel)

static func local_point(task: HeritageTaskBase, logical: Vector2) -> Vector2:
	var factor := minf(task.size.x/1000.0,task.size.y/600.0)
	return logical*factor+(task.size-Vector2(1000,600)*factor)*.5

static func mouse(task: HeritageTaskBase, logical: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = local_point(task,logical)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	if not down:
		var global_event := event.duplicate() as InputEventMouseButton
		global_event.position = task.get_global_transform_with_canvas()*event.position
		task._input(global_event)
	task.task_gui_input(event)

static func motion(task: HeritageTaskBase, logical: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = local_point(task,logical)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	task.task_gui_input(event)

static func solve_scene(task: HeritageTaskBase) -> void:
	for direction: Variant in task.get("candidates")[task.get("scene_index")].solution:
		tap(task,{-1:KEY_A,1:KEY_D,-2:KEY_W,2:KEY_S}[int(direction)])
		tick(task,.15)
