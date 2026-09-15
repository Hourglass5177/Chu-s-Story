class_name HeritageInputProfile
extends RefCounted

## One owner per physical source. UI, lesson hints and rebinding read these same
## definitions; the board game's ui_* InputMap is never changed.
signal action_edge(direction: int, down: bool)
signal semantic_edge(action: StringName, down: bool)
signal value_changed(action: StringName, value: float)
signal device_changed(device: StringName)
signal bindings_changed

const AXIS_PRESS := 0.40
const AXIS_RELEASE := 0.22
var kind: StringName = &"heat"
var device: StringName = &"keyboard"
var active_gamepad: int = -1
var _sources: Dictionary = {}
var _values: Dictionary = {}
var _pointer_travel := Vector2.ZERO
var _pointer_time: int = 0
var _definitions: Array[Dictionary] = []
var _bindings: Dictionary = {}
var _storage_key: StringName
var _hint_templates: Dictionary = {}

func _init(profile_kind: StringName = &"heat", task_key: StringName = &"") -> void:
	kind = profile_kind
	_storage_key = task_key if not task_key.is_empty() else kind
	_definitions = _defaults()
	if kind == &"primary" and not _definitions.is_empty():
		_definitions[0].label = {&"laohekou_si_xian":"按下拨弦",&"jingzhou_hua_gu_xi":"按下接声，长声按住",&"gu_pen_ge":"按下敲击",&"xingshan_min_ge":"振翅，按住滑翔",&"tianmen_tang_su":"按住吹气，提前松开",&"huangmei_xi":"确认"}.get(task_key,"按下操作")
	refresh_bindings()

static func for_task(task: StringName) -> StringName:
	return {&"xia_lian_dan_shu": &"heat", &"yandi_shennong_chuanshuo": &"platform",
		&"xiabaoping_minjian_gushi": &"puzzle", &"dong_yong_chuanshuo": &"cart",
		&"ezhou_diaohua_jianzhi": &"trace", &"xisai_shenzhou_hui": &"escort",
		&"tujia_saye_erhe": &"dance", &"ti_qin_xi": &"bow", &"han_ju": &"spotlight"}.get(task, &"primary")

func _definition(id: StringName, label: String, direction: int, keys: Array, buttons: Array, mouse: int = 0, axes: Array = []) -> Dictionary:
	var keys_out: Array = []
	for code: int in keys: keys_out.append({"type":"key", "code":code})
	var pad_out: Array = []
	for code: int in buttons: pad_out.append({"type":"button", "code":code})
	for axis: Array in axes: pad_out.append({"type":"axis", "code":axis[0], "sign":axis[1]})
	return {"id":id, "label":label, "direction":direction, "keyboard":keys_out,
		"gamepad":pad_out, "mouse":[{"type":"mouse", "code":mouse}] if mouse > 0 else []}

func _defaults() -> Array[Dictionary]:
	var single := _definition(&"primary", "按下操作", 0, [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER], [JOY_BUTTON_A], MOUSE_BUTTON_LEFT)
	if kind in [&"primary", &"heat"]:
		single.label = "按住添火，松开收火" if kind == &"heat" else "按下操作"
		return [single]
	var left := _definition(&"left", "向左", -1, [KEY_A,KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], MOUSE_BUTTON_LEFT, [[JOY_AXIS_LEFT_X,-1]])
	var right := _definition(&"right", "向右", 1, [KEY_D,KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], MOUSE_BUTTON_RIGHT, [[JOY_AXIS_LEFT_X,1]])
	var up := _definition(&"up", "向上", -2, [KEY_W,KEY_UP], [JOY_BUTTON_DPAD_UP], 0, [[JOY_AXIS_LEFT_Y,-1]])
	var down := _definition(&"down", "向下", 2, [KEY_S,KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], 0, [[JOY_AXIS_LEFT_Y,1]])
	match kind:
		&"platform":
			left.label = "向左走"; right.label = "向右走"
			right.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_LEFT}]
			var jump := _definition(&"jump", "按下跳，早松跳低", 0, [KEY_SPACE,KEY_W,KEY_UP,KEY_ENTER,KEY_KP_ENTER], [JOY_BUTTON_A], MOUSE_BUTTON_RIGHT)
			return [left,right,jump]
		&"dance", &"bow", &"spotlight", &"directions":
			left.gamepad.push_front({"type":"button", "code":JOY_BUTTON_LEFT_SHOULDER})
			right.gamepad.push_front({"type":"button", "code":JOY_BUTTON_RIGHT_SHOULDER})
			left.label = "左脚" if kind == &"dance" else "左弓" if kind == &"bow" else "左灯" if kind == &"spotlight" else "左侧"
			right.label = "右脚" if kind == &"dance" else "右弓" if kind == &"bow" else "右灯" if kind == &"spotlight" else "右侧"
			return [left,right]
		&"cart":
			left.id = &"brake"; left.label = "刹车"; left.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_RIGHT}]
			right.id = &"push"; right.label = "推车"; right.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_LEFT}]
			left.gamepad.push_front({"type":"axis", "code":JOY_AXIS_TRIGGER_LEFT,"sign":1})
			right.gamepad.push_front({"type":"axis", "code":JOY_AXIS_TRIGGER_RIGHT,"sign":1})
			return [left,right]
		&"escort", &"boat":
			left.label = "左换道"; right.label = "右换道"
			right.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_LEFT}]
			up.id = &"accelerate"; up.label = "加速"; up.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_WHEEL_UP}]
			down.id = &"decelerate"; down.label = "减速"; down.mouse = [{"type":"mouse", "code":MOUSE_BUTTON_WHEEL_DOWN}]
			up.gamepad.push_front({"type":"axis", "code":JOY_AXIS_TRIGGER_RIGHT,"sign":1})
			down.gamepad.push_front({"type":"axis", "code":JOY_AXIS_TRIGGER_LEFT,"sign":1})
			return [left,right,up,down]
		&"puzzle":
			left.label = "空格向左"; right.label = "空格向右"; up.label = "空格向上"; down.label = "空格向下"
			for entry: Dictionary in [left,right,up,down]: entry.mouse = []
			return [left,right,up,down]
		&"trace", &"cut":
			for entry: Dictionary in [left,right,up,down]: entry.mouse = []
			single.label = "按住下刀"
			return [left,right,up,down,single]
	return [single]

