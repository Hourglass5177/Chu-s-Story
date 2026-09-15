extends RefCounted

## Automated observer for the current route. It reads visible geometry and
## motion, and sends ordinary InputEventActions; it never writes game state.
static func edge(task: HeritageTaskBase, action: StringName, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	task.task_input(event)

static func platform(task: HeritageStageTask, delta: float, controls: Dictionary, miss_once: bool = false) -> void:
	_platform_edge(task, &"ui_right", true, controls)
	var jump_left: float = maxf(0.0, float(controls.get("jump_left",0.0)) - delta)
	if jump_left <= 0.0: _platform_edge(task, &"ui_accept", false, controls)
	var p: Vector2 = task.get("_player_position")
	var desired_hold: float = 0.0
	if bool(task.get("grounded")) and float(task.get("recover")) <= 0.0 and jump_left <= 0.0:
		for floor_rect: Rect2 in task.get("_platforms"):
			if p.x >= floor_rect.position.x - 30 and p.x < floor_rect.end.x and absf(p.y+44-floor_rect.position.y)<2:
				if floor_rect.end.x - p.x < 62: desired_hold = 0.42
		for rock: Rect2 in task.get("_hazards"):
			if absf(rock.end.y-p.y-44)>2: continue
			var low_branch: bool = false
			for branch: Rect2 in task.get("_low_branches"):
				if rock.position.x >= branch.position.x and rock.end.x <= branch.end.x: low_branch = true
			var ahead: float = rock.position.x-p.x
			if ahead>0 and ahead<(45.0 if low_branch else 75.0):
				if not miss_once or int(task.get("mistakes")) > 0:
					desired_hold = 0.085 if low_branch else 0.42
		if desired_hold > 0:
			_platform_edge(task, &"ui_accept", true, controls)
			jump_left = desired_hold
	controls["jump_left"] = jump_left

static func _platform_edge(task: HeritageStageTask, action: StringName, down: bool, controls: Dictionary) -> void:
	if controls.get("edge_callback") is Callable:
		(controls["edge_callback"] as Callable).call(action,down)
		return
	if not bool(controls.get("pointer",false)):
		edge(task,action,down)
		return
	var edges: Dictionary = controls.get("mouse_edges",{})
	if bool(edges.get(action,false)) == down: return
	edges[action] = down
	controls["mouse_edges"] = edges
	var factor: float = minf(task.size.x/1000.0,task.size.y/600.0)
	var point := Vector2(250 if action==&"ui_right" else 500,540)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if action==&"ui_right" else MOUSE_BUTTON_RIGHT
	event.position = (task.size-Vector2(1000,600)*factor)*0.5 + point*factor
	event.pressed = down
	task.task_gui_input(event)

static func cart(task: HeritageStageTask, miss_once: bool = false) -> void:
	var state: Dictionary = task.call("get_presentation_state")
	var brake: bool = false
	var push: bool = true
	var manage_speed: bool = not miss_once or int(task.get("mistakes")) > 0
	if manage_speed and state.bridge_warning and float(state.bridge_distance) <= float(state.braking_distance)+80:
		brake = float(state.speed) > 96
		push = float(state.speed) < 88
	edge(task, &"ui_left", brake)
	edge(task, &"ui_right", push)
