class_name TutorialController
extends Node

signal step_changed(step: int)
signal tutorial_completed

const SCREENSHOT_PATH := "res://Tutorial/tangsu_example.png"
var progress_path := "user://intro_tutorial.cfg"
var step := 0
var player: PlayerClass
var hud: HUD
var overlay: TutorialOverlay
var layer: CanvasLayer
var _generation := -1
var _idle := 0.0
var _hint_shown := false
var _active := false
var _score_seen := false
var _attempt: HeritageTaskAttempt
var _page_lease := -1
var _detail: 非遗详情弹窗
var _last_target: Control
var _device := &"mouse"
var _arrived := false
var _pending_start := false
var _target_dirty := true
var _cached_target: Control
var _confirm_sound: AudioStreamPlayer
var _focus_original: Dictionary = {}

func configure(subject: PlayerClass, interface: HUD) -> void:
	_confirm_sound = AudioStreamPlayer.new()
	_confirm_sound.stream = preload("res://InheritanceTasks/Audio/rhythm-v2/confirm.wav")
	_confirm_sound.volume_db = -18.0
	add_child(_confirm_sound)
	player = subject
	hud = interface
	GameManager.tutorial_controller = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	overlay = TutorialOverlay.new()
	layer.add_child(overlay)
	overlay.primary_requested.connect(_on_primary)
	overlay.exit_requested.connect(_leave.bind(false))
	overlay.hint_requested.connect(_show_hint)
	overlay.rules.pressed.connect(func() -> void: hud.open_game_guide())
	player.movement_completed.connect(_on_arrival)
	TurnManager.modal_state_changed.connect(_on_modal_state_changed)
	TurnManager.phase_changed.connect(_on_phase)
	TurnManager.turn_completed.connect(_on_turn_completed)
	ResourceManager.feiyi_hand_changed.connect(_on_collection)
	FoodManager.food_resolution_finished.connect(_on_food)
	hud.score_overlay.visibility_changed.connect(_on_score_visibility)
	hud.detail_panel.visibility_changed.connect(_target_changed)
	hud.backpack_panel.visibility_changed.connect(_target_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	TurnManager.start_game([player])
	TurnManager.turn_timer.stop()
	_generation = TurnManager.get_session_generation()
	_active = true
	var deck: Array = ResourceManager.地区非遗牌库[MapSection.REGION.天门]
	deck.erase(TutorialDefinition.CARD)
	deck.append(TutorialDefinition.CARD)
	ResourceManager.add_food_card(player, TutorialDefinition.FOOD)
	hud._set_focus_mode(true)
	hud.map_zoom_factor = 2.0
	hud.update_camera_view(0.0)
	_install_pause_actions()
	_set_step(0)
	overlay.show_page("入门教学 · 一起出发", "左侧看精力，右侧放收藏。\n练习补给：一份鱼面，恢复2点精力。", "开始练习")
	if not ResourceLoader.exists(SCREENSHOT_PATH):
		_show_error("传承示意图缺失，请检查游戏文件。")

func _is_suspended() -> bool:
	return hud.pause_overlay.visible or hud.game_guide.is_guide_open()

func is_current() -> bool:
	return _active and GameManager.is_tutorial_session() and _generation == TurnManager.get_session_generation() and is_instance_valid(player)

func allows_action(action: StringName, target: Variant = null) -> bool:
	if not is_current() or _is_suspended() or overlay.modal.visible: return false
	match action:
		&"move": return step == 1 and target is MapSection and target.location_index == TutorialDefinition.DESTINATION
		&"collect": return step == 2
		&"food": return step == 3
		&"inherit": return step == 4
		&"end": return step == 6 or (step == 1 and _arrived)
	return false

func _set_step(value: int) -> void:
	step = value
	_idle = 0
	_hint_shown = false
	_last_target = null
	_target_dirty = true
	overlay.set_step(step, TutorialDefinition.PROMPTS[step])
	_sync_buttons()
	if step > 1: _confirm_sound.play()
	step_changed.emit(step)

func _sync_buttons() -> void:
	if not is_instance_valid(hud): return
	if step > 0 and step < 7:
		hud._update_button_states(TurnManager.now_phase)
	apply_button_rules()
	if hud.detail_panel.visible:
		hud.detail_panel._refresh_task_panel()

func apply_button_rules() -> void:
	hud.btn_action.disabled = hud.btn_action.disabled or step != 2
	hud.btn_food.disabled = step != 3
	hud.btn_end_turn.disabled = not (step == 6 or (step == 1 and _arrived))

func _on_primary() -> void:
	if not is_current(): return
	if overlay.primary.text == "重新开始":
		restart()
		return
	if step == 0:
		_pending_start = true
		_try_begin()
	elif _attempt != null:
		var attempt := _attempt
		_attempt = null
		if not HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.success(attempt.task_id, {&"tutorial_demonstration": true}, "教学示意解锁")):
			_show_error("教学解锁未完成，请重新开始。")
			return
		_release_page()
		overlay.close_page()
		_set_step(5)
		if is_instance_valid(_detail): _detail._render_current_card()
	elif step == 7:
		_leave(true)