func get_action_definitions() -> Array[Dictionary]:
	return _definitions.duplicate(true)

func bindings_for(action: StringName, family: String) -> Array:
	return _bindings.get(String(action),{}).get(family,[]).duplicate(true)

func refresh_bindings() -> void:
	_bindings.clear()
	_hint_templates.clear()
	var saved := HeritageMinigamePreferences.input_bindings(_storage_key)
	for entry: Dictionary in _definitions:
		var id := String(entry.id)
		_bindings[id] = {}
		for family: String in ["keyboard","gamepad","mouse"]:
			_bindings[id][family] = entry[family].duplicate(true)
			var action_settings: Variant = saved.get(id,{})
			var stored: Variant = action_settings.get(family,null) if action_settings is Dictionary else null
			if stored is Array and not stored.is_empty():
				var valid := true
				for binding: Variant in stored:
					if not binding is Dictionary or not _valid_binding(binding, family): valid = false
				if valid: _bindings[id][family] = stored.duplicate(true)
	clear()
	bindings_changed.emit()

func _valid_binding(binding: Dictionary, family: String) -> bool:
	if family not in ["keyboard","mouse","gamepad"]: return false
	var code := int(binding.get("code",-1))
	if family == "keyboard": return binding.get("type") == "key" and code > 0 and code != KEY_ESCAPE
	if family == "mouse": return binding.get("type") == "mouse" and code in [1,2,3,4,5]
	if binding.get("type") == "button": return code >= 0 and code < JOY_BUTTON_MAX and code != JOY_BUTTON_START
	return binding.get("type") == "axis" and code >= 0 and code < JOY_AXIS_MAX and int(binding.get("sign",0)) in [-1,1]

func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		return {"type":"key", "code":event.physical_keycode if event.physical_keycode else event.keycode}
	if event is InputEventJoypadButton and event.pressed: return {"type":"button","code":event.button_index}
	if event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_PRESS: return {"type":"axis","code":event.axis,"sign":signi(int(event.axis_value * 100))}
	if event is InputEventMouseButton and event.pressed: return {"type":"mouse","code":event.button_index}
	return {}

func rebind(action: StringName, family: String, binding: Dictionary, swap: bool = false) -> Dictionary:
	var id := String(action)
	if not _bindings.has(id) or not _valid_binding(binding,family): return {"ok":false,"reason":"reserved"}
	var conflicts: Array[String] = []
	for other: String in _bindings:
		if other != id and binding in _bindings[other][family]: conflicts.append(other)
	if not conflicts.is_empty() and not swap: return {"ok":false,"reason":"conflict","actions":conflicts}
	var saved := HeritageMinigamePreferences.input_bindings(_storage_key)
	var previous: Array = _bindings[id][family].duplicate(true)
	for other: String in conflicts:
		if not saved.has(other): saved[other] = {}
		saved[other][family] = previous.duplicate(true)
	if not saved.has(id): saved[id] = {}
	saved[id][family] = [binding.duplicate(true)]
	if not HeritageMinigamePreferences.save_input_bindings(_storage_key,saved): return {"ok":false,"reason":"save_failed"}
	refresh_bindings()
	return {"ok":true}

