extends GutTest

const DETAIL_SCENE := preload("res://HUDs/非遗详情弹窗.tscn")
const THUMBNAIL_SCENE := preload("res://HUDs/非遗牌缩略图.tscn")
const HOST_SCENE := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
const TEST_DISCOVERY_PATH: String = "user://test_heritage_task_ui_flow.cfg"

var _player: PlayerClass
var _other: PlayerClass
var _viewport: SubViewport
var _saved_turn_state: Dictionary
var _saved_players: Array[PlayerClass] = []
var _saved_resource_hud: HUD
var _saved_tree_paused: bool = false
var _saved_timer_running: bool = false
var _saved_timer_time_left: float = 0.0


func before_each() -> void:
	_saved_turn_state = {
		"game_on": TurnManager.GameOn,
		"phase": TurnManager.now_phase,
		"player_index": TurnManager.now_player_index,
		"session_generation": TurnManager.get_session_generation(),
		"turn_epoch": TurnManager.get_turn_epoch(),
	}
	_saved_players.assign(TurnManager.players)
	_saved_resource_hud = ResourceManager.hud
	_saved_tree_paused = get_tree().paused
	_saved_timer_running = not TurnManager.turn_timer.is_stopped()
	_saved_timer_time_left = TurnManager.turn_timer.time_left

	get_tree().paused = false
	TurnManager.turn_timer.stop()
	InteractionCoordinator.reset_session(false)
	TurnManager.invalidate_all_modals(&"heritage_ui_test_setup")
	ResourceManager.hud = null

	_player = PlayerClass.new()
	_player.player_name = "传承界面P1"
	_player.player_index = 0
	_player.current_energy = 6
	_player.alive = true
	_player.onTurn = true
	_other = PlayerClass.new()
	_other.player_name = "传承界面P2"
	_other.player_index = 1
	_other.current_energy = 6
	_other.alive = true
	_other.onTurn = false

	TurnManager._session_generation = int(_saved_turn_state["session_generation"]) + 200
	TurnManager._turn_epoch = int(_saved_turn_state["turn_epoch"]) + 20
	TurnManager.players.assign([_player, _other])
	TurnManager.now_player_index = 0
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	var players: Array[PlayerClass] = [_player, _other]
	HeritageTaskManager.reload_definitions()
	HeritageTaskManager.reset_for_new_game(players)

	var absolute_test_path := ProjectSettings.globalize_path(TEST_DISCOVERY_PATH)
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(absolute_test_path)
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(2560, 1600)
	_viewport.gui_disable_input = false
	add_child_autofree(_viewport)


func after_each() -> void:
	get_tree().paused = false
	HeritageTaskManager.reset_session()
	InteractionCoordinator.reset_session(false)
	TurnManager.invalidate_all_modals(&"heritage_ui_test_cleanup")
	TurnManager.turn_timer.stop()
	ResourceManager.hud = _saved_resource_hud
	TurnManager.players.assign(_saved_players)
	TurnManager.now_player_index = int(_saved_turn_state["player_index"])
	TurnManager.GameOn = bool(_saved_turn_state["game_on"])
	TurnManager.now_phase = int(_saved_turn_state["phase"])
	TurnManager._session_generation = int(_saved_turn_state["session_generation"])
	TurnManager._turn_epoch = int(_saved_turn_state["turn_epoch"])
	if _saved_timer_running and _saved_timer_time_left > 0.0:
		TurnManager.turn_timer.start(_saved_timer_time_left)
	DiscoveryManager.configure_storage_path(DiscoveryManager.DEFAULT_STORAGE_PATH)
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DISCOVERY_PATH))
	if is_instance_valid(_player):
		_player.free()
	if is_instance_valid(_other):
		_other.free()
	get_tree().paused = _saved_tree_paused


func test_locked_detail_shows_question_mark_and_only_allows_owner_action() -> void:
	var card := _load_national(&"xia_lian_dan_shu")
	_player.非遗牌手牌.append(card)
	var detail := await _make_detail()

	detail.show_detail(card, _player)
	assert_eq((detail.get_node("VBoxContainer/LblScore") as Label).text, "【分数】?")
	assert_false((detail.get_node("VBoxContainer/TaskPanel/Content/TaskButton") as Button).disabled)
	detail.close_detail()

	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	detail.show_detail(card, _player)
	assert_true((detail.get_node("VBoxContainer/TaskPanel/Content/TaskButton") as Button).disabled)
	assert_string_contains(
		(detail.get_node("VBoxContainer/TaskPanel/Content/Status") as Label).text,
		"行动阶段"
	)
	detail.close_detail()

	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	_player.onTurn = false
	_other.onTurn = true
	TurnManager.now_player_index = 1
	detail.show_detail(card, _player)
	assert_true((detail.get_node("VBoxContainer/TaskPanel/Content/TaskButton") as Button).disabled)
	detail.close_detail()