func _on_modal_state_changed(_snapshot: Dictionary) -> void:
	if _pending_start: _try_begin.call_deferred()

func _try_begin() -> void:
	if not _pending_start or not is_current() or step != 0: return
	if TurnManager.modal_resolution_depth > 0 or _is_suspended():
		overlay.primary.text = "准备出发…"
		overlay.primary.disabled = true
		return
	_pending_start = false
	overlay.close_page()
	_set_step(1)
	TurnManager._on_timer_timeout()

func _on_arrival(destination: Vector3i) -> void:
	if not is_current() or step != 1 or destination != TutorialDefinition.DESTINATION: return
	_arrived = true
	_last_target = null
	_target_dirty = true
	_sync_buttons()
	overlay.flash = 0.3

func _on_phase(phase: TurnManager.TurnPhase) -> void:
	if not is_current(): return
	if phase == TurnManager.TurnPhase.MOVING:
		overlay.prompt.text = TutorialDefinition.PROMPTS[1]
		# Keep normal path finding; only the lesson destination is suggested.
		for section: MapSection in player.map.grid_map.values():
			section.is_reachable = section.location_index == TutorialDefinition.DESTINATION
	elif phase == TurnManager.TurnPhase.ACTION and step == 1 and player.now_pos == TutorialDefinition.DESTINATION:
		_set_step(2)
	_sync_buttons.call_deferred()

func _on_collection(owner: PlayerClass) -> void:
	if is_current() and owner == player and step == 2 and player.非遗牌手牌.has(TutorialDefinition.CARD):
		_set_step(3)

func _on_food(owner: PlayerClass, result: FoodResolutionResult) -> void:
	if is_current() and owner == player and step == 3 and result != null and result.success:
		_set_step(4)

func present_inheritance(detail: 非遗详情弹窗) -> void:
	if not allows_action(&"inherit") or detail.current_player != player or detail.current_card != TutorialDefinition.CARD: return
	var picture := load(SCREENSHOT_PATH) as Texture2D
	if picture == null:
		_show_error("传承示意图无法读取。")
		return
	_attempt = HeritageTaskManager.begin_attempt(player, detail.current_card)
	if _attempt == null: return
	_detail = detail
	_page_lease = TurnManager.acquire_modal(&"tutorial_example", TurnManager.ModalResumePolicy.NO_RESUME)
	overlay.show_page("天门糖塑 · 教学示意", "按住吹气，提前松开  →  完成小游戏，解锁5分\n本次直接解锁；正式对局需要亲自完成。", "继续", picture)

func _on_score_visibility() -> void:
	_target_dirty = true
	if not is_current() or step != 5: return
	if hud.score_overlay.visible:
		_score_seen = true
	elif _score_seen:
		_set_step(6)

func _on_turn_completed(owner: PlayerClass, _turn: int) -> void:
	if not is_current() or step != 6 or owner != player: return
	_set_step(7)
	_page_lease = TurnManager.acquire_modal(&"tutorial_complete", TurnManager.ModalResumePolicy.NO_RESUME)
	var progress := ConfigFile.new()
	progress.set_value("intro", "completed_version", TutorialDefinition.VERSION)
	var error := progress.save(progress_path)
	if error != OK: push_warning("入门完成记录未能保存：%s" % error_string(error))
	overlay.show_page("入门完成", "移动 → 收集 → 补给 → 结束\n收集非遗、完成传承，向20分出发。", "开始本地游戏")
	overlay.rules.show()
	tutorial_completed.emit()

func _target_changed() -> void:
	_last_target = null
	_target_dirty = true
	_sync_buttons.call_deferred()

func _target() -> Control:
	if _target_dirty or (_cached_target != null and not is_instance_valid(_cached_target)):
		_cached_target = _resolve_target()
		_target_dirty = false
	return _cached_target

