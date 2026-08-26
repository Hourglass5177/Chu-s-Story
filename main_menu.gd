class_name MainMenu
extends Control

## 对局前端壳层。子页面只处理展示与意图，只有这里可以提交会话或切换主场景。

signal mode_requested(mode: SessionSetup.GameMode)
signal local_setup_confirmed(setup: SessionSetup)
signal ui_scale_changed(value: float)
signal reduce_motion_changed(enabled: bool)
signal ui_sound_enabled_changed(enabled: bool)
signal ui_feedback_requested(cue: StringName)

const MAIN_MAP_SCENE := "res://main_map.tscn"
const PAGE_SCENE: PackedScene = preload("res://UI/Frontend/frontend_page.tscn")
const STEPPER_SCENE: PackedScene = preload("res://UI/Frontend/number_stepper.tscn")
const CARD_SCENE: PackedScene = preload("res://UI/Frontend/stateful_card.tscn")
const PLAYER_SETUP_SCENE: PackedScene = preload("res://UI/Frontend/player_setup_page.tscn")
const ROSTER_SCENE: PackedScene = preload("res://UI/Frontend/roster_page.tscn")
const GAME_GUIDE_SCENE: PackedScene = preload("res://UI/GameGuide/digital_game_guide.tscn")
const FRONTEND_THEME: Theme = preload("res://UI/Frontend/frontend_theme.tres")
const SESSION_LAUNCHER_SCRIPT: Script = preload("res://UI/Frontend/frontend_session_launcher.gd")
const TITLE_TEXTURE: Texture2D = preload("res://arts/素材合集/主界面（启动+首页）/游戏标题.png")

const SCREEN_HOME := &"home"
const SCREEN_MODE := &"mode"
const SCREEN_LOCAL_COUNT := &"local_count"
const SCREEN_PLAYER_SETUP := &"player_setup"
const SCREEN_ROSTER := &"roster"
const SCREEN_LOADING := &"loading"
const STABLE_SCREENS: Array[StringName] = [
	SCREEN_HOME,
	SCREEN_MODE,
	SCREEN_LOCAL_COUNT,
	SCREEN_PLAYER_SETUP,
	SCREEN_ROSTER,
	SCREEN_LOADING,
]

var _draft := SessionSetup.new()
var _preferences := FrontendUIPreferences.new()
var _pages: Dictionary[StringName, FrontendScreen] = {}
var _current_screen: StringName = &""
var _shell: Control

var _human_stepper: FrontendNumberStepper
var _bot_stepper: FrontendNumberStepper
var _target_score_stepper: FrontendNumberStepper
var _total_label: Label
var _count_syncing := false

var _player_setup_page: FrontendPlayerSetupPage
var _roster_page: FrontendRosterPage
var _editing_slot := 0
var _return_to_roster_after_edit := false
var _touched_players: Dictionary[int, bool] = {}

var _modal_layer: Control
var _modal_panel: PanelContainer
var _modal_body: VBoxContainer
var _modal_callback := Callable()
var _modal_cancel_callback := Callable()
var _modal_return_focus: WeakRef

var _toast_layer: Control
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

var _start_locked := false
var _loading_label: Label
var _loading_timer: Timer
var _loading_dot_count := 0
var _session_launcher: FrontendSessionLauncher = SESSION_LAUNCHER_SCRIPT.new() as FrontendSessionLauncher
var _game_guide: DigitalGameGuide
var _home_rules_button: Button


func _ready() -> void:
	# SceneTree 的暂停状态会跨场景保留。主菜单不属于游戏内暂停域，
	# 无论它由终局、调试入口还是异常中断进入，都必须先恢复前端输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	_build_frontend()
	_connect_preferences()
	show_screen(SCREEN_HOME, false)


func _unhandled_input(event: InputEvent) -> void:
	if _modal_layer != null and _modal_layer.visible and event.is_action_pressed("ui_cancel"):
		_close_modal(false)
		get_viewport().set_input_as_handled()


## 稳定的前端测试/自动化接口。
func get_current_screen() -> StringName:
	return _current_screen