func reset_bindings() -> bool:
	if not HeritageMinigamePreferences.save_input_bindings(_storage_key,{}): return false
	refresh_bindings()
	return true

func handles_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion: return false
	if event is InputEventAction: return not _action_for_alias(event.action).is_empty()
	for entry: Dictionary in _definitions:
		for binding: Dictionary in _bindings[String(entry.id)][_family(event)]:
			if _matches(event,binding): return true
	return false

func _family(event: InputEvent) -> String:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion: return "gamepad"
	if event is InputEventMouseButton or event is InputEventMouseMotion: return "mouse"
	return "keyboard"

func _matches(event: InputEvent, binding: Dictionary) -> bool:
	match String(binding.type):
		"key": return event is InputEventKey and int(binding.code) == (event.physical_keycode if event.physical_keycode else event.keycode)
		"button": return event is InputEventJoypadButton and int(binding.code) == event.button_index
		"axis": return event is InputEventJoypadMotion and int(binding.code) == event.axis
		"mouse": return event is InputEventMouseButton and int(binding.code) == event.button_index
	return false

func note_event_device(event: InputEvent) -> void:
	if event is InputEventMouseMotion: note_pointer_motion(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo: _set_device(&"keyboard")
	elif event is InputEventMouseButton and event.pressed: _set_device(&"mouse")
	elif event is InputEventJoypadButton and event.pressed:
		active_gamepad = event.device; _set_device(&"gamepad")
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_PRESS:
		active_gamepad = event.device; _set_device(&"gamepad")

func route_event(event: InputEvent) -> bool:
	if not handles_event(event): return false
	if event is InputEventKey and event.echo: return true
	note_event_device(event)
	if event is InputEventAction:
		_set_source("action:%s" % event.action, _action_for_alias(event.action), 1.0 if event.pressed else 0.0)
		return true
	for entry: Dictionary in _definitions:
		var id := StringName(entry.id)
		for binding: Dictionary in _bindings[String(id)][_family(event)]:
			if not _matches(event,binding): continue
			var source := "%s:%d:%s:%d:%d" % [_family(event),event.device,binding.type,int(binding.code),int(binding.get("sign",0))]
			var value := 0.0
			if event is InputEventJoypadMotion:
				value = maxf(0,event.axis_value * int(binding.sign))
				var threshold := AXIS_RELEASE if _sources.has(source) else AXIS_PRESS
				if value < threshold: value = 0.0
			else: value = 1.0 if event.is_pressed() else 0.0
			_set_source(source,id,value)
			if event is InputEventMouseButton and event.button_index in [4,5]: _set_source(source,id,0.0)
	return true

func pointer_action(action: StringName, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	if down: _set_device(&"mouse")
	_set_source("mouse:pointer:%d" % button,action,1.0 if down else 0.0)

func pointer_edge(direction: int, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	pointer_action(action_for_direction(direction),down,button)

func note_pointer_motion(relative: Vector2) -> void:
	if device == &"mouse": return
	for source: String in _sources:
		if not source.begins_with("mouse:"):
			_pointer_travel = Vector2.ZERO
			return
	var now := Time.get_ticks_msec()
	if now - _pointer_time > 180:
		_pointer_travel = Vector2.ZERO
		_pointer_time = now
	_pointer_travel += relative
	if _pointer_travel.length() > 16.0:
		_pointer_travel = Vector2.ZERO
		_set_device(&"mouse")

func release_pointer(event: InputEventMouseButton) -> bool:
	if event.pressed: return false
	var consumed := false
	for source: String in _sources.keys():
		if source == "mouse:pointer:%d" % event.button_index or source.ends_with(":mouse:%d:0" % event.button_index):
			_set_source(source,StringName(_sources[source].action),0.0); consumed = true
	return consumed

func clear() -> void:
	_sources.clear(); _values.clear(); _pointer_travel = Vector2.ZERO

func held(direction: int) -> bool:
	return action_value(action_for_direction(direction)) > 0.0

func action_value(action: StringName) -> float:
	return float(_values.get(action,0.0))

func has_pressed_sources() -> bool: return not _sources.is_empty()

func physical_input_held() -> bool:
	if has_pressed_sources(): return true
	for id: String in _bindings:
		for family: String in _bindings[id]:
			for binding: Dictionary in _bindings[id][family]:
				match String(binding.type):
					"key":
						if Input.is_physical_key_pressed(int(binding.code)) or Input.is_key_pressed(int(binding.code)): return true
					"mouse":
						if int(binding.code) in [1,2,3] and Input.is_mouse_button_pressed(int(binding.code)): return true
					"button", "axis":
						for pad: int in Input.get_connected_joypads():
							if binding.type == "button" and Input.is_joy_button_pressed(pad,int(binding.code)): return true
							if binding.type == "axis" and Input.get_joy_axis(pad,int(binding.code)) * int(binding.sign) > AXIS_RELEASE: return true
	return false

func action_for_direction(direction: int) -> StringName:
	for entry: Dictionary in _definitions:
		if int(entry.direction) == direction: return StringName(entry.id)
	return &""

func direction_for_action(action: StringName) -> int:
	for entry: Dictionary in _definitions:
		if entry.id == action: return int(entry.direction)
	return 99

func _action_for_alias(action: StringName) -> StringName:
	var aliases := {&"ui_left":-1,&"heritage_left":-1,&"ui_right":1,&"heritage_right":1,
		&"ui_up":-2,&"heritage_up":-2,&"ui_down":2,&"heritage_down":2,
		&"ui_accept":0,&"heritage_primary":0,&"heritage_jump":0}
	if kind == &"platform" and action == &"ui_up": return &"jump"
	if aliases.has(action): return action_for_direction(int(aliases[action]))
	return action if _bindings.has(String(action)) else &""

func _set_device(value: StringName) -> void:
	if device == value: return
	if value != &"mouse": _pointer_travel = Vector2.ZERO
	device = value; device_changed.emit(device)

func _set_source(source: String, action: StringName, value: float) -> void:
	if action.is_empty(): return
	if _sources.has(source) and StringName(_sources[source].action) != action:
		if value > 0.0: return
		action = StringName(_sources[source].action)
	var previous := action_value(action)
	if value > 0.0: _sources[source] = {"action":action,"value":value}
	else: _sources.erase(source)
	var total := 0.0
	for state: Dictionary in _sources.values():
		if state.action == action: total = maxf(total,float(state.value))
	_values[action] = total
	if not is_equal_approx(previous,total): value_changed.emit(action,total)
	if (previous > 0) == (total > 0): return
	semantic_edge.emit(action,total > 0)
	action_edge.emit(direction_for_action(action),total > 0)

func control_hints() -> Array[Dictionary]:
	if not _hint_templates.has(device):
		var templates: Array[Dictionary] = []
		for entry: Dictionary in _definitions:
			var glyphs: Array[String] = []
			for binding: Dictionary in _bindings[String(entry.id)][String(device)]: glyphs.append(binding_glyph(binding))
			if glyphs.is_empty() and device == &"mouse": continue
			templates.append({"id":entry.id,"label":entry.label,"glyphs":glyphs})
		_hint_templates[device] = templates
	var hints: Array[Dictionary] = []
	for template: Dictionary in _hint_templates[device]:
		var hint := template.duplicate()
		hint["held"] = action_value(hint.id)>0
		hints.append(hint)
	return hints

func binding_glyph(binding: Dictionary) -> String:
	match String(binding.type):
		"key":
			var names := {KEY_SPACE:"space",KEY_ENTER:"enter",KEY_KP_ENTER:"enter",KEY_LEFT:"left",KEY_RIGHT:"right",KEY_UP:"up",KEY_DOWN:"down"}
			return "key_" + String(names.get(int(binding.code),OS.get_keycode_string(int(binding.code)).to_lower()))
		"mouse": return {1:"mouse_left",2:"mouse_right",3:"mouse_middle",4:"mouse_wheel_up",5:"mouse_wheel_down"}.get(int(binding.code),"mouse")
		"button": return {JOY_BUTTON_A:"pad_south",JOY_BUTTON_B:"pad_east",JOY_BUTTON_X:"pad_west",JOY_BUTTON_Y:"pad_north",JOY_BUTTON_LEFT_SHOULDER:"pad_lb",JOY_BUTTON_RIGHT_SHOULDER:"pad_rb",JOY_BUTTON_DPAD_LEFT:"pad_dpad_left",JOY_BUTTON_DPAD_RIGHT:"pad_dpad_right",JOY_BUTTON_DPAD_UP:"pad_dpad_up",JOY_BUTTON_DPAD_DOWN:"pad_dpad_down"}.get(int(binding.code),"pad_%d" % int(binding.code))
		"axis":
			if int(binding.code) == JOY_AXIS_TRIGGER_LEFT: return "pad_lt"
			if int(binding.code) == JOY_AXIS_TRIGGER_RIGHT: return "pad_rt"
			return "pad_stick_" + ("left" if int(binding.sign)<0 else "right") if int(binding.code) == JOY_AXIS_LEFT_X else "pad_stick_" + ("up" if int(binding.sign)<0 else "down")
	return "?"