func _resolve_target() -> Control:
	if hud.score_overlay.visible: return hud.score_overlay.close_button
	if hud.backpack_panel.visible:
		if step != 3: return hud.backpack_panel.btn_close
		for item: Node in hud.backpack_panel.grid_container.get_children():
			if not item.is_queued_for_deletion() and item.get("action_button") != null:
				return item.action_button
		return hud.backpack_panel.btn_close
	if hud.detail_panel.visible:
		if step == 4: return hud.detail_panel.task_button
		return hud.detail_panel.get_node("BtnClose") as Control
	match step:
		1:
			if _arrived: return hud.btn_end_turn
		2: return hud.btn_action
		3: return hud.btn_food
		4:
			for node in hud.feiyi_list.find_children("*", "TextureButton", true, false):
				if node.get("card_data") == TutorialDefinition.CARD: return node
		5: return hud.score_label
		6: return hud.btn_end_turn
	return null

func _process(delta: float) -> void:
	if not is_current(): return
	var suspended := _is_suspended()
	overlay.visible = not suspended
	if suspended: return
	if overlay.modal.visible: return
	_idle += delta
	if _idle >= 10.0 and not _hint_shown:
		_hint_shown = true
		overlay.flash = 0.3
	if _idle >= 20.0 and not overlay.hint.visible:
		overlay.hint.show()
		var hint_target := _target()
		if is_instance_valid(hint_target):
			hint_target.focus_next = hint_target.get_path_to(overlay.hint)
			overlay.hint.focus_next = overlay.hint.get_path_to(hint_target)
	if overlay.flash > 0:
		overlay.flash = maxf(0, overlay.flash - delta)
		overlay.queue_redraw()
	var area: Control = hud.get_node("手牌信息") as Control
	var next_rect := area.get_global_rect().grow(-18 * overlay.unit)
	next_rect.size.x = minf(next_rect.size.x, hud.btn_action.get_global_rect().position.x - 24 * overlay.unit - next_rect.position.x)
	# On modal pages use an unobstructed footer beneath their existing buttons.
	var in_detail: bool = hud.detail_panel.visible or hud.backpack_panel.visible or hud.score_overlay.visible
	if in_detail:
		next_rect = Rect2(Vector2(overlay.size.x * 0.14, overlay.size.y - 94 * overlay.unit), Vector2(overlay.size.x * 0.72, 80 * overlay.unit))
	overlay.badge.position = Vector2(overlay.size.x - 260 * overlay.unit, 10 * overlay.unit) if in_detail else Vector2(30, 76) * overlay.unit
	overlay.badge.size = Vector2(240 if in_detail else 460, 42) * overlay.unit
	overlay.badge.text = "入门教学 · %d/7" % mini(step + 1, 7) if in_detail else "入门教学 · %d/7 %s" % [mini(step + 1, 7), TutorialDefinition.TITLES[step]]
	if next_rect != overlay.instruction_rect:
		overlay.instruction_rect = next_rect
		overlay.layout()
	hud.information.visible = false
	hud.current_status.visible = false
	var target := _target()
	var rect := Rect2()
	if is_instance_valid(target) and target.is_visible_in_tree():
		rect = target.get_global_rect()
		if target != _last_target:
			_last_target = target
			if _device != &"mouse":
				_allow_focus(target)
				target.call_deferred(&"grab_focus")
	elif step == 1 and not _arrived and TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		rect = hud.get_tutorial_map_rect(TutorialDefinition.DESTINATION)
	if overlay.highlight != rect:
		overlay.highlight = rect
		overlay.queue_redraw()
	# Contextual hints replace the main line, never add another paragraph.
	if hud.detail_panel.visible and step == 3: overlay.prompt.text = "先关闭详情，再打开“食物”。"
	elif hud.backpack_panel.visible and step == 4: overlay.prompt.text = "精力＋2！关闭背包看看收藏。"
	elif hud.detail_panel.visible and step == 4: overlay.prompt.text = "点“传承任务”，看看怎样解锁。"
	elif hud.detail_panel.visible and step == 5: overlay.prompt.text = "已解锁5分，关闭详情看看总分。"
	elif hud.score_overlay.visible: overlay.prompt.text = "积分点买东西，总分决定胜负。\n同类、同地区的收藏可组合加分。"
	elif step == 1 and _arrived: overlay.prompt.text = "精力－1。点“结束移动”。"
	elif step == 1 and not _arrived and _device != &"mouse": overlay.prompt.text = "方向选中非遗点，按确认前往。"
	elif _idle < 20: overlay.prompt.text = TutorialDefinition.PROMPTS[step]

func _show_hint() -> void:
	overlay.prompt.text = TutorialDefinition.HINTS[step]
	overlay.flash = 0.3
	_idle = 21.0