## 返回深复制，外部工具不能污染前端草稿。
func get_draft_snapshot() -> SessionSetup:
	return _draft.duplicate_snapshot()


func set_local_player_counts(human_count: int, bot_count: int) -> bool:
	if _draft.resize_slots(human_count, bot_count) != OK:
		return false
	_draft.mode = SessionSetup.GameMode.LOCAL
	_sync_count_view()
	return true


func set_target_score(target_score: int) -> bool:
	if not SessionSetup.TARGET_SCORE_OPTIONS.has(target_score):
		return false
	_draft.target_score = target_score
	_sync_count_view()
	return true


func show_screen(screen_name: StringName, animated := true) -> bool:
	if not STABLE_SCREENS.has(screen_name) or not _pages.has(screen_name):
		return false
	if _start_locked and screen_name != SCREEN_LOADING:
		return false
	if _current_screen == screen_name:
		_sync_page(screen_name)
		return true
	var previous := _pages.get(_current_screen) as FrontendScreen
	if previous != null:
		previous.exit_screen(false)
	_current_screen = screen_name
	_sync_page(screen_name)
	var page := _pages[screen_name] as FrontendScreen
	page.enter_screen(animated)
	return true


func request_mode(mode: int) -> bool:
	if not SessionSetup.GameMode.values().has(mode):
		return false
	mode_requested.emit(mode as SessionSetup.GameMode)
	_preferences.request_feedback(&"confirm")
	match mode:
		SessionSetup.GameMode.LOCAL:
			_draft.mode = SessionSetup.GameMode.LOCAL
			show_screen(SCREEN_LOCAL_COUNT)
		SessionSetup.GameMode.NETWORK, SessionSetup.GameMode.TUTORIAL:
			_show_toast("暂未开放")
	return true


## 仅受理一次合法提交。真正的资源初始化在加载页渲染一帧后开始。
func request_start_once() -> bool:
	if _start_locked:
		return false
	var errors := _draft.validate()
	if not errors.is_empty():
		_show_toast(errors[0])
		_preferences.request_feedback(&"invalid")
		return false
	_start_locked = true
	var snapshot := _draft.duplicate_snapshot()
	snapshot.normalize_display_names()
	show_screen(SCREEN_LOADING)
	_begin_local_session(snapshot)
	return true


func set_ui_scale(value: float) -> void:
	_preferences.ui_scale = value


func set_reduce_motion(enabled: bool) -> void:
	_preferences.reduce_motion = enabled


func set_ui_sound_enabled(enabled: bool) -> void:
	_preferences.ui_sound_enabled = enabled


## Narrow dependency-injection seam used by automated front-end validation.
## Production always keeps the default FrontendSessionLauncher.
func set_session_launcher(launcher: FrontendSessionLauncher) -> void:
	if not _start_locked and launcher != null:
		_session_launcher = launcher


func _build_frontend() -> void:
	_capture_and_hide_legacy_nodes()
	_shell = Control.new()
	_shell.name = "FrontendShell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.z_index = 100
	_shell.theme = FRONTEND_THEME
	add_child(_shell)
	_build_home_page()
	_build_mode_page()
	_build_count_page()
	_build_player_setup_page()
	_build_roster_page()
	_build_loading_page()
	_build_toast_layer()
	_build_modal_layer()
	_build_game_guide()


func _capture_and_hide_legacy_nodes() -> void:
	# 旧 Demo 节点仅保留制作人员文字；游戏说明已由数字版指南取代。它们不得参与显示、
	# 焦点或鼠标命中。不要依赖一份容易漏项的节点名称列表。
	for child: Node in get_children():
		_disable_legacy_input_tree(child)
		if child.name != &"Background" and child is CanvasItem:
			(child as CanvasItem).visible = false