func test_attempt_double_press_technical_rollback_result_and_modal_round_trip() -> void:
	var card := _load_national(&"xia_lian_dan_shu")
	_player.非遗牌手牌.append(card)
	var detail := await _make_detail()
	TurnManager.turn_timer.start(9.0)
	var remaining_before := TurnManager.turn_timer.time_left

	detail.show_detail(card, _player)
	assert_true(get_tree().paused)
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 1)

	detail._on_task_pressed()
	var first_snapshot := InteractionCoordinator.get_active_snapshot()
	var attempt := detail.get("_active_attempt") as HeritageTaskAttempt
	var host := detail.get("_task_host") as HeritageTaskHost
	assert_not_null(attempt)
	assert_not_null(host)
	assert_eq(_player.current_energy, 5)
	assert_eq(first_snapshot.get("owner"), &"heritage_task")

	detail._on_task_pressed()
	assert_same(detail.get("_active_attempt"), attempt, "重复点击不得创建第二次挑战")
	assert_eq(_player.current_energy, 5, "重复点击不得重复扣除精力")
	assert_eq(
		InteractionCoordinator.get_active_snapshot().get("interaction_id"),
		first_snapshot.get("interaction_id")
	)

	var active_task := host.get_active_task()
	assert_not_null(active_task)
	assert_same(
		_viewport.gui_get_focus_owner(),
		active_task,
		"小游戏开始后必须接管键盘/手柄焦点，避免确认键穿透到底层详情"
	)
	var accept_event := InputEventAction.new()
	accept_event.action = &"ui_accept"
	accept_event.pressed = true
	active_task._gui_input(accept_event)
	assert_same(detail.get("_active_attempt"), attempt, "小游戏确认输入不得重复启动挑战")
	assert_eq(_player.current_energy, 5, "小游戏确认输入不得重复扣除精力")
	active_task.complete_technical_error(&"test_device_failure", "测试设备异常")
	assert_eq(_player.current_energy, 6, "技术故障必须返还挑战成本")
	assert_null(detail.get("_active_attempt"))
	assert_true(InteractionCoordinator.assert_quiescent("heritage detail technical result"))
	assert_true((host.get_node("ResultPanel") as Control).visible, "结果应留在任务宿主中等待玩家返回")
	assert_not_null(detail.get("_task_host"), "结算完成后不得自动跳过结果页")
	detail.close_detail()
	assert_true(detail.visible, "任务结果尚未返回时不能关闭底层详情")
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 1)

	host.return_requested.emit()
	await get_tree().process_frame
	assert_null(detail.get("_task_host"))
	assert_false((detail.get_node("VBoxContainer/TaskPanel/Content/TaskButton") as Button).disabled)
	detail.close_detail()
	assert_false(detail.visible)
	assert_false(get_tree().paused)
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)
	assert_true(InteractionCoordinator.assert_quiescent("heritage detail closed"))
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_almost_eq(TurnManager.turn_timer.time_left, remaining_before, 0.2)


func test_thumbnail_and_detail_change_from_question_mark_to_five_after_success() -> void:
	var card := _load_national(&"han_ju")
	_player.非遗牌手牌.append(card)
	var thumbnail := THUMBNAIL_SCENE.instantiate() as 非遗牌缩略图
	_viewport.add_child(thumbnail)
	thumbnail.setup(card)
	assert_eq((thumbnail.get_node("ScoreBadge/BaseScore") as Label).text, "?")

	var attempt := HeritageTaskManager.begin_attempt(_player, card)
	assert_not_null(attempt)
	assert_true(HeritageTaskManager.finish_attempt(
		attempt,
		HeritageTaskResult.success(card.inheritance_task_id)
	))
	thumbnail.setup(card)
	assert_eq((thumbnail.get_node("ScoreBadge/BaseScore") as Label).text, "5")
	assert_eq(FeiyiDetailContent.build(card, true).get("score"), "【分数】5 分")
	assert_true(InteractionCoordinator.assert_quiescent("heritage thumbnail unlocked"))


func test_detail_removal_cancels_host_refunds_attempt_and_releases_ownership() -> void:
	var card := _load_national(&"xia_lian_dan_shu")
	_player.非遗牌手牌.append(card)
	var detail := await _make_detail()
	detail.show_detail(card, _player)
	detail._on_task_pressed()
	var host := detail.get("_task_host") as HeritageTaskHost
	assert_not_null(host)
	assert_eq(_player.current_energy, 5)

	detail.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(detail))
	assert_false(is_instance_valid(host), "详情被场景切换移除时不得遗留任务宿主遮罩")
	assert_eq(_player.current_energy, 6, "非玩家主动退出的场景清理应回滚成本")
	assert_true(InteractionCoordinator.assert_quiescent("heritage detail removed"))
	assert_eq(int(TurnManager.get_modal_snapshot().get("depth", -1)), 0)
	assert_false(get_tree().paused)


