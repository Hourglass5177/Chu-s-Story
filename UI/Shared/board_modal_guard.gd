class_name BoardModalGuard
extends Node

## Input-only modal boundary. Business pause ownership remains with each existing panel.
var panel: Control
var close: Callable
var shield: ColorRect
var previous_focus: WeakRef
var previous_z: int
static var stack: Array[BoardModalGuard] = []

static func install(target: Control, on_close: Callable) -> BoardModalGuard:
	var guard := BoardModalGuard.new()
	guard.panel = target
	guard.close = on_close
	target.add_child(guard)
	return guard

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shield = ColorRect.new()
	shield.name = "BoardModalShield"
	shield.color = Color(0.10, 0.07, 0.04, 0.66)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(shield)
	panel.move_child(shield, 0)
	shield.z_index = -1
	panel.visibility_changed.connect(_sync)
	panel.item_rect_changed.connect(_layout)
	panel.get_viewport().size_changed.connect(_layout)
	_sync()

func _layout() -> void:
	var area := panel.get_viewport_rect()
	shield.position = -panel.global_position
	shield.size = area.size

func _sync() -> void:
	if panel.is_visible_in_tree():
		if stack.has(self): return
		var focus := panel.get_viewport().gui_get_focus_owner()
		previous_focus = weakref(focus) if focus != null else null
		previous_z = panel.z_index
		stack.append(self)
		# Keep heritage hosts (100), pause (500), guide (900) above this board panel.
		panel.z_index = 20 + stack.size() * 2
		_layout()
		call_deferred("_focus_first")
	else:
		if not stack.has(self): return
		stack.erase(self)
		panel.z_index = previous_z
		var focus := previous_focus.get_ref() as Control if previous_focus != null else null
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()

func _focus_first() -> void:
	if not panel.is_visible_in_tree(): return
	var controls: Array[Control] = []
	_collect(panel, controls)
	if not controls.is_empty(): controls[0].grab_focus()

func _collect(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.is_visible_in_tree() and node.focus_mode == Control.FOCUS_ALL:
		if not node is BaseButton or not node.disabled: controls.append(node)
	for child in node.get_children():
		if child != shield: _collect(child, controls)

func _input(event: InputEvent) -> void:
	if stack.is_empty() or stack.back() != self or not panel.is_visible_in_tree(): return
	var guide := get_tree().get_first_node_in_group("digital_game_guide") as CanvasItem
	if guide != null and guide.visible: return
	# Higher overlays own input, including inherited-task hosts and the pause menu.
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not panel.is_ancestor_of(focus) and focus != panel:
		var ancestor: Node = focus
		while ancestor != null:
			if ancestor is CanvasItem and ancestor.z_index > panel.z_index and ancestor.is_visible_in_tree(): return
			ancestor = ancestor.get_parent()
	if event.is_action_pressed("ui_cancel"):
		close.call()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		var controls: Array[Control] = []
		_collect(panel, controls)
		if controls.is_empty(): return
		var index := controls.find(get_viewport().gui_get_focus_owner())
		index = posmod(index + (-1 if event.is_action_pressed("ui_focus_prev") else 1), controls.size())
		controls[index].grab_focus()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	stack.erase(self)