func _disable_legacy_input_tree(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children():
		_disable_legacy_input_tree(child)


func _build_home_page() -> void:
	var page := _create_page(SCREEN_HOME, "", "", Vector2(1040, 900))
	(page.get_node("%Eyebrow") as Label).visible = false
	(page.get_node("%Title") as Label).visible = false
	var body := page.get_node("%Body") as VBoxContainer
	var title := TextureRect.new()
	title.texture = TITLE_TEXTURE
	title.custom_minimum_size = Vector2(760, 260)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(580, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(buttons)
	var start_button := _new_button("开始游戏", buttons, Vector2(580, 92))
	var rules_button := _new_button("游戏说明", buttons, Vector2(580, 82))
	_home_rules_button = rules_button
	var credits_button := _new_button("制作人员", buttons, Vector2(580, 82))
	var exit_button := _new_button("退出游戏", buttons, Vector2(580, 82))
	start_button.pressed.connect(func() -> void: show_screen(SCREEN_MODE))
	rules_button.pressed.connect(func() -> void: open_game_guide())
	credits_button.pressed.connect(func() -> void:
		_show_text_modal("制作人员", _read_legacy_text("CreditsPanel/Label"), credits_button)
	)
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	_link_vertical_focus([start_button, rules_button, credits_button, exit_button])
	page.initial_focus_path = page.get_path_to(start_button)


func _build_mode_page() -> void:
	var page := _create_page(SCREEN_MODE, "选择模式", "开始游戏", Vector2(1640, 880))
	var body := page.get_node("%Body") as VBoxContainer
	body.add_child(_new_label("想怎么一起玩？", 32, HORIZONTAL_ALIGNMENT_CENTER))
	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 28)
	body.add_child(cards)
	var local_card := _new_card("本地游戏", "1–6 人同屏游玩", null, cards)
	var network_card := _new_card("网络游戏", "暂未开放", null, cards)
	var tutorial_card := _new_card("教学模式", "暂未开放", null, cards)
	local_card.activated.connect(func() -> void: request_mode(SessionSetup.GameMode.LOCAL))
	network_card.activated.connect(func() -> void: request_mode(SessionSetup.GameMode.NETWORK))
	tutorial_card.activated.connect(func() -> void: request_mode(SessionSetup.GameMode.TUTORIAL))
	_link_horizontal_focus([local_card, network_card, tutorial_card])
	var back_button := _new_button("返回", body, Vector2(300, 76))
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.pressed.connect(_request_home_from_mode)
	for card: FrontendStatefulCard in [local_card, network_card, tutorial_card]:
		card.focus_neighbor_bottom = card.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(local_card)
	back_button.focus_neighbor_left = back_button.get_path()
	back_button.focus_neighbor_right = back_button.get_path()
	page.initial_focus_path = page.get_path_to(local_card)


func _build_count_page() -> void:
	var page := _create_page(SCREEN_LOCAL_COUNT, "本地游戏", "选择玩家", Vector2(1260, 940))
	var body := page.get_node("%Body") as VBoxContainer
	body.add_child(_new_label("设置席位", 34, HORIZONTAL_ALIGNMENT_CENTER))
	_human_stepper = STEPPER_SCENE.instantiate() as FrontendNumberStepper
	_human_stepper.caption = "真人玩家"
	_human_stepper.minimum = 1
	_human_stepper.maximum = 6
	body.add_child(_human_stepper)
	_bot_stepper = STEPPER_SCENE.instantiate() as FrontendNumberStepper
	_bot_stepper.caption = "电脑玩家"
	_bot_stepper.minimum = 0
	_bot_stepper.maximum = 5
	body.add_child(_bot_stepper)
	_total_label = _new_label("总人数：1 / 6", 42, HORIZONTAL_ALIGNMENT_CENTER)
	_total_label.add_theme_color_override("font_color", FrontendStyle.GOLD)
	body.add_child(_total_label)
	_target_score_stepper = STEPPER_SCENE.instantiate() as FrontendNumberStepper
	_target_score_stepper.caption = "目标分数"
	_target_score_stepper.minimum = 15
	_target_score_stepper.maximum = 30
	_target_score_stepper.step_size = 5
	_target_score_stepper.current_value = SessionSetup.DEFAULT_TARGET_SCORE
	_target_score_stepper.value_suffix = " 分"
	body.add_child(_target_score_stepper)
	var note := _new_label("电脑玩家暂由本地操作", 30, HORIZONTAL_ALIGNMENT_CENTER)
	note.add_theme_color_override("font_color", FrontendStyle.BROWN)
	body.add_child(note)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(actions)
	var back_button := _new_button("返回", actions, Vector2(260, 78))
	var next_button := _new_button("下一步", actions, Vector2(320, 78))
	_human_stepper.value_changed.connect(func(value: int) -> void:
		if not _count_syncing:
			_request_count_change(value, _bot_stepper.get_value())
	)
	_bot_stepper.value_changed.connect(func(value: int) -> void:
		if not _count_syncing:
			_request_count_change(_human_stepper.get_value(), value)
	)
	_target_score_stepper.value_changed.connect(func(value: int) -> void:
		if not _count_syncing:
			set_target_score(value)
	)
	_human_stepper.boundary_pressed.connect(func(_direction: int) -> void: _show_toast("已到人数上限"))
	_bot_stepper.boundary_pressed.connect(func(_direction: int) -> void: _show_toast("已到人数上限"))
	back_button.pressed.connect(func() -> void: show_screen(SCREEN_MODE))
	next_button.pressed.connect(func() -> void: _open_player_setup(0, false))
	var human_decrease := _human_stepper.get_node("%Decrease") as Button
	var human_increase := _human_stepper.get_node("%Increase") as Button
	var bot_decrease := _bot_stepper.get_node("%Decrease") as Button
	var bot_increase := _bot_stepper.get_node("%Increase") as Button
	var score_decrease := _target_score_stepper.get_node("%Decrease") as Button
	var score_increase := _target_score_stepper.get_node("%Increase") as Button
	human_decrease.focus_neighbor_bottom = human_decrease.get_path_to(bot_decrease)
	human_increase.focus_neighbor_bottom = human_increase.get_path_to(bot_increase)
	bot_decrease.focus_neighbor_top = bot_decrease.get_path_to(human_decrease)
	bot_increase.focus_neighbor_top = bot_increase.get_path_to(human_increase)
	bot_decrease.focus_neighbor_bottom = bot_decrease.get_path_to(score_decrease)
	bot_increase.focus_neighbor_bottom = bot_increase.get_path_to(score_increase)
	score_decrease.focus_neighbor_top = score_decrease.get_path_to(bot_decrease)
	score_increase.focus_neighbor_top = score_increase.get_path_to(bot_increase)
	score_decrease.focus_neighbor_bottom = score_decrease.get_path_to(back_button)
	score_increase.focus_neighbor_bottom = score_increase.get_path_to(next_button)
	back_button.focus_neighbor_top = back_button.get_path_to(score_decrease)
	back_button.focus_neighbor_right = back_button.get_path_to(next_button)
	next_button.focus_neighbor_top = next_button.get_path_to(score_increase)
	next_button.focus_neighbor_left = next_button.get_path_to(back_button)
	page.initial_focus_path = page.get_path_to(human_increase)


func _build_player_setup_page() -> void:
	_player_setup_page = PLAYER_SETUP_SCENE.instantiate() as FrontendPlayerSetupPage
	_player_setup_page.name = "PlayerSetupPage"
	_player_setup_page.visible = false
	_player_setup_page.set_ui_preferences(_preferences)
	_shell.add_child(_player_setup_page)
	_register_page(SCREEN_PLAYER_SETUP, _player_setup_page)
	_player_setup_page.player_confirmed.connect(_on_player_confirmed)
	_player_setup_page.previous_requested.connect(_on_player_setup_previous)
	_player_setup_page.invalid_action.connect(_show_toast)
	_player_setup_page.player_draft_changed.connect(_mark_slot_touched)


func _build_roster_page() -> void:
	_roster_page = ROSTER_SCENE.instantiate() as FrontendRosterPage
	_roster_page.name = "RosterPage"
	_roster_page.visible = false
	_roster_page.set_ui_preferences(_preferences)
	_shell.add_child(_roster_page)
	_register_page(SCREEN_ROSTER, _roster_page)
	_roster_page.edit_player_requested.connect(func(slot_index: int) -> void: _open_player_setup(slot_index, true))
	_roster_page.start_requested.connect(func() -> void: request_start_once())
	_roster_page.previous_requested.connect(func() -> void:
		_open_player_setup(maxi(_draft.players.size() - 1, 0), false)
	)


func _build_loading_page() -> void:
	var page := _create_page(SCREEN_LOADING, "准备中", "本地游戏", Vector2(900, 620))
	page.handle_cancel_action = false
	var body := page.get_node("%Body") as VBoxContainer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 80
	body.add_child(spacer)
	_loading_label = _new_label("正在准备", 42, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_loading_label)
	var note := _new_label("请稍候", 26, HORIZONTAL_ALIGNMENT_CENTER)
	note.add_theme_color_override("font_color", FrontendStyle.BROWN_MUTED)
	body.add_child(note)
	_loading_timer = Timer.new()
	_loading_timer.wait_time = 0.28
	_loading_timer.timeout.connect(_advance_loading_indicator)
	page.add_child(_loading_timer)


func _create_page(screen_name: StringName, title_text: String, eyebrow: String, panel_size: Vector2) -> FrontendScreen:
	var page := PAGE_SCENE.instantiate() as FrontendScreen
	page.name = String(screen_name).to_pascal_case() + "Page"
	page.visible = false
	page.set_ui_preferences(_preferences)
	_shell.add_child(page)
	(page.get_node("%Title") as Label).text = title_text
	(page.get_node("%Eyebrow") as Label).text = eyebrow
	(page.get_node("SafeArea/Center/PagePanel") as PanelContainer).custom_minimum_size = panel_size
	(page.get_node("%PrimaryAction") as Button).visible = false
	var body := page.get_node("%Body") as VBoxContainer
	for child: Node in body.get_children():
		child.queue_free()
	_register_page(screen_name, page)
	return page


func _register_page(screen_name: StringName, page: FrontendScreen) -> void:
	_pages[screen_name] = page
	page.back_requested.connect(func() -> void: _on_page_back(screen_name))


func _sync_page(screen_name: StringName) -> void:
	match screen_name:
		SCREEN_LOCAL_COUNT:
			_sync_count_view()
		SCREEN_PLAYER_SETUP:
			_player_setup_page.bind_setup(_draft, _editing_slot, _return_to_roster_after_edit)
		SCREEN_ROSTER:
			_roster_page.bind_setup(_draft)
		SCREEN_LOADING:
			_loading_dot_count = 0
			_advance_loading_indicator()
			_loading_timer.start()
		_:
			if _loading_timer != null:
				_loading_timer.stop()


func _on_page_back(screen_name: StringName) -> void:
	if _modal_layer != null and _modal_layer.visible:
		_close_modal(false)
		return
	match screen_name:
		SCREEN_HOME:
			pass
		SCREEN_MODE:
			_request_home_from_mode()
		SCREEN_LOCAL_COUNT:
			show_screen(SCREEN_MODE)
		SCREEN_PLAYER_SETUP:
			_on_player_setup_previous(_editing_slot)
		SCREEN_ROSTER:
			_open_player_setup(maxi(_draft.players.size() - 1, 0), false)
		SCREEN_LOADING:
			pass


func _request_home_from_mode() -> void:
	if not _draft_has_meaningful_changes():
		show_screen(SCREEN_HOME)
		return
	_show_confirmation(
		"放弃本次配置？",
		"返回首页后将清空当前开局草稿。",
		"放弃",
		func() -> void:
			_draft = SessionSetup.new()
			_touched_players.clear()
			show_screen(SCREEN_HOME)
	)


func _request_count_change(human_count: int, bot_count: int) -> void:
	if human_count < 1 or bot_count < 0 or human_count + bot_count > SessionSetup.MAX_PLAYERS:
		_sync_count_view()
		_show_toast("总人数最多 6 人")
		return
	if _would_remove_configured_players(human_count, bot_count):
		_sync_count_view()
		_show_confirmation(
			"减少玩家？",
			"将移除已经配置的末位玩家。",
			"移除",
			func() -> void: set_local_player_counts(human_count, bot_count)
		)
		return
	set_local_player_counts(human_count, bot_count)


func _sync_count_view() -> void:
	if _human_stepper == null or _bot_stepper == null:
		return
	_count_syncing = true
	_human_stepper.set_bounds(1, SessionSetup.MAX_PLAYERS - _draft.bot_count, false)
	_bot_stepper.set_bounds(0, SessionSetup.MAX_PLAYERS - _draft.human_count, false)
	_human_stepper.set_value(_draft.human_count, false)
	_bot_stepper.set_value(_draft.bot_count, false)
	_total_label.text = "总人数：%d / %d" % [_draft.players.size(), SessionSetup.MAX_PLAYERS]
	_target_score_stepper.set_value(_draft.target_score, false)
	_count_syncing = false


func _would_remove_configured_players(next_humans: int, next_bots: int) -> bool:
	var human_seen := 0
	var bot_seen := 0
	for player: PlayerSetup in _draft.players:
		if player.control_kind == PlayerSetup.ControlKind.HUMAN:
			if human_seen >= next_humans and _player_has_meaningful_config(player):
				return true
			human_seen += 1
		else:
			if bot_seen >= next_bots and _player_has_meaningful_config(player):
				return true
			bot_seen += 1
	return false


func _player_has_meaningful_config(player: PlayerSetup) -> bool:
	if player == null:
		return false
	if player.control_kind == PlayerSetup.ControlKind.BOT:
		return _touched_players.has(player.get_instance_id())
	return not player.display_name.strip_edges().is_empty() or player.is_configured()


func _open_player_setup(slot_index: int, return_to_roster: bool) -> void:
	if _draft.players.is_empty():
		_show_toast("请先设置玩家人数")
		show_screen(SCREEN_LOCAL_COUNT)
		return
	_editing_slot = clampi(slot_index, 0, _draft.players.size() - 1)
	_return_to_roster_after_edit = return_to_roster
	show_screen(SCREEN_PLAYER_SETUP)


func _on_player_confirmed(slot_index: int, return_to_roster: bool) -> void:
	_mark_slot_touched(slot_index)
	if return_to_roster or slot_index >= _draft.players.size() - 1:
		if return_to_roster:
			_roster_page.prefer_player_focus(slot_index)
		show_screen(SCREEN_ROSTER)
	else:
		_open_player_setup(slot_index + 1, false)


func _on_player_setup_previous(slot_index: int) -> void:
	if _return_to_roster_after_edit:
		_roster_page.prefer_player_focus(slot_index)
		show_screen(SCREEN_ROSTER)
	elif slot_index > 0:
		_open_player_setup(slot_index - 1, false)
	else:
		show_screen(SCREEN_LOCAL_COUNT)


func _mark_slot_touched(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _draft.players.size():
		return
	var player := _draft.players[slot_index]
	if player != null:
		_touched_players[player.get_instance_id()] = true


func _begin_local_session(snapshot: SessionSetup) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or not _start_locked:
		return
	var loading_page := _pages.get(SCREEN_LOADING) as FrontendScreen
	if loading_page != null and loading_page.screen_state != FrontendScreen.ScreenState.ACTIVE:
		await loading_page.transition_finished
	if not is_inside_tree() or not _start_locked or _current_screen != SCREEN_LOADING:
		return
	await get_tree().process_frame
	var error := _session_launcher.prepare_local_session(snapshot)
	if error != OK:
		_start_locked = false
		show_screen(SCREEN_ROSTER, false)
		_show_toast("无法开始游戏")
		return
	local_setup_confirmed.emit(snapshot.duplicate_snapshot())
	var scene_error := _session_launcher.change_to_game_scene(get_tree(), MAIN_MAP_SCENE)
	if scene_error != OK:
		_start_locked = false
		_session_launcher.rollback_session()
		show_screen(SCREEN_ROSTER, false)
		_show_toast("场景加载失败")


func _advance_loading_indicator() -> void:
	_loading_dot_count = (_loading_dot_count + 1) % 4
	_loading_label.text = "正在准备%s" % ".".repeat(_loading_dot_count)


func _build_modal_layer() -> void:
	_modal_layer = Control.new()
	_modal_layer.name = "ModalLayer"
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.visible = false
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.add_child(_modal_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.12, 0.055, 0.035, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(center)
	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(920, 480)
	center.add_child(_modal_panel)
	_modal_body = VBoxContainer.new()
	_modal_body.add_theme_constant_override("separation", 24)
	_modal_panel.add_child(_modal_body)


func _build_game_guide() -> void:
	_game_guide = GAME_GUIDE_SCENE.instantiate() as DigitalGameGuide
	_game_guide.name = "DigitalGameGuide"
	_game_guide.set_ui_preferences(_preferences)
	_game_guide.set_shortcut_enabled(false)
	_shell.add_child(_game_guide)
	_game_guide.guide_closed.connect(_on_game_guide_closed)


func open_game_guide(context: GuideOpenContext = null) -> bool:
	if _game_guide == null or _modal_layer.visible:
		return false
	var current_page := _pages.get(_current_screen) as FrontendScreen
	if current_page != null:
		current_page.set_interaction_enabled(false)
	var open_context := context
	if open_context == null:
		open_context = GuideOpenContext.new(
			GuideOpenContext.Source.MAIN_MENU,
			&"guide_home",
			&"",
			&"",
			_home_rules_button
		)
	return _game_guide.open_guide(open_context)


func get_game_guide() -> DigitalGameGuide:
	return _game_guide


func _on_game_guide_closed(context: GuideOpenContext) -> void:
	var current_page := _pages.get(_current_screen) as FrontendScreen
	if current_page != null:
		current_page.set_interaction_enabled(true)
	var return_focus := context.get_return_focus() if context != null else null
	if return_focus != null and is_instance_valid(return_focus) and return_focus.is_visible_in_tree() and return_focus.focus_mode != Control.FOCUS_NONE:
		return_focus.grab_focus()


func _show_text_modal(title_text: String, body_text: String, return_focus: Control) -> void:
	_prepare_modal(title_text, return_focus)
	_modal_panel.custom_minimum_size = Vector2(1420, 1060)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_body.add_child(scroll)
	var label := _new_label(body_text, 28, HORIZONTAL_ALIGNMENT_LEFT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	var close_button := _new_button("关闭", _modal_body, Vector2(300, 76))
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(func() -> void: _close_modal(true))
	close_button.grab_focus()


func _show_confirmation(title_text: String, message: String, confirm_text: String, on_confirm: Callable) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	_prepare_modal(title_text, focus_owner)
	_modal_panel.custom_minimum_size = Vector2(900, 460)
	var message_label := _new_label(message, 30, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_body.add_child(message_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_modal_body.add_child(actions)
	var cancel_button := _new_button("取消", actions, Vector2(260, 76))
	var confirm_button := _new_button(confirm_text, actions, Vector2(280, 76))
	_modal_callback = on_confirm
	cancel_button.pressed.connect(func() -> void: _close_modal(false))
	confirm_button.pressed.connect(func() -> void: _close_modal(true))
	_link_horizontal_focus([cancel_button, confirm_button])
	cancel_button.grab_focus()


func _prepare_modal(title_text: String, return_focus: Control) -> void:
	for child: Node in _modal_body.get_children():
		_modal_body.remove_child(child)
		child.queue_free()
	_modal_callback = Callable()
	_modal_cancel_callback = Callable()
	_modal_return_focus = weakref(return_focus) if return_focus != null else null
	var current_page := _pages.get(_current_screen) as FrontendScreen
	if current_page != null:
		current_page.set_interaction_enabled(false)
	_modal_layer.visible = true
	var title := _new_label(title_text, 48, HORIZONTAL_ALIGNMENT_CENTER)
	_modal_body.add_child(title)
	_modal_body.add_child(HSeparator.new())


func _close_modal(confirmed: bool) -> void:
	if _modal_layer == null or not _modal_layer.visible:
		return
	var callback := _modal_callback if confirmed else _modal_cancel_callback
	_modal_callback = Callable()
	_modal_cancel_callback = Callable()
	_modal_layer.visible = false
	var return_control := _modal_return_focus.get_ref() as Control if _modal_return_focus != null else null
	_modal_return_focus = null
	if callback.is_valid():
		callback.call()
	var current_page := _pages.get(_current_screen) as FrontendScreen
	if current_page != null and current_page.screen_state == FrontendScreen.ScreenState.ACTIVE:
		current_page.set_interaction_enabled(true)
	if return_control != null \
		and return_control.is_visible_in_tree() \
		and current_page != null \
		and current_page.screen_state == FrontendScreen.ScreenState.ACTIVE \
		and current_page.is_ancestor_of(return_control):
		return_control.call_deferred("grab_focus")
	elif current_page != null and current_page.screen_state == FrontendScreen.ScreenState.ACTIVE:
		current_page.call_deferred("grab_initial_focus")


func _build_toast_layer() -> void:
	_toast_layer = Control.new()
	_toast_layer.name = "ToastLayer"
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_child(_toast_layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_bottom", 92)
	_toast_layer.add_child(margin)
	var bottom := CenterContainer.new()
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(bottom)
	_toast_panel = PanelContainer.new()
	_toast_panel.custom_minimum_size = Vector2(420, 72)
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_toast_panel)
	_toast_label = _new_label("", 28, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_panel.add_child(_toast_label)
	_set_mouse_filter_recursive(_toast_layer, Control.MOUSE_FILTER_IGNORE)


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child, filter)


func _show_toast(message: String) -> void:
	if message.strip_edges().is_empty() or _toast_panel == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = message
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	_toast_tween = create_tween()
	var fade_time := _preferences.transition_duration(0.16)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, fade_time)
	_toast_tween.tween_interval(1.7)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, fade_time)
	_toast_tween.finished.connect(func() -> void:
		if is_instance_valid(_toast_panel):
			_toast_panel.visible = false
	, CONNECT_ONE_SHOT)


func _connect_preferences() -> void:
	_preferences.ui_scale_changed.connect(func(value: float) -> void:
		ui_scale_changed.emit(value)
	)
	_preferences.reduce_motion_changed.connect(func(enabled: bool) -> void: reduce_motion_changed.emit(enabled))
	_preferences.ui_sound_enabled_changed.connect(func(enabled: bool) -> void: ui_sound_enabled_changed.emit(enabled))
	_preferences.ui_feedback_requested.connect(func(cue: StringName) -> void: ui_feedback_requested.emit(cue))


func _read_legacy_text(node_path: String) -> String:
	var label := get_node_or_null(node_path) as Label
	return label.text if label != null else ""


func _draft_has_meaningful_changes() -> bool:
	if _draft.human_count != 1 or _draft.bot_count != 0 or _draft.target_score != SessionSetup.DEFAULT_TARGET_SCORE:
		return true
	for player: PlayerSetup in _draft.players:
		if _player_has_meaningful_config(player):
			return true
	return false


func _new_button(text_value: String, parent: Container, minimum := Vector2(260, 76)) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_ALL
	parent.add_child(button)
	return button


func _new_label(text_value: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _new_card(title_text: String, subtitle_text: String, artwork: Texture2D, parent: Container) -> FrontendStatefulCard:
	var card := CARD_SCENE.instantiate() as FrontendStatefulCard
	card.title = title_text
	card.subtitle = subtitle_text
	card.artwork = artwork
	card.custom_minimum_size = Vector2(440, 400)
	card.set_ui_preferences(_preferences)
	parent.add_child(card)
	return card


func _link_vertical_focus(controls: Array[Control]) -> void:
	for index: int in controls.size():
		var current := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)


func _link_horizontal_focus(controls: Array[Control]) -> void:
	for index: int in controls.size():
		var current := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_right = current.get_path_to(next)
