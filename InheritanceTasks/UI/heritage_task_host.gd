class_name HeritageTaskHost
extends Control

signal task_entered(task_id: StringName)
signal task_finished(result: HeritageTaskResult)
signal return_requested

const AUDIO_BUS: StringName = &"HeritageMinigames"
const TV_SIZE := Vector2(1619, 971)
const TV_SCREEN := Rect2(127, 125, 1173, 670)
const PIXEL_TV_SIZE := Vector2(576, 348)
const PIXEL_TV_SCREEN := Rect2(12, 24, 500, 300)
const PIXEL_TV_PATH := "res://InheritanceTasks/Art/Pixel/v3/runtime/ui/tv.png"
const INPUT_GLYPH := preload("res://InheritanceTasks/UI/heritage_input_glyph.gd")

@onready var title_label: Label = %TitleLabel
@onready var heritage_label: Label = %HeritageLabel
@onready var hook_label: Label = %HookLabel
@onready var control_label: Label = %ControlLabel
@onready var time_label: Label = %TimeLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var task_container: Control = %TaskContainer
@onready var abort_button: Button = %AbortButton
@onready var pause_button: Button = %PauseButton
@onready var pause_panel: Control = %PausePanel
@onready var exit_confirm: Control = %ExitConfirm
@onready var result_panel: Control = %ResultPanel
@onready var result_title: Label = %ResultTitle
@onready var result_message: Label = %ResultMessage
@onready var vocal_breakdown: VBoxContainer = %VocalBreakdown
@onready var return_button: Button = %ReturnButton
@onready var prepare_panel: Control = %PreparePanel
@onready var settings_panel: Control = %SettingsPanel
@onready var _interaction_coordinator: Node = get_node_or_null("/root/InteractionCoordinator")

var definition: HeritageTaskDefinition = null
var context: HeritageTaskRunContext = null
var active_task: HeritageTaskBase = null
var _begun: bool = false
var _terminal_emitted: bool = false
var _entry_emitted: bool = false
var _suspension_reasons: Dictionary[StringName, bool] = {}
var _story_replay_button: Button
var _challenge_started: bool = false
var _screen_rect := Rect2()
var _last_screen_scale: float = 1.0
var _prepare_box: VBoxContainer
var _prepare_body: HBoxContainer
var _prepare_cover: TextureRect
var _prepare_portrait: TextureRect
var _prepare_identity: Label
var _prepare_goal: Label
var _prepare_controls: Label
var _prepare_success: Label
var _prepare_tutorial: Label
var _start_button: Button
var _relearn_button: Button
var _general_settings: GameSettingsPanel
var _settings_box: VBoxContainer
var _volume_slider: HSlider
var _volume_value: Label
var _visual_assistance: CheckButton
var _reduce_motion: CheckButton
var _settings_return: Button
var _calibration_button: Button
var _result_art: TextureRect
var _result_visual_state: Dictionary = {}
var _result_visual_elapsed := 0.0
var _panel_backgrounds: Dictionary[Control, Panel] = {}
var _pixel_shell: bool = false
var _pixel_integer_scale: int = 2
var _pixel_font: Font
var _pixel_aux_font: Font
var _lesson_banner: PanelContainer
var _lesson_badge: Label
var _instruction_label: Label
var _play_hints: HBoxContainer
var _prepare_hints: VBoxContainer
var _pause_hints: VBoxContainer
var _prepare_settings: Button
var _instruction_state: Dictionary = {}
var _hint_signature: String = ""
var _hints_refresh_pending: bool = false
var hint_rows_created: int = 0
var _broadcast: Control
var _settings_previous_panel: Control
var _exit_previous_panel: Control
var _repeat_step: Button
var _skip_lesson: Button
var _bindings_panel: Control
var _bindings_box: VBoxContainer
var _bindings_rows: VBoxContainer
var _bindings_status: Label
var _bindings_family: OptionButton
var _bindings_return: Button
var _binding_conflict: HBoxContainer
var _capture_action: StringName = &""
var _pending_binding: Dictionary = {}
var _pending_action: StringName = &""
var _binding_focus_before: Control


func _ready() -> void:
	BoardMusic.hold_for(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	abort_button.pressed.connect(_on_abort_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%PauseExitButton.pressed.connect(_show_exit_confirm)
	%CancelExitButton.pressed.connect(_hide_exit_confirm)
	%ConfirmExitButton.pressed.connect(_confirm_abort)
	return_button.pressed.connect(func() -> void: return_requested.emit())
	%RetryButton.pressed.connect(_retry_practice)
	for button: Button in [%SettingsButton, %SettingsKnob, %VolumeKnob, %PauseSettingsButton]:
		button.pressed.connect(_show_settings)
	%SettingsKnob.accessibility_name = "小游戏设置"
	%VolumeKnob.accessibility_name = "小游戏音量"
	_build_preparation()
	_build_settings()
	_general_settings = GameSettingsPanel.mount(self)
	Settings.changed.connect(_on_shared_setting_changed)
	_build_bindings()
	_build_pixel_chrome()
	_result_art = _image_rect()
	_result_art.name = "ResultArtwork"
	_result_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_result_art.hide()
	var result_box := result_panel.get_node("Box") as VBoxContainer
	result_box.add_child(_result_art)
	result_box.move_child(_result_art,1)
	for panel: Control in [prepare_panel, pause_panel, settings_panel, exit_confirm, result_panel, _bindings_panel]:
		_add_panel_background(panel)
	for panel: Control in [pause_panel, settings_panel, exit_confirm]:
		var box := panel.get_node("Box") as VBoxContainer
		box.minimum_size_changed.connect(func() -> void: _layout_panel_box.call_deferred(panel, box, false))
	_style_controls(self)
	prepare_panel.hide()
	pause_panel.hide()
	exit_confirm.hide()
	result_panel.hide()
	settings_panel.hide()
	resized.connect(_layout_television.call_deferred)
	vocal_breakdown.minimum_size_changed.connect(_layout_result.call_deferred)
	%ResultScroll.gui_input.connect(_on_result_scroll_input)
	get_tree().node_added.connect(_route_new_audio_node)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_layout_television.call_deferred()
	set_process(true)


func configure(
		p_definition: HeritageTaskDefinition,
		p_context: HeritageTaskRunContext
) -> void:
	_clear_task()
	definition = p_definition
	context = p_context.duplicate_snapshot() if p_context != null else null
	_apply_shell_version()
	_begun = false
	_terminal_emitted = false
	_entry_emitted = false
	_challenge_started = false
	_suspension_reasons.clear()
	_settings_previous_panel = null
	_exit_previous_panel = null
	_capture_action = &""
	_bindings_panel.hide()
	_render_definition()
	pause_panel.hide()
	exit_confirm.hide()
	result_panel.hide()
	prepare_panel.hide()
	settings_panel.hide()


func begin() -> void:
	if _begun:
		return
	_begun = true
	if definition == null or not definition.is_valid_definition():
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id if definition != null else &"",
			&"invalid_definition",
			"任务资源未就绪"
		))
		return
	if context == null:
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id, &"missing_context", "任务数据未就绪"
		))
		return
	active_task = definition.instantiate_task()
	if active_task == null:
		_finish_without_task(HeritageTaskResult.technical_error(
			definition.task_id, &"invalid_task_scene", "任务场景无法载入"
		))
		return
	active_task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active_task.duration_seconds = definition.duration_seconds
	active_task.task_completed.connect(_on_task_completed, CONNECT_ONE_SHOT)
	active_task.manual_abort_requested.connect(_show_exit_confirm)
	active_task.time_changed.connect(_on_time_changed)
	active_task.progress_changed.connect(_on_progress_changed)
	task_container.add_child(active_task)
	active_task.focus_mode = Control.FOCUS_ALL
	active_task.hide()
	context.metadata[&"reference_video_path"] = definition.reference_video_path
	context.metadata[&"reference_audio_path"] = definition.reference_audio_path
	context.metadata[&"reference_analysis_path"] = definition.reference_analysis_path
	context.metadata[&"music_chart"] = definition.music_chart
	context.metadata[&"presentation"] = definition.presentation
	context.metadata[&"host_controls"] = true
	context.metadata[&"host_instruction_overlay"] = _pixel_shell
	context.metadata[&"music_visual_assistance"] = HeritageMinigamePreferences.visual_assistance_enabled()
	context.metadata[&"reduce_motion"] = HeritageMinigamePreferences.reduced_motion_enabled()
	active_task.configure(context)
	if active_task.has_signal("input_device_changed"):
		active_task.connect("input_device_changed", _on_input_device_changed)
	if active_task.has_signal("control_hints_changed"):
		active_task.connect("control_hints_changed", _refresh_control_hints)
	_render_preparation()
	_refresh_control_hints()
	prepare_panel.show()
	pause_button.disabled = true
	_sync_pixel_focus()
	_start_button.grab_focus()
	_layout_television()