func test_preparation_failure_does_not_emit_entry_or_unlock_minigame() -> void:
	var definition := HeritageTaskManager.get_definition(&"huangmei_xi")
	var host := HOST_SCENE.instantiate() as HeritageTaskHost
	add_child_autofree(host)
	watch_signals(host)
	host.task_entered.connect(_record_minigame_discovery)
	var context := HeritageTaskRunContext.new(definition.task_id)
	host.configure(definition, context)
	host.begin()

	assert_signal_emitted(host, "task_finished")
	assert_signal_not_emitted(host, "task_entered")
	assert_false(DiscoveryManager.is_discovered(DiscoveryManager.KIND_MINIGAME, definition.task_id))
	assert_true((host.get_node("ResultPanel") as Control).visible)


func test_success_failure_and_manual_exit_all_unlock_after_real_entry() -> void:
	var cases: Array[Dictionary] = [
		{&"task_id": &"xia_lian_dan_shu", &"outcome": HeritageTaskResult.Status.SUCCESS},
		{&"task_id": &"han_ju", &"outcome": HeritageTaskResult.Status.FAILURE},
		{&"task_id": &"tianmen_tang_su", &"outcome": HeritageTaskResult.Status.MANUAL_ABORT},
	]
	for case_data: Dictionary in cases:
		var task_id: StringName = case_data[&"task_id"]
		var definition := HeritageTaskManager.get_definition(task_id)
		var host := HOST_SCENE.instantiate() as HeritageTaskHost
		add_child_autofree(host)
		watch_signals(host)
		host.task_entered.connect(_record_minigame_discovery)
		var context := HeritageTaskRunContext.new(task_id)
		context.test_mode = true
		context.forced_outcome = int(case_data[&"outcome"])
		host.configure(definition, context)
		host.begin()
		assert_signal_emitted(host, "task_entered", "%s 应在真正进入后公开" % task_id)
		assert_true(DiscoveryManager.is_discovered(DiscoveryManager.KIND_MINIGAME, task_id))
		await get_tree().process_frame
		assert_signal_emitted(host, "task_finished", "%s 应正常保留结算结果" % task_id)
		assert_true((host.get_node("ResultPanel") as Control).visible)


func test_task_host_and_huangmei_media_fit_supported_desktop_viewports() -> void:
	var host := HOST_SCENE.instantiate() as HeritageTaskHost
	_viewport.add_child(host)
	var huangmei := load("res://InheritanceTasks/Tasks/huangmei_xi.tscn").instantiate() as Control
	var task_container := host.get_node("SafeMargin/Panel/Layout/TaskContainer") as Control
	task_container.add_child(huangmei)
	huangmei.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var supported_sizes: Array[Vector2i] = [
		Vector2i(2560, 1600),
		Vector2i(1920, 1080),
		Vector2i(1280, 720),
		Vector2i(2048, 1536),
		Vector2i(3440, 1440),
	]
	for viewport_size: Vector2i in supported_sizes:
		_viewport.size = viewport_size
		await get_tree().process_frame
		await get_tree().process_frame
		var panel_rect := (host.get_node("SafeMargin/Panel") as Control).get_global_rect()
		var task_rect := task_container.get_global_rect()
		var video_rect := (huangmei.get_node("ReferenceVideo") as Control).get_global_rect()
		assert_true(
			_rect_fits(panel_rect, Rect2(Vector2.ZERO, Vector2(viewport_size))),
			"%s 下任务宿主不得越出视口" % viewport_size
		)
		assert_gte(task_rect.size.y, 320.0, "%s 下小游戏应保留足够操作高度" % viewport_size)
		assert_true(
			_rect_fits(video_rect, task_rect),
			"%s 下黄梅戏示范视频不得越出小游戏区域" % viewport_size
		)
	_viewport.size = Vector2i(2560, 1600)
	host.queue_free()
	await get_tree().process_frame


func _make_detail() -> 非遗详情弹窗:
	var detail := DETAIL_SCENE.instantiate() as 非遗详情弹窗
	_viewport.add_child(detail)
	await get_tree().process_frame
	return detail


func _load_national(task_id: StringName) -> 非遗牌:
	var paths: Dictionary[StringName, String] = {
		&"xia_lian_dan_shu": "res://Cards/非遗牌/荆门/夏氏炼丹术及其祖传秘方.tres",
		&"han_ju": "res://Cards/非遗牌/武汉/汉剧.tres",
	}
	return load(paths.get(task_id, "")) as 非遗牌


func _record_minigame_discovery(task_id: StringName) -> void:
	DiscoveryManager.record_discovery(DiscoveryManager.KIND_MINIGAME, task_id)


func _rect_fits(inner: Rect2, outer: Rect2, tolerance: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - tolerance \
			and inner.position.y >= outer.position.y - tolerance \
			and inner.end.x <= outer.end.x + tolerance \
			and inner.end.y <= outer.end.y + tolerance