func _allow_focus(target: Control) -> void:
	if not _focus_original.has(target): _focus_original[target] = target.focus_mode
	target.focus_mode = Control.FOCUS_ALL

func _on_focus_changed(control: Control) -> void:
	if not is_current() or _is_suspended() or _device == &"mouse": return
	if overlay.modal.visible:
		if control not in [overlay.primary, overlay.secondary, overlay.rules]: overlay.primary.call_deferred(&"grab_focus")
		return
	if control == overlay.hint and overlay.hint.visible: return
	var target := _target()
	if target == null: target = overlay
	if control != target:
		_allow_focus(target)
		target.call_deferred(&"grab_focus")

func _input(event: InputEvent) -> void:
	if not is_current(): return
	var previous_device := _device
	if event is InputEventKey and event.pressed and not event.echo:
		_device = &"keyboard"
	elif event is InputEventJoypadButton and event.pressed:
		_device = &"gamepad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65:
		_device = &"gamepad"
	elif event is InputEventMouseButton and event.pressed:
		_device = &"mouse"
	if previous_device != _device:
		_last_target = null
		overlay.set_input_device(_device)
	if event.is_action_pressed("ui_cancel") and not _is_suspended():
		if hud.pause_overlay.open_pause(): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Settings.is_panel_open(): return
	if is_current() and not hud.game_guide.is_guide_open() and _forward_gamepad(event): return
	if not is_current() or _is_suspended() or overlay.modal.visible: return
	if event is InputEventKey and event.echo: return
	if step == 1 and not _arrived and TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		if event.is_action_pressed("ui_accept"):
			player.map._on_section_clicked(player.map.grid_map[TutorialDefinition.DESTINATION])
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			overlay.prompt.text = "已选中非遗点，按确认前往。"
			overlay.grab_focus()
			get_viewport().set_input_as_handled()
	elif step == 5 and not hud.detail_panel.visible and not hud.score_overlay.visible and event.is_action_pressed("ui_accept"):
		hud.score_overlay.open_for_player(player)
		get_viewport().set_input_as_handled()

func _forward_gamepad(event: InputEvent) -> bool:
	if not event is InputEventJoypadButton: return false
	var actions := {JOY_BUTTON_A: &"ui_accept", JOY_BUTTON_B: &"ui_cancel", JOY_BUTTON_START: &"ui_cancel", JOY_BUTTON_DPAD_LEFT: &"ui_left", JOY_BUTTON_DPAD_RIGHT: &"ui_right", JOY_BUTTON_DPAD_UP: &"ui_up", JOY_BUTTON_DPAD_DOWN: &"ui_down"}
	if not actions.has(event.button_index): return false
	var action: StringName = actions[event.button_index]
	var mapped := InputEventAction.new()
	mapped.action = action
	mapped.pressed = event.pressed
	get_viewport().set_input_as_handled()
	get_viewport().push_input.call_deferred(mapped)
	return true

func _on_joy_connection_changed(_device_id: int, connected: bool) -> void:
	if not connected and _device == &"gamepad" and is_current(): hud.pause_overlay.open_pause()

func _install_pause_actions() -> void:
	hud.pause_overlay.continue_button.text = "继续练习"
	var container := hud.pause_overlay.continue_button.get_parent()
	for entry in [["重新开始", restart], ["退出教程", _leave.bind(false)]]:
		var button := Button.new()
		button.text = entry[0]
		MainUI.button(button)
		container.add_child(button)
		button.pressed.connect(entry[1])

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_current(): hud.pause_overlay.open_pause()

func _show_error(message: String) -> void:
	overlay.show_page("教学未能继续", message, "重新开始")

func _release_page() -> void:
	if _page_lease >= 0 and _generation == TurnManager.get_session_generation(): TurnManager.release_modal(_page_lease)
	_page_lease = -1

func restart() -> void:
	GameManager.begin_tutorial_session()
	get_tree().call_deferred(&"reload_current_scene")

func _leave(local: bool) -> void:
	GameManager.open_local_setup_on_menu = local
	GameManager.return_to_main_menu()

func cancel() -> void:
	_active = false
	for control in _focus_original:
		if is_instance_valid(control): control.focus_mode = _focus_original[control]
	_focus_original.clear()
	if _attempt != null and _generation == TurnManager.get_session_generation(): HeritageTaskManager.abort_attempt(_attempt, &"session_reset")
	_attempt = null
	_release_page()
	if is_instance_valid(layer): layer.hide()
	if is_instance_valid(hud):
		hud.information.show()
		hud.current_status.show()

func _exit_tree() -> void:
	cancel()
	if GameManager.tutorial_controller == self: GameManager.tutorial_controller = null