func start_from_preparation(relearn: bool = false) -> void:
	if not _begun or _terminal_emitted or _challenge_started or not is_instance_valid(active_task):
		return
	if not _suspension_reasons.is_empty():
		return
	_challenge_started = true
	context.metadata[&"force_tutorial"] = relearn
	context.metadata[&"skip_tutorial"] = not relearn and bool(context.metadata.get(&"skip_tutorial", HeritageMinigamePreferences.tutorial_done(definition.task_id, _tutorial_version())))
	active_task.configure(context)
	prepare_panel.hide()
	pause_button.disabled = false
	_sync_pixel_focus()
	active_task.show()
	active_task.grab_focus()
	_ensure_audio_bus()
	_route_audio_subtree(active_task)
	active_task.start_task()
	# on_task_started() 会同步完成设备、媒体等前置检查。只有任务仍然
	# 处于可玩的运行态，才算真正进入，避免加载/准备故障误解锁图鉴。
	if active_task.run_state == HeritageTaskBase.RunState.RUNNING \
			or active_task.run_state == HeritageTaskBase.RunState.SUSPENDED:
		_emit_task_entered_once()


func suspend() -> void:
	_set_suspension(&"external", true)


func resume() -> void:
	_set_suspension(&"external", false)


func _process(delta: float) -> void:
	var coordinator_suspended := false
	if _interaction_coordinator != null \
			and _interaction_coordinator.has_method("is_active_suspended"):
		coordinator_suspended = bool(_interaction_coordinator.call("is_active_suspended"))
	_set_suspension(&"guide", coordinator_suspended)
	var current_scale := _physical_scale()
	if not is_equal_approx(current_scale, _last_screen_scale):
		_layout_television()
	if _pixel_shell:
		_refresh_instruction_state()
	if result_panel.visible and not _result_visual_state.is_empty() and _result_visual_elapsed < 1.2 and not coordinator_suspended and not _suspension_reasons.has(&"window_focus"):
		_result_visual_elapsed = minf(1.2,_result_visual_elapsed+delta)
		var ending := _result_visual_state.duplicate(true)
		ending["animation_time"] = float(ending.get("animation_time",0.0))+_result_visual_elapsed
		ending["action_time"] = _result_visual_elapsed
		if is_instance_valid(active_task) and is_instance_valid(active_task.pixel_stage):
			active_task.pixel_stage.update_state(ending)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_suspension(&"window_focus", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_suspension(&"window_focus", false)


func cancel(reason: StringName = &"host_cancelled") -> void:
	if _terminal_emitted:
		return
	if is_instance_valid(active_task):
		active_task.cancel_external(reason)
	elif _begun:
		_finish_without_task(HeritageTaskResult.cancelled(
			definition.task_id if definition != null else &"", reason
		))


func get_active_task() -> HeritageTaskBase:
	return active_task


func _render_definition() -> void:
	if definition == null:
		title_label.text = "传承任务"
		heritage_label.text = ""
		hook_label.text = ""
		control_label.text = ""
		time_label.text = "--"
		progress_bar.value = 0.0
		return
	title_label.text = definition.display_name
	heritage_label.text = "楚物志 · %s" % definition.heritage_name
	hook_label.text = definition.hook
	control_label.text = definition.control_hint
	time_label.text = "准备"
	progress_bar.value = 0.0
	%PauseControls.text = definition.control_hint
	%ExitMessage.text = "结束这次练习，返回小游戏图鉴？" if context != null and context.practice_mode else "退出会保留本次精力消耗与挑战次数。"
	if _pixel_shell:
		%ExitMessage.text = "结束这次练习？" if context != null and context.practice_mode else "退出后，本次精力和机会不会返还。"


func _on_time_changed(seconds_left: float) -> void:
	time_label.text = active_task.get_time_display() if is_instance_valid(active_task) else "%d秒" % ceili(seconds_left)


func _on_progress_changed(value: float) -> void:
	progress_bar.value = value * 100.0


func _on_abort_pressed() -> void:
	_show_exit_confirm()


func _on_pause_pressed() -> void:
	if _terminal_emitted or not _challenge_started:
		return
	%PauseTitle.text = "已暂停"
	pause_panel.show()
	_set_suspension(&"local_pause", true)
	_layout_television.call_deferred()
	_sync_pixel_focus()
	%ResumeButton.grab_focus()


func _on_resume_pressed() -> void:
	pause_panel.hide()
	_set_suspension(&"local_pause", false)
	_restore_task_focus()


func _show_exit_confirm() -> void:
	if _terminal_emitted:
		return
	if _pixel_shell and not exit_confirm.visible:
		_exit_previous_panel = _visible_underlay()
		if is_instance_valid(_exit_previous_panel): _exit_previous_panel.hide()
	exit_confirm.show()
	_set_suspension(&"exit_confirm", true)
	_layout_television.call_deferred()
	_sync_pixel_focus()
	%CancelExitButton.grab_focus()


func _hide_exit_confirm() -> void:
	exit_confirm.hide()
	if _pixel_shell and is_instance_valid(_exit_previous_panel): _exit_previous_panel.show()
	_exit_previous_panel = null
	_set_suspension(&"exit_confirm", false)
	_restore_task_focus()


func _confirm_abort() -> void:
	exit_confirm.hide()
	if is_instance_valid(active_task) and _challenge_started:
		# Abort while still suspended: resuming first could apply a buffered score
		# before the player's explicit exit intent. Completion clears all reasons.
		active_task.abort_manual()
	elif _begun:
		_on_task_completed(HeritageTaskResult.manual_abort(definition.task_id))


func _on_task_completed(result: HeritageTaskResult) -> void:
	if _terminal_emitted:
		return
	# 兼容未来可能在 start_task() 内同步完成的轻量任务；技术故障和
	# 外部取消不代表真正进入过玩法。
	if _challenge_started and result.status in [HeritageTaskResult.Status.SUCCESS, HeritageTaskResult.Status.FAILURE, HeritageTaskResult.Status.MANUAL_ABORT]:
		_emit_task_entered_once()
	_terminal_emitted = true
	abort_button.disabled = true
	pause_button.disabled = true
	_suspension_reasons.clear()
	prepare_panel.hide()
	settings_panel.hide()
	if result.status == HeritageTaskResult.Status.MANUAL_ABORT:
		pause_panel.hide()
		exit_confirm.hide()
		result_panel.hide()
		# The owner settles the attempt synchronously before it handles returning.
		task_finished.emit(result)
		return_requested.emit()
		return
	_show_result(result)
	task_finished.emit(result)


func _emit_task_entered_once() -> void:
	if _entry_emitted or definition == null:
		return
	_entry_emitted = true
	task_entered.emit(definition.task_id)


func _finish_without_task(result: HeritageTaskResult) -> void:
	if _terminal_emitted:
		return
	_terminal_emitted = true
	abort_button.disabled = true
	pause_button.disabled = true
	_suspension_reasons.clear()
	_show_result(result)
	task_finished.emit(result)


func _set_suspension(reason: StringName, enabled: bool) -> void:
	if enabled:
		_suspension_reasons[reason] = true
	else:
		_suspension_reasons.erase(reason)
	if is_instance_valid(active_task):
		active_task.set_suspended(not _suspension_reasons.is_empty())
		for child: Node in active_task.get_children():
			if child is HeritageBeatCalibration:
				child.set_suspended(not _suspension_reasons.is_empty())


func _show_result(result: HeritageTaskResult) -> void:
	_bindings_panel.hide()
	_capture_action = &""
	pause_panel.hide()
	exit_confirm.hide()
	prepare_panel.hide()
	settings_panel.hide()
	result_panel.show()
	match result.status:
		HeritageTaskResult.Status.SUCCESS:
			result_title.text = "传承完成"
		HeritageTaskResult.Status.FAILURE:
			result_title.text = "未能完成"
		HeritageTaskResult.Status.TECHNICAL_ERROR:
			result_title.text = "设备或素材暂不可用"
		_:
			result_title.text = "任务已取消"
	var suffix := ""
	var practice := context != null and context.practice_mode
	if not practice and (result.status == HeritageTaskResult.Status.FAILURE or result.status == HeritageTaskResult.Status.MANUAL_ABORT):
		suffix = "\n下个行动阶段可再次挑战。"
	elif not practice and result.status == HeritageTaskResult.Status.TECHNICAL_ERROR:
		suffix = "\n已返还精力与本次机会。"
	result_message.text = (result.message if not result.message.is_empty() else "本次任务已经结束。") + suffix
	if result.metrics.has("grades"):
		var grades: Dictionary = result.metrics.grades
		result_message.text += "\n优 %d   良 %d   失 %d" % [grades.get("优",0),grades.get("良",0),grades.get("失",0)]
		if int(grades.get("release_errors",0))>0: result_message.text += "  ·  收尾失误 %d"%int(grades.release_errors)
	if practice and result.is_success(): result_title.text = "挑战完成"
	vocal_breakdown.display_result(result)
	%ResultScroll.visible = vocal_breakdown.visible
	_result_art.visible = result.status in [HeritageTaskResult.Status.SUCCESS,HeritageTaskResult.Status.FAILURE] and is_instance_valid(active_task) and is_instance_valid(active_task.pixel_stage)
	if _result_art.visible:
		# Settlement has already happened. Show the actual final art without delaying
		# task_finished, charging again, or replacing the numerical/audio result.
		_result_visual_state = active_task.get_visual_state().duplicate(true)
		_result_visual_elapsed = 0.0
		_result_visual_state["action"] = &"success" if result.is_success() else &"miss"
		_result_visual_state["action_time"] = 0.0
		active_task.pixel_stage.update_state(_result_visual_state)
		active_task.queue_redraw()
		_result_art.texture = active_task.pixel_stage.get_texture()
		_result_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER if vocal_breakdown.visible else Control.SIZE_EXPAND_FILL
		_result_art.custom_minimum_size.y = _px(64 if vocal_breakdown.visible else 100)
	else:
		_result_art.texture = null
		_result_visual_state.clear()
	%RetryButton.visible = practice and result.status in [HeritageTaskResult.Status.SUCCESS, HeritageTaskResult.Status.FAILURE]
	if is_instance_valid(_story_replay_button):
		_story_replay_button.queue_free()
		_story_replay_button = null
	if is_instance_valid(active_task) and active_task.has_method("replay_story") and result.status in [HeritageTaskResult.Status.SUCCESS,HeritageTaskResult.Status.FAILURE]:
		var replay := Button.new()
		_story_replay_button = replay
		replay.text = "回看故事"
		result_panel.get_node("Box").add_child(replay)
		result_panel.get_node("Box").move_child(replay, return_button.get_index())
		HeritageTelevisionStyle.button(replay)
		replay.pressed.connect(func() -> void:
			result_panel.hide()
			active_task.call("replay_story"))
		active_task.connect("story_replay_finished", func() -> void:
			result_panel.show()
			return_button.grab_focus())
	%ResultScroll.scroll_vertical = 0
	_style_text(self)
	_layout_result.call_deferred()
	_sync_pixel_focus()
	return_button.grab_focus()


func _layout_result() -> void:
	if not is_node_ready() or not result_panel.visible: return
	var box: VBoxContainer = result_panel.get_node("Box")
	_layout_panel_box(result_panel, box, true)


func _on_result_scroll_input(event: InputEvent) -> void:
	var scroll: ScrollContainer = %ResultScroll
	if not scroll.has_focus(): return
	var direction := 0
	if event.is_action_pressed("ui_down", true): direction = 1
	elif event.is_action_pressed("ui_up", true): direction = -1
	if direction == 0: return
	var previous := scroll.scroll_vertical
	scroll.scroll_vertical += direction * 96
	if scroll.scroll_vertical == previous: return_button.grab_focus()
	scroll.accept_event()


func _restore_task_focus() -> void:
	_sync_pixel_focus()
	if _bindings_panel.visible: _bindings_return.grab_focus()
	elif exit_confirm.visible: %CancelExitButton.grab_focus()
	elif settings_panel.visible: _settings_return.grab_focus()
	elif pause_panel.visible: %ResumeButton.grab_focus()
	elif prepare_panel.visible: _start_button.grab_focus()
	elif result_panel.visible: return_button.grab_focus()
	elif is_instance_valid(active_task) and not _terminal_emitted:
		active_task.grab_focus()


func _clear_task() -> void:
	if is_instance_valid(_story_replay_button): _story_replay_button.queue_free()
	_story_replay_button = null
	if is_instance_valid(_result_art): _result_art.texture = null
	_result_visual_state.clear()
	_result_visual_elapsed = 0.0
	if is_instance_valid(active_task):
		if active_task.task_completed.is_connected(_on_task_completed):
			active_task.task_completed.disconnect(_on_task_completed)
		active_task.cancel_external(&"host_reconfigured")
		active_task.queue_free()
	active_task = null
	if is_instance_valid(task_container):
		for child: Node in task_container.get_children():
			child.queue_free()
	if is_instance_valid(abort_button):
		abort_button.disabled = false
	if is_instance_valid(pause_button):
		pause_button.disabled = false


func _build_preparation() -> void:
	_prepare_box = VBoxContainer.new()
	_prepare_box.name = "Box"
	prepare_panel.add_child(_prepare_box)
	_prepare_body = HBoxContainer.new()
	_prepare_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prepare_box.add_child(_prepare_body)
	var artwork := VBoxContainer.new()
	artwork.name = "Artwork"
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artwork.size_flags_stretch_ratio = 0.85
	_prepare_body.add_child(artwork)
	_prepare_cover = _image_rect()
	_prepare_cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.add_child(_prepare_cover)
	_prepare_portrait = _image_rect()
	_prepare_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	artwork.add_child(_prepare_portrait)
	_prepare_identity = _label("", 28)
	_prepare_identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	artwork.add_child(_prepare_identity)
	var scroll := ScrollContainer.new()
	scroll.name = "InstructionsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.4
	scroll.follow_focus = true
	_prepare_body.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_section_heading("目标"))
	_prepare_goal = _label("", 28)
	details.add_child(_prepare_goal)
	details.add_child(_section_heading("操作"))
	_prepare_controls = _label("", 28)
	details.add_child(_prepare_controls)
	details.add_child(_section_heading("完成条件"))
	_prepare_success = _label("", 28)
	details.add_child(_prepare_success)
	_prepare_tutorial = _label("", 25)
	_prepare_box.add_child(_prepare_tutorial)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 16)
	_prepare_box.add_child(buttons)
	_start_button = _button("开始")
	_start_button.name = "StartButton"
	_start_button.pressed.connect(start_from_preparation)
	buttons.add_child(_start_button)
	_relearn_button = _button("重学")
	_relearn_button.name = "RelearnButton"
	_relearn_button.pressed.connect(start_from_preparation.bind(true))
	buttons.add_child(_relearn_button)
	_prepare_settings = _button("设置")
	_prepare_settings.name = "PrepareSettingsButton"
	_prepare_settings.pressed.connect(_show_settings)
	buttons.add_child(_prepare_settings)


func _section_heading(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	for index: int in 3:
		if index==1:
			var label := _label(text,30)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(label)
		else:
			var lines := VBoxContainer.new()
			lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lines.add_theme_constant_override("separation",3)
			for stroke: int in 2:
				var line := ColorRect.new()
				line.color=Color("907953")
				line.custom_minimum_size.y=2
				line.mouse_filter=Control.MOUSE_FILTER_IGNORE
				lines.add_child(line)
			row.add_child(lines)
	return row

func _render_preparation() -> void:
	_prepare_cover.texture = definition.get_gallery_thumbnail()
	if _pixel_shell and definition.presentation != null and definition.presentation.has_method("get_cover"):
		_prepare_cover.texture = definition.presentation.call("get_cover", context.avatar_id) as Texture2D
	_prepare_goal.text = definition.hook
	_prepare_controls.text = definition.control_hint
	_prepare_success.text = _success_hint()
	_prepare_identity.text = HeritageAvatarCatalog.display_name(context.avatar_id)
	_prepare_portrait.texture = null
	if definition.presentation != null:
		var appearance := definition.presentation.get_appearance(context.avatar_id)
		if appearance != null: _prepare_portrait.texture = appearance.portrait
	if _prepare_portrait.texture == null:
		var professions := get_node_or_null("/root/ProfessionManager")
		var profession: Resource = professions.call("get_definition_by_id", context.avatar_id) if professions != null else null
		if profession != null: _prepare_portrait.texture = profession.get("selection_portrait") as Texture2D
	var has_lesson := active_task.has_method("restart_lesson") or active_task.supports_interactive_tutorial()
	var lesson_done := HeritageMinigamePreferences.tutorial_done(definition.task_id, _tutorial_version())
	_start_button.text = "开始" if lesson_done or not has_lesson else "开始教学"
	_relearn_button.visible = has_lesson and lesson_done
	_prepare_tutorial.text = "已完成教学，可直接开始或重学。" if lesson_done and has_lesson else ("先看示范，再亲手练一次。教学不计时。" if has_lesson else "准备好后开始。")
	if definition.task_id == &"huangmei_xi":
		_prepare_tutorial.text = "每次先听完整示范，再录唱。示范始终保留。"
	if _pixel_shell:
		_prepare_tutorial.text = "随时可重学" if lesson_done and has_lesson else "先练一次，再正式开始"
		if definition.task_id == &"xia_lian_dan_shu":
			_prepare_goal.text = "让炉火跟住火候区"
			_prepare_success.text = "炼制进度达到七成"
		elif definition.task_id == &"yandi_shennong_chuanshuo":
			_prepare_goal.text = "穿过山林，登高采药"
			_prepare_success.text = "45秒内抵达采药点"
		elif definition.task_id == &"ezhou_diaohua_jianzhi":
			_prepare_goal.text = "刻出四处双鸟花枝纹样"
		elif definition.task_id == &"huangmei_xi":
			_prepare_tutorial.text = "先听示范，再录唱"


func _success_hint() -> String:
	# Completion criteria belong here; a last instruction such as "wait for
	# analysis" describes a phase, not what the player needs to achieve.
	match definition.task_id:
		&"laohekou_si_xian", &"tujia_saye_erhe", &"jingzhou_hua_gu_xi", &"han_ju", &"ti_qin_xi":
			return "跟上音乐，得分达到70%"
		&"gu_pen_ge": return "三轮复现，完成两轮"
		&"ezhou_diaohua_jianzhi": return "30秒内闭合四处切口"
		&"huangmei_xi": return "综合60分，每句至少45分"
	if definition.presentation != null:
		var explicit_hint := String(definition.presentation.properties.get("success_hint", ""))
		if not explicit_hint.is_empty(): return explicit_hint
	for index: int in range(definition.instructions.size() - 1, -1, -1):
		var instruction := definition.instructions[index]
		if "通过" in instruction or "完成" in instruction or "终点" in instruction:
			return instruction
	return definition.instructions[-1] if not definition.instructions.is_empty() else definition.hook


func _tutorial_version() -> int:
	return maxi(4,int(active_task.call("tutorial_version"))) if is_instance_valid(active_task) and active_task.has_method("tutorial_version") else 4


func _build_settings() -> void:
	_settings_box = VBoxContainer.new()
	_settings_box.name = "Box"
	settings_panel.add_child(_settings_box)
	var title := _label("小游戏设置", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_box.add_child(title)
	_volume_value = _label("音量", 28)
	_settings_box.add_child(_volume_value)
	_volume_slider = HSlider.new()
	_volume_slider.name = "VolumeSlider"
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 5
	_volume_slider.value = HeritageMinigamePreferences.volume_percent()
	_volume_slider.focus_mode = Control.FOCUS_ALL
	_volume_slider.accessibility_name = "小游戏音量"
	_volume_slider.modulate = Color("936536")
	_volume_slider.value_changed.connect(_on_volume_changed)
	_settings_box.add_child(_volume_slider)
	_volume_value.text = "音量  %d%%" % int(_volume_slider.value)
	_visual_assistance = CheckButton.new()
	_visual_assistance.name = "VisualAssistance"
	_visual_assistance.button_pressed = HeritageMinigamePreferences.visual_assistance_enabled()
	_visual_assistance.text = "音乐方向与预备提示：%s" % ("开" if _visual_assistance.button_pressed else "关")
	_visual_assistance.toggled.connect(_on_visual_assistance_changed)
	_settings_box.add_child(_visual_assistance)
	_reduce_motion = CheckButton.new()
	_reduce_motion.name = "ReduceMotion"
	_reduce_motion.button_pressed = HeritageMinigamePreferences.reduced_motion_enabled()
	_reduce_motion.text = "减少装饰动态：%s" % ("开" if _reduce_motion.button_pressed else "关")
	_reduce_motion.toggled.connect(_on_reduced_motion_changed)
	_settings_box.add_child(_reduce_motion)
	_calibration_button = _button("节拍校准")
	_calibration_button.name = "CalibrationButton"
	_calibration_button.pressed.connect(_open_task_calibration)
	_settings_box.add_child(_calibration_button)
	var bindings := _button("按键与手柄")
	bindings.name = "OpenBindingsButton"
	bindings.pressed.connect(_show_bindings)
	_settings_box.add_child(bindings)
	var general := _button("通用设置")
	general.name = "GeneralSettingsButton"
	general.pressed.connect(func() -> void: _general_settings.open_panel(general))
	_settings_box.add_child(general)
	_settings_return = _button("返回")
	_settings_return.name = "SettingsReturn"
	_settings_return.pressed.connect(_hide_settings)
	_settings_box.add_child(_settings_return)


func _show_settings() -> void:
	if _pixel_shell and not settings_panel.visible:
		_settings_previous_panel = _visible_underlay()
		if is_instance_valid(_settings_previous_panel): _settings_previous_panel.hide()
	_calibration_button.visible = is_instance_valid(active_task) and active_task.has_method("_open_calibration")
	_calibration_button.disabled = not _challenge_started or not _calibration_allowed()
	_calibration_button.tooltip_text = "教学时可校准" if _calibration_button.disabled else "跟随短音调整设备输入偏移"
	settings_panel.show()
	_set_suspension(&"settings", true)
	_layout_television()
	_volume_slider.grab_focus()
	_sync_pixel_focus()


func _hide_settings() -> void:
	settings_panel.hide()
	if _pixel_shell and is_instance_valid(_settings_previous_panel): _settings_previous_panel.show()
	_settings_previous_panel = null
	_set_suspension(&"settings", false)
	_restore_task_focus()


func _calibration_allowed() -> bool:
	return is_instance_valid(active_task) and active_task is HeritageStageTask and active_task.phase != HeritageStageTask.Phase.LIVE


func _open_task_calibration() -> void:
	if not _challenge_started or not _calibration_allowed(): return
	for reason: StringName in _suspension_reasons:
		if reason not in [&"settings", &"local_pause"]: return
	settings_panel.hide()
	pause_panel.hide()
	_set_suspension(&"settings", false)
	_set_suspension(&"local_pause", false)
	active_task.call("_open_calibration")
	for child: Node in active_task.get_children():
		if child is HeritageBeatCalibration:
			child.add_theme_stylebox_override("panel", HeritageTelevisionStyle.panel())
			_style_controls(child)
			_style_text(child)


func _on_volume_changed(value: float) -> void:
	_volume_value.text = "音量  %d%%" % int(value)
	HeritageMinigamePreferences.save_volume_percent(int(value))
	var index := _ensure_audio_bus()
	AudioServer.set_bus_volume_linear(index, value / 100.0)


func _on_visual_assistance_changed(enabled: bool) -> void:
	_visual_assistance.text = "音乐视觉提示" if _pixel_shell else "音乐方向与预备提示：%s" % ("开" if enabled else "关")
	HeritageMinigamePreferences.save_visual_assistance(enabled)
	if context != null: context.metadata[&"music_visual_assistance"] = enabled
	if is_instance_valid(active_task) and active_task.context != null:
		active_task.context.metadata[&"music_visual_assistance"] = enabled
		if active_task is HeritagePerformanceTask:
			active_task.visual_assistance = enabled
			if is_instance_valid(active_task.visual_aid_button):
				active_task.visual_aid_button.set_pressed_no_signal(enabled)
		active_task.queue_redraw()


func _on_reduced_motion_changed(enabled: bool) -> void:
	_reduce_motion.text = "减少装饰动态" if _pixel_shell else "减少装饰动态：%s" % ("开" if enabled else "关")
	HeritageMinigamePreferences.save_reduced_motion(enabled)
	if context != null: context.metadata[&"reduce_motion"] = enabled
	if is_instance_valid(active_task) and active_task.context != null:
		active_task.context.metadata[&"reduce_motion"] = enabled
		if active_task is HeritageStageTask: active_task.reduced_motion = enabled
		active_task.queue_redraw()


func _ensure_audio_bus() -> int:
	var index := AudioServer.get_bus_index(AUDIO_BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, AUDIO_BUS)
		AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_linear(index, HeritageMinigamePreferences.volume_percent() / 100.0)
	return index


func _route_audio_subtree(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D or node is VideoStreamPlayer:
		node.set("bus", AUDIO_BUS)
	for child: Node in node.get_children(): _route_audio_subtree(child)


func _route_new_audio_node(node: Node) -> void:
	if not is_instance_valid(active_task) or not active_task.is_ancestor_of(node): return
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D or node is VideoStreamPlayer:
		_ensure_audio_bus()
		node.set("bus", AUDIO_BUS)


func _retry_practice() -> void:
	if context == null or not context.practice_mode or not _terminal_emitted: return
	var next_context := context.duplicate_snapshot()
	configure(definition, next_context)
	begin()


func _unhandled_input(event: InputEvent) -> void:
	if Settings.is_panel_open(): return
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo(): return
	if _bindings_panel.visible: _hide_bindings()
	elif exit_confirm.visible: _hide_exit_confirm()
	elif settings_panel.visible: _hide_settings()
	elif pause_panel.visible: _on_resume_pressed()
	elif prepare_panel.visible: _show_exit_confirm()
	elif result_panel.visible: return_requested.emit()
	else: return
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if Settings.is_panel_open(): return
	if not _pixel_shell or not visible or event.is_echo(): return
	if not _capture_action.is_empty():
		if event.is_action_pressed(&"ui_cancel"):
			_capture_action = &""; _bindings_status.text = "已取消修改"
		elif is_instance_valid(active_task):
			var profile := active_task.get_input_profile()
			var binding := profile.binding_from_event(event)
			if not binding.is_empty():
				var family := _selected_binding_family()
				var event_family := "keyboard" if event is InputEventKey else "mouse" if event is InputEventMouseButton else "gamepad"
				if family == event_family: _try_binding(binding)
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(active_task):
		var profile := active_task.get_input_profile()
		if event is InputEventMouseMotion:
			profile.note_pointer_motion(event.relative * get_viewport().get_stretch_transform().get_scale())
			return
		else: profile.note_event_device(event)
	var start_pressed: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START and event.pressed
	if not start_pressed and not event.is_action_pressed(&"ui_cancel"): return
	if _bindings_panel.visible or exit_confirm.visible or settings_panel.visible or prepare_panel.visible or result_panel.visible:
		if not start_pressed: _unhandled_input(event)
		else: get_viewport().set_input_as_handled()
		return
	if pause_panel.visible: _on_resume_pressed()
	elif _challenge_started and not _terminal_emitted: _on_pause_pressed()
	else: return
	get_viewport().set_input_as_handled()


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected or not _pixel_shell or not _challenge_started or _terminal_emitted: return
	if not is_instance_valid(active_task) or not active_task.has_method("get_input_device"): return
	if active_task.call("get_input_device") != &"gamepad": return
	if active_task.get_input_profile().active_gamepad != device_id: return
	_on_pause_pressed()
	%PauseTitle.text = "手柄已断开"


func _image_rect() -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta(&"base_font_size", font_size)
	label.add_theme_color_override("font_color", HeritageTelevisionStyle.INK)
	return label


func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta(&"base_font_size", 28)
	return button


func _add_panel_background(panel: Control) -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_theme_stylebox_override("panel", HeritageTelevisionStyle.panel())
	panel.add_child(backdrop)
	panel.move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_backgrounds[panel] = backdrop


func _style_controls(node: Node) -> void:
	if node == task_container or node is GameSettingsPanel: return
	if node is Button:
		HeritageTelevisionStyle.button(node, node == %VolumeKnob or node == %SettingsKnob)
	if node is Label:
		node.add_theme_color_override("font_color", HeritageTelevisionStyle.INK)
	for child: Node in node.get_children(): _style_controls(child)
	if node == self:
		for label: Label in [title_label, heritage_label, time_label, control_label]:
			label.add_theme_color_override("font_color", Color("fff0ca"))
			label.add_theme_color_override("font_outline_color", Color("442415"))
			label.add_theme_constant_override("outline_size", 3)
		title_label.set_meta(&"base_font_size", 44)
		heritage_label.set_meta(&"base_font_size", 26)
		time_label.set_meta(&"base_font_size", 36)
		control_label.set_meta(&"base_font_size", 26)
		result_title.set_meta(&"base_font_size", 42)
		%PauseTitle.set_meta(&"base_font_size", 42)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("ffd17b")
		var background := StyleBoxFlat.new()
		background.bg_color = Color("472d21")
		progress_bar.add_theme_stylebox_override("fill", fill)
		progress_bar.add_theme_stylebox_override("background", background)


func _physical_scale() -> float:
	# canvas_items 的高清 UI 仍使用逻辑坐标；CanvasItem 的屏幕矩阵不含
	# Root Window 的自动 stretch。必须乘上视口 stretch 才能保证真实像素下限。
	var scale_value := (get_viewport().get_stretch_transform() * get_global_transform_with_canvas()).get_scale().abs()
	return maxf(minf(scale_value.x, scale_value.y), 0.1)


func _px(physical_pixels: float) -> float:
	return physical_pixels / _physical_scale()


func _style_text(node: Node) -> void:
	if node == task_container or node is GameSettingsPanel: return
	if _pixel_shell:
		_style_pixel_text(node)
		return
	if node is Label or node is Button:
		var control := node as Control
		if not control.has_meta(&"base_font_size"):
			control.set_meta(&"base_font_size", maxi(control.get_theme_font_size("font_size"), 26))
		var target := maxi(int(control.get_meta(&"base_font_size")), ceili(_px(18)))
		control.add_theme_font_size_override("font_size", target)
	if node is Button:
		(node as Button).custom_minimum_size.y = maxf(68.0, _px(44))
	for child: Node in node.get_children(): _style_text(child)


func _layout_television() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0: return
	if _pixel_shell:
		_layout_pixel_television()
		return
	_last_screen_scale = _physical_scale()
	var factor := minf((size.x - _px(12)) / TV_SIZE.x, (size.y - _px(12)) / TV_SIZE.y)
	var tv_dimensions := TV_SIZE * factor
	var panel := get_node("SafeMargin/Panel") as Control
	panel.position = (size - tv_dimensions) * 0.5
	panel.size = tv_dimensions
	_screen_rect = Rect2(panel.position + TV_SCREEN.position * factor, TV_SCREEN.size * factor)
	task_container.position = TV_SCREEN.position * factor
	task_container.size = TV_SCREEN.size * factor
	_set_tv_rect(get_node("SafeMargin/Panel/Layout/Header"), Rect2(127, 24, 1173, 95), factor)
	_set_tv_rect(get_node("SafeMargin/Panel/Layout/Footer"), Rect2(135, 814, 1157, 72), factor)
	_set_tv_rect(time_label, Rect2(1340, 510, 205, 96), factor)
	_set_tv_rect(%SettingsKnob, Rect2(1359, 131, 165, 159), factor)
	_set_tv_rect(%VolumeKnob, Rect2(1359, 299, 165, 154), factor)
	_set_tv_rect(pause_button, Rect2(1352, 733, 60, 72), factor)
	_set_tv_rect(abort_button, Rect2(1418, 733, 60, 72), factor)
	_set_tv_rect(%SettingsButton, Rect2(1484, 733, 60, 72), factor)
	_style_text(self)
	progress_bar.custom_minimum_size.y = _px(6)
	_prepare_body.add_theme_constant_override("separation", ceili(_px(18)))
	_prepare_portrait.custom_minimum_size.y = minf(_screen_rect.size.y * 0.24, _px(105))
	_volume_slider.custom_minimum_size.y = _px(44)
	_layout_panel_box(prepare_panel, _prepare_box, true)
	_layout_panel_box(settings_panel, _settings_box, false)
	_layout_panel_box(pause_panel, pause_panel.get_node("Box"), false)
	_layout_panel_box(exit_confirm, exit_confirm.get_node("Box"), false)
	_layout_result()


func _set_tv_rect(control: Control, rect: Rect2, factor: float) -> void:
	control.position = rect.position * factor
	control.size = rect.size * factor


func _layout_panel_box(panel: Control, box: VBoxContainer, fill_screen: bool) -> void:
	if _screen_rect.size.x <= 0: return
	var inset := _px(12)
	var available := _screen_rect.grow(-inset)
	var margin := _px(16)
	box.add_theme_constant_override("separation", ceili(_px(8)))
	var panel_width := available.size.x if fill_screen else minf(available.size.x, maxf(_px(450), available.size.x * 0.7))
	box.size.x = panel_width - margin * 2.0
	var panel_height := available.size.y if fill_screen else minf(available.size.y, box.get_combined_minimum_size().y + margin * 2.0)
	panel.position = available.position + (available.size - Vector2(panel_width, panel_height)) * 0.5
	panel.size = Vector2(panel_width, panel_height)
	box.position = Vector2.ONE * margin
	box.size = panel.size - Vector2.ONE * margin * 2.0


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_route_new_audio_node):
		get_tree().node_added.disconnect(_route_new_audio_node)
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


func _build_pixel_chrome() -> void:
	_repeat_step = _button("重看")
	_repeat_step.name = "RepeatLessonStep"
	_repeat_step.pressed.connect(func() -> void:
		if is_instance_valid(active_task): active_task.restart_current_step(); active_task.grab_focus())
	get_node("SafeMargin/Panel/Layout").add_child(_repeat_step)
	_skip_lesson = _button("跳过")
	_skip_lesson.name = "SkipLesson"
	_skip_lesson.pressed.connect(func() -> void:
		if is_instance_valid(active_task): active_task.skip_tutorial(); active_task.grab_focus())
	get_node("SafeMargin/Panel/Layout").add_child(_skip_lesson)
	_repeat_step.hide(); _skip_lesson.hide()
	_lesson_banner = PanelContainer.new()
	_lesson_banner.name = "TeachingBanner"
	_lesson_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_node("SafeMargin/Panel/Layout").add_child(_lesson_banner)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 20)
	_lesson_banner.add_child(strip)
	_lesson_badge = _label("玩法教学", 24)
	_lesson_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	strip.add_child(_lesson_badge)
	_instruction_label = _label("看一遍", 24)
	_instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_instruction_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_instruction_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	strip.add_child(_instruction_label)
	_play_hints = HBoxContainer.new()
	_play_hints.name = "ControlHints"
	_play_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_node("SafeMargin/Panel/Layout").add_child(_play_hints)
	_prepare_hints = VBoxContainer.new()
	_prepare_hints.name = "PrepareControlHints"
	_prepare_controls.get_parent().add_child(_prepare_hints)
	_prepare_controls.get_parent().move_child(_prepare_hints, _prepare_controls.get_index() + 1)
	_pause_hints = VBoxContainer.new()
	_pause_hints.name = "PauseControlHints"
	%PauseControls.get_parent().add_child(_pause_hints)
	%PauseControls.get_parent().move_child(_pause_hints, %PauseControls.get_index() + 1)
	_lesson_banner.hide()
	_play_hints.hide()
	_prepare_hints.hide()
	_pause_hints.hide()
	for hints_panel: Control in [_play_hints, _prepare_hints, _pause_hints]:
		hints_panel.visibility_changed.connect(_refresh_control_hints)


func _apply_shell_version() -> void:
	# Shell/input correctness must not depend on an art revision or task whitelist.
	_pixel_shell = definition != null
	var television := get_node("SafeMargin/Panel/Television") as TextureRect
	television.texture = load(PIXEL_TV_PATH if _pixel_shell and ResourceLoader.exists(PIXEL_TV_PATH) else "res://InheritanceTasks/Art/Pixel/v1/runtime/tv.png") as Texture2D
	_hint_signature = ""
	_instruction_state.clear()
	_prepare_hints.visible = _pixel_shell
	_pause_hints.visible = _pixel_shell
	_prepare_portrait.visible = not _pixel_shell
	_prepare_settings.hide()
	_start_button.size_flags_stretch_ratio = 2.0 if _pixel_shell else 1.0
	_prepare_controls.visible = not _pixel_shell or definition.task_id == &"huangmei_xi"
	%PauseControls.visible = not _pixel_shell or definition.task_id == &"huangmei_xi"
	for control: Control in [%VolumeKnob, %SettingsKnob, heritage_label, progress_bar, control_label]:
		control.visible = not _pixel_shell
	if _pixel_shell:
		if _pixel_font == null: _pixel_font = HeritageTelevisionStyle.pixel_font()
		if _pixel_aux_font == null: _pixel_aux_font = HeritageTelevisionStyle.pixel_font(true)
		_visual_assistance.text = "音乐视觉提示"
		_visual_assistance.visible = definition.task_id in [&"laohekou_si_xian",&"tujia_saye_erhe",&"jingzhou_hua_gu_xi",&"han_ju",&"ti_qin_xi",&"gu_pen_ge"]
		_reduce_motion.text = "减少装饰动态"
		for backdrop: Panel in _panel_backgrounds.values():
			backdrop.add_theme_stylebox_override("panel", HeritageTelevisionStyle.pixel_box("panel", 0))
		var strip := StyleBoxFlat.new()
		strip.bg_color = HeritageTelevisionStyle.V2_GREEN
		strip.set_content_margin_all(0)
		_lesson_banner.add_theme_stylebox_override("panel", strip)
	else:
		_lesson_banner.hide()
		_play_hints.hide()
		title_label.show()
		_clear_pixel_fonts(self)
		var legacy_controls: Array[Control] = []
		_collect_focus_controls(self, legacy_controls)
		for control: Control in legacy_controls: control.mouse_filter = Control.MOUSE_FILTER_STOP
		_visual_assistance.show()
		_prepare_cover.custom_minimum_size = Vector2.ZERO
		_prepare_cover.custom_maximum_size = Vector2(-1, -1)
		_prepare_cover.size_flags_horizontal = Control.SIZE_FILL
		_prepare_cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_prepare_portrait.custom_minimum_size = Vector2.ZERO
		_prepare_portrait.custom_maximum_size = Vector2(-1, -1)
		_prepare_portrait.size_flags_horizontal = Control.SIZE_FILL
		(_prepare_body.get_node("Artwork") as BoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
		(_prepare_body.get_node("Artwork") as Control).size_flags_stretch_ratio = 0.85
		(_prepare_body.get_node("InstructionsScroll") as Control).size_flags_stretch_ratio = 1.4
		for backdrop: Panel in _panel_backgrounds.values():
			backdrop.add_theme_stylebox_override("panel", HeritageTelevisionStyle.panel())
		_style_controls(self)
	_layout_television.call_deferred()


func _style_pixel_text(node: Node) -> void:
	if node == task_container or node is GameSettingsPanel: return
	if node.get_script() == INPUT_GLYPH:
		var glyph_scale := float(maxi(2,_pixel_integer_scale)) / 2.0
		node.set("font_size",ceili(_px(20 * glyph_scale)))
		(node as Control).custom_minimum_size = Vector2(_px(64 * glyph_scale),_px(38 * glyph_scale))
	if node is Label or node is Button:
		var control := node as Control
		var auxiliary := bool(control.get_meta(&"pixel_auxiliary", false))
		var physical_size := float((10 if auxiliary else 12) * maxi(_pixel_integer_scale, 2))
		if control in [result_title, %PauseTitle]: physical_size = 18.0 * maxi(_pixel_integer_scale, 2)
		control.add_theme_font_override("font", _pixel_aux_font if auxiliary else _pixel_font)
		control.add_theme_font_size_override("font_size", ceili(_px(physical_size)))
		control.add_theme_constant_override("outline_size", 0)
		control.add_theme_color_override("font_color", HeritageTelevisionStyle.V2_INK)
		control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if control in [title_label, _lesson_badge, _instruction_label] or bool(control.get_meta(&"pixel_light", false)):
			control.add_theme_color_override("font_color", HeritageTelevisionStyle.V2_CREAM)
	if node is Button:
		var button := node as Button
		button.custom_minimum_size.y = _px(maxf(48.0, 24.0 * _pixel_integer_scale))
		HeritageTelevisionStyle.pixel_button(button, _px(8), float(_pixel_integer_scale) / _physical_scale())
	for child: Node in node.get_children(): _style_pixel_text(child)


func _layout_pixel_television() -> void:
	_last_screen_scale = _physical_scale()
	var physical_space := size * _last_screen_scale - Vector2(12, 12)
	_pixel_integer_scale = maxi(1, floori(minf(physical_space.x / PIXEL_TV_SIZE.x, physical_space.y / PIXEL_TV_SIZE.y)))
	var factor := float(_pixel_integer_scale) / _last_screen_scale
	var dimensions := PIXEL_TV_SIZE * factor
	var panel := get_node("SafeMargin/Panel") as Control
	# Snap the outer origin in actual screen pixels as well as the asset scale.
	panel.position = ((size - dimensions) * 0.5 * _last_screen_scale).round() / _last_screen_scale
	panel.size = dimensions
	_screen_rect = Rect2(panel.position + PIXEL_TV_SCREEN.position * factor, PIXEL_TV_SCREEN.size * factor)
	task_container.position = PIXEL_TV_SCREEN.position * factor
	task_container.size = PIXEL_TV_SCREEN.size * factor
	if _broadcast==null:
		_broadcast = load("res://InheritanceTasks/UI/heritage_broadcast_overlay.gd").new()
		panel.add_child(_broadcast)
		_broadcast.z_index = 5
	_broadcast.position = task_container.position
	_broadcast.size = task_container.size
	_set_tv_rect(get_node("SafeMargin/Panel/Layout/Header"), Rect2(16, 0, 492, 24), factor)
	_set_tv_rect(get_node("SafeMargin/Panel/Layout/Footer"), Rect2(16, 325, 492, 21), factor)
	_set_tv_rect(time_label, Rect2(518, 35, 52, 32), factor)
	_set_tv_rect(pause_button, Rect2(520, 206, 48, 26), factor)
	_set_tv_rect(%SettingsButton, Rect2(520, 242, 48, 26), factor)
	_set_tv_rect(abort_button, Rect2(520, 278, 48, 26), factor)
	_set_tv_rect(_repeat_step, Rect2(520, 118, 48, 26), factor)
	_set_tv_rect(_skip_lesson, Rect2(520, 154, 48, 26), factor)
	_set_tv_rect(_lesson_banner, Rect2(14, 3, 496, 18), factor)
	_set_tv_rect(_play_hints, Rect2(16, 325, 492, 22), factor)
	_style_text(self)
	for backdrop: Panel in _panel_backgrounds.values():
		backdrop.add_theme_stylebox_override("panel", HeritageTelevisionStyle.pixel_box("panel", 0, factor))
	_prepare_body.add_theme_constant_override("separation", int(_px(24)))
	_prepare_portrait.custom_minimum_size.y = _px(96 * _pixel_integer_scale / 2)
	var artwork := _prepare_body.get_node("Artwork") as VBoxContainer
	artwork.alignment = BoxContainer.ALIGNMENT_CENTER
	artwork.size_flags_stretch_ratio = 1.3
	(_prepare_body.get_node("InstructionsScroll") as Control).size_flags_stretch_ratio = 1.0
	var preview_scale := maxi(1, _pixel_integer_scale / 2)
	var preview_size := Vector2(500, 300) * preview_scale / _physical_scale()
	_prepare_cover.custom_minimum_size = preview_size
	_prepare_cover.custom_maximum_size = preview_size
	_prepare_cover.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prepare_cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prepare_cover.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var portrait_size := Vector2(96, 128) * preview_scale / _physical_scale()
	_prepare_portrait.custom_minimum_size = portrait_size
	_prepare_portrait.custom_maximum_size = portrait_size
	_prepare_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prepare_identity.set_meta(&"pixel_auxiliary", true)
	_prepare_tutorial.set_meta(&"pixel_auxiliary", true)
	_volume_slider.custom_minimum_size.y = _px(48)
	_volume_slider.modulate = Color.WHITE
	HeritageTelevisionStyle.pixel_slider(_volume_slider, factor)
	for toggle: CheckButton in [_visual_assistance, _reduce_motion]:
		for state: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			var icon := HeritageTelevisionStyle.pixel_icon("checkbox_off" if state.begins_with("unchecked") else "checkbox_on", factor)
			if icon != null: toggle.add_theme_icon_override(state, icon)
	for row: BoxContainer in [_prepare_hints, _pause_hints, _play_hints]:
		row.add_theme_constant_override("separation", int(_px(12)))
	_layout_panel_box(prepare_panel, _prepare_box, true)
	_layout_panel_box(settings_panel, _settings_box, false)
	_layout_panel_box(_bindings_panel, _bindings_box, true)
	var binding_scroll := _bindings_box.get_node("BindingsScroll") as ScrollContainer
	binding_scroll.custom_minimum_size.y = _px(96 * _pixel_integer_scale)
	binding_scroll.custom_maximum_size.y = binding_scroll.custom_minimum_size.y
	_layout_panel_box(pause_panel, pause_panel.get_node("Box"), false)
	_layout_panel_box(exit_confirm, exit_confirm.get_node("Box"), false)
	_layout_result()
	_sync_pixel_focus()


func _on_input_device_changed(_device: StringName) -> void:
	_refresh_control_hints()


func _refresh_control_hints() -> void:
	if _hints_refresh_pending: return
	_hints_refresh_pending = true
	_apply_control_hints.call_deferred()

func _apply_control_hints() -> void:
	_hints_refresh_pending = false
	if not _pixel_shell or not is_instance_valid(active_task) or not active_task.has_method("get_control_hints"): return
	var hints: Array = active_task.call("get_control_hints")
	var signature := ""
	for hint: Dictionary in hints:
		signature += str(hint.get("id", "")) + str(hint.get("glyphs", [])) + str(hint.get("label", ""))
	for container: BoxContainer in [_prepare_hints, _pause_hints, _play_hints]:
		# A hidden page must not reshape text, resize containers or animate keys
		# during gameplay. visibility_changed refreshes it before it is drawn.
		if not container.is_visible_in_tree(): continue
		var changed := signature != String(container.get_meta(&"hint_signature", "")) or _hint_signature.is_empty()
		var active_ids: Array[String] = []
		for hint: Dictionary in hints: active_ids.append(String(hint.get("id", "Action")))
		if changed:
			for existing: Node in container.get_children():
				(existing as Control).visible = String(existing.name) in active_ids
		for hint: Dictionary in hints:
			var id := String(hint.get("id", "Action"))
			var row := container.get_node_or_null(NodePath(id)) as HBoxContainer
			if row == null:
				row = _make_hint(hint, container == _play_hints)
				container.add_child(row)
				hint_rows_created += 1
				_style_pixel_text(row)
			if changed: row.show()
			var cap := row.get_child(0) as Control
			var glyphs: Array = hint.get("glyphs", [])
			var glyph := String(glyphs[0]) if not glyphs.is_empty() else "?"
			if changed:
				cap.set("glyph",glyph)
				cap.set("caption",_glyph_text(glyph))
				cap.set_meta(&"glyph",glyph)
				cap.tooltip_text = _glyph_text(glyph)
				cap.accessibility_name = cap.tooltip_text
				cap.queue_redraw()
				(row.get_child(1) as Label).text = _hint_description(hint,container == _play_hints)
			cap.call("set_pressed",bool(hint.get("held",false)))
		container.set_meta(&"hint_signature",signature)
	_hint_signature = signature

func _hint_description(hint: Dictionary, compact: bool) -> String:
	if compact and String(hint.get("id", "")) == "heat": return "添火 / 松开收火"
	return String(hint.get("label", ""))


func _make_hint(hint: Dictionary, compact: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = String(hint.get("id", "Action"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(_px(8)))
	var glyphs: Array = hint.get("glyphs", [])
	# Show the currently preferred binding in the small instruction area.
	# Alternatives remain fully available in settings without repeating Enter.
	glyphs = [glyphs[0]] if not glyphs.is_empty() else ["?"]
	for glyph: String in glyphs:
		var cap := INPUT_GLYPH.new()
		cap.glyph = glyph
		cap.caption = _glyph_text(glyph)
		cap.font = _pixel_font
		cap.font_size = ceili(_px(20))
		cap.set_meta(&"glyph", glyph)
		# Reserve the widest device label; swapping A/Space/mouse/pad never
		# changes the row's minimum width or the television layout.
		cap.custom_minimum_size = Vector2(_px(64), _px(38))
		cap.tooltip_text = _glyph_text(glyph)
		cap.accessibility_name = _glyph_text(glyph)
		row.add_child(cap)
	var description_text := _hint_description(hint,compact)
	var description := _label(description_text, 24)
	description.autowrap_mode = TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if compact: description.set_meta(&"pixel_light", true)
	row.add_child(description)
	return row


func _keycap_style(held: bool) -> StyleBoxFlat:
	var cap := StyleBoxFlat.new()
	cap.bg_color = HeritageTelevisionStyle.V2_ACCENT if held else HeritageTelevisionStyle.V2_CREAM
	cap.anti_aliasing = false
	cap.border_color = Color("624039")
	cap.set_border_width_all(maxi(1, int(_px(2))))
	cap.border_width_bottom = maxi(1, int(_px(2 if held else 5)))
	cap.content_margin_left = _px(5)
	cap.content_margin_right = _px(5)
	return cap


func _glyph_text(glyph: String) -> String:
	var names := {"key_space": "空格", "key_enter":"Enter", "key_a": "A", "key_d": "D", "key_w": "W", "key_s": "S", "key_left": "←", "key_right": "→", "mouse_left": "左键", "mouse_right": "右键", "mouse_middle":"中键", "mouse_wheel_up":"滚轮↑", "mouse_wheel_down":"滚轮↓", "pad_south": "下键", "pad_north":"上键", "pad_east":"右键", "pad_west":"左键", "pad_dpad_left": "←", "pad_dpad_right": "→", "pad_dpad_up":"↑", "pad_dpad_down":"↓", "pad_lb":"LB", "pad_rb":"RB", "pad_lt":"LT", "pad_rt":"RT", "pad_stick_left":"摇杆←", "pad_stick_right":"摇杆→", "pad_stick_up":"摇杆↑", "pad_stick_down":"摇杆↓"}
	names["key_up"] = "↑"
	names["key_down"] = "↓"
	var style := HeritageMinigamePreferences.gamepad_glyph_style()
	if style == "letters": names.merge({"pad_south":"A","pad_east":"B","pad_west":"X","pad_north":"Y"},true)
	elif style == "symbols": names.merge({"pad_south":"×","pad_east":"○","pad_west":"□","pad_north":"△","pad_lb":"L1","pad_rb":"R1","pad_lt":"L2","pad_rt":"R2"},true)
	return String(names.get(glyph, glyph.trim_prefix("key_").to_upper()))


func _refresh_instruction_state() -> void:
	var show_hints := _challenge_started and not _terminal_emitted and not prepare_panel.visible and not result_panel.visible and not pause_panel.visible and not settings_panel.visible and not exit_confirm.visible and not _bindings_panel.visible
	_play_hints.visible = show_hints
	_repeat_step.visible = show_hints and is_instance_valid(active_task) and active_task.is_tutorial_active()
	_skip_lesson.visible = _repeat_step.visible
	if is_instance_valid(_broadcast): _broadcast.visible = show_hints
	if not show_hints or not is_instance_valid(active_task) or not active_task.has_method("get_instruction_state"):
		_lesson_banner.hide()
		title_label.show()
		_instruction_state.clear()
		return
	var state: Dictionary = active_task.call("get_instruction_state")
	if state == _instruction_state: return
	_instruction_state = state.duplicate()
	if is_instance_valid(_broadcast): _broadcast.call("update_instruction",state)
	var phase := String(state.get("phase", "live"))
	var teaching := bool(state.get("teaching", false))
	_lesson_banner.hide()
	title_label.show()
	time_label.visible = not teaching and phase=="live"
	_lesson_badge.text = ("玩法教学 · 示范" if phase == "demo" else "玩法教学 · 练手") if teaching else "准备继续" if phase == "resume" else "准备开始"
	match phase:
		"demo": _instruction_label.text = String(state.get("text", "看一遍"))
		"practice":
			var short_text := String(state.get("text", ""))
			_instruction_label.text = short_text
		"countdown", "resume": _instruction_label.text = "先松开按键" if "松开" in String(state.get("text", "")) else str(maxi(1, int(state.get("countdown", 3))))
		_: _instruction_label.text = String(state.get("text", ""))
	_style_pixel_text(_lesson_banner)


func _sync_pixel_focus() -> void:
	if not _pixel_shell: return
	var top: Control = null
	for candidate: Control in [prepare_panel, pause_panel, settings_panel, exit_confirm, result_panel, _bindings_panel]:
		if candidate.visible: top = candidate
	var buttons: Array[Control] = []
	_collect_focus_controls(self, buttons)
	var active: Array[Control] = []
	for control: Control in buttons:
		var allowed := top == null or top.is_ancestor_of(control) or (top == prepare_panel and control == %SettingsButton)
		control.focus_mode = Control.FOCUS_ALL if allowed else Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_STOP if allowed else Control.MOUSE_FILTER_IGNORE
		if allowed and control.is_visible_in_tree() and not (control is BaseButton and control.disabled): active.append(control)
	if top == null or active.is_empty(): return
	for index: int in active.size():
		var control := active[index]
		var before := active[posmod(index - 1, active.size())].get_path()
		var after := active[(index + 1) % active.size()].get_path()
		control.focus_previous = before
		control.focus_next = after
		control.focus_neighbor_top = before
		control.focus_neighbor_bottom = after
		if not control is Range:
			control.focus_neighbor_left = before
			control.focus_neighbor_right = after


func _collect_focus_controls(node: Node, controls: Array[Control]) -> void:
	if node == task_container or node is GameSettingsPanel: return
	if node is BaseButton or node is Slider: controls.append(node as Control)
	for child: Node in node.get_children(): _collect_focus_controls(child, controls)


func _clear_pixel_fonts(node: Node) -> void:
	if node == task_container or node is GameSettingsPanel: return
	if node is Control:
		(node as Control).remove_theme_font_override("font")
	for child: Node in node.get_children(): _clear_pixel_fonts(child)


func _build_bindings() -> void:
	_bindings_panel = Control.new()
	_bindings_panel.name = "BindingsPanel"
	_bindings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bindings_panel)
	_bindings_box = VBoxContainer.new()
	_bindings_box.name = "Box"
	_bindings_panel.add_child(_bindings_box)
	var title := _label("按键与手柄",36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bindings_box.add_child(title)
	_bindings_family = OptionButton.new()
	_bindings_family.name = "BindingDevice"
	for label: String in ["键盘","手柄","鼠标"]: _bindings_family.add_item(label)
	_bindings_family.item_selected.connect(func(_index: int) -> void:
		_capture_action = &""; _binding_conflict.hide(); _render_bindings())
	_bindings_box.add_child(_bindings_family)
	var scroll := ScrollContainer.new()
	scroll.name = "BindingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_FILL
	scroll.follow_focus = true
	_bindings_box.add_child(scroll)
	_bindings_rows = VBoxContainer.new()
	_bindings_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bindings_rows)
	_bindings_status = _label("点一个操作，再按新按键；Esc取消。",24)
	_bindings_status.set_meta(&"pixel_auxiliary",true)
	_bindings_box.add_child(_bindings_status)
	_binding_conflict = HBoxContainer.new()
	var swap := _button("交换绑定")
	swap.pressed.connect(func() -> void:
		var result := active_task.get_input_profile().rebind(_pending_action,_selected_binding_family(),_pending_binding,true)
		_bindings_status.text = "已交换" if bool(result.get("ok",false)) else "保存失败，请重试"
		_binding_conflict.hide(); _render_bindings(); _refresh_control_hints())
	_binding_conflict.add_child(swap)
	var cancel_binding := _button("取消")
	cancel_binding.pressed.connect(func() -> void: _binding_conflict.hide(); _bindings_status.text = "未修改绑定")
	_binding_conflict.add_child(cancel_binding)
	_bindings_box.add_child(_binding_conflict)
	_binding_conflict.hide()
	var glyph_row := HBoxContainer.new()
	var glyph_label := _label("手柄图标",24)
	glyph_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_row.add_child(glyph_label)
	var glyph_style := OptionButton.new()
	glyph_style.name = "GamepadGlyphStyle"
	for label: String in ["位置","ABXY","符号"]: glyph_style.add_item(label)
	glyph_style.select(["position","letters","symbols"].find(HeritageMinigamePreferences.gamepad_glyph_style()))
	glyph_style.item_selected.connect(func(index: int) -> void:
		HeritageMinigamePreferences.save_gamepad_glyph_style(["position","letters","symbols"][index])
		_hint_signature = ""; _refresh_control_hints(); _render_bindings())
	glyph_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glyph_row.add_child(glyph_style)
	_bindings_box.add_child(glyph_row)
	var footer := HBoxContainer.new()
	var reset := _button("恢复默认")
	reset.pressed.connect(func() -> void:
		var saved := active_task.get_input_profile().reset_bindings()
		_capture_action = &""; _binding_conflict.hide()
		_bindings_status.text = "已恢复本关默认操作" if saved else "未能保存，请重试"
		_render_bindings(); _refresh_control_hints())
	footer.add_child(reset)
	_bindings_return = _button("返回")
	_bindings_return.pressed.connect(_hide_bindings)
	footer.add_child(_bindings_return)
	_bindings_box.add_child(footer)
	_bindings_panel.hide()


func _selected_binding_family() -> String:
	return ["keyboard","gamepad","mouse"][_bindings_family.selected]


func _show_bindings() -> void:
	if not is_instance_valid(active_task): return
	_binding_focus_before = get_viewport().gui_get_focus_owner()
	settings_panel.hide()
	_bindings_panel.show()
	_set_suspension(&"bindings",true)
	_capture_action = &""; _binding_conflict.hide()
	_bindings_status.text = "点一个操作，再按新按键；Esc取消。"
	_render_bindings()
	_layout_television()
	_sync_pixel_focus()
	_bindings_family.grab_focus()


func _hide_bindings() -> void:
	_capture_action = &""; _pending_binding.clear(); _binding_conflict.hide()
	_bindings_panel.hide()
	settings_panel.show()
	_set_suspension(&"bindings",false)
	_sync_pixel_focus()
	if is_instance_valid(_binding_focus_before): _binding_focus_before.grab_focus()
	else: _settings_return.grab_focus()


func _render_bindings() -> void:
	if not is_instance_valid(active_task): return
	for child: Node in _bindings_rows.get_children(): child.free()
	var profile := active_task.get_input_profile()
	var family := _selected_binding_family()
	var spatial_mouse := family == "mouse" and profile.kind in [&"platform",&"spotlight",&"puzzle",&"trace",&"cut",&"escort",&"boat"]
	for entry: Dictionary in profile.get_action_definitions():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",int(_px(12)))
		var label := _label(String(entry.label),24)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var names: Array[String] = []
		for binding: Dictionary in profile.bindings_for(entry.id,family):
			var binding_name := _glyph_text(profile.binding_glyph(binding))
			if not binding_name in names: names.append(binding_name)
		var change := _button(" / ".join(names) if not names.is_empty() else "点选位置")
		change.name = "Rebind_%s" % entry.id
		change.disabled = spatial_mouse
		change.custom_minimum_size.x = _px(120)
		change.pressed.connect(func() -> void:
			_capture_action = StringName(entry.id)
			_binding_conflict.hide()
			_bindings_status.text = "请按新的%s操作键 · Esc取消" % String(entry.label))
		row.add_child(change)
		_bindings_rows.add_child(row)
	if spatial_mouse: _bindings_status.text = "画面位置对应点击区域；键盘和手柄可改键。"
	_style_pixel_text(_bindings_box)
	_sync_pixel_focus()


func _try_binding(binding: Dictionary) -> void:
	var action := _capture_action
	_capture_action = &""
	var result := active_task.get_input_profile().rebind(action,_selected_binding_family(),binding)
	if bool(result.get("ok",false)):
		_bindings_status.text = "已保存"
		_render_bindings(); _refresh_control_hints()
	elif result.get("reason") == "conflict":
		_pending_binding = binding.duplicate(true); _pending_action = action
		_bindings_status.text = "此按键已有操作，是否交换？"
		_binding_conflict.show()
		_style_pixel_text(_binding_conflict); _sync_pixel_focus()
		(_binding_conflict.get_child(1) as Button).grab_focus()
	else:
		_bindings_status.text = "Esc / Start留作暂停，请换一个键。" if result.get("reason") == "reserved" else "未能保存，请重试。"


func _visible_underlay() -> Control:
	for panel: Control in [settings_panel, pause_panel, prepare_panel, result_panel]:
		if panel.visible: return panel
	return null


func _on_shared_setting_changed(key: String, value: Variant) -> void:
	match key:
		"minigame_volume":
			_volume_slider.set_value_no_signal(float(value))
			_volume_value.text = "音量  %d%%" % int(value)
		"reduce_motion":
			_reduce_motion.set_pressed_no_signal(bool(value))
			_on_reduced_motion_changed(bool(value))
		"music_visual_assistance":
			_visual_assistance.set_pressed_no_signal(bool(value))
			_on_visual_assistance_changed(bool(value))
		"gamepad_glyph_style":
			_hint_signature = ""
			var selector := find_child("GamepadGlyphStyle", true, false) as OptionButton
			if selector != null: selector.select(["position","letters","symbols"].find(value))
			_on_input_device_changed(&"gamepad")
