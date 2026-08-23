extends GutTest

const EVENT_OVERLAY_SCENE := preload("res://HUDs/event_overlay.tscn")
const YOU_MU_CARD := preload("res://Cards/事件牌/游目骋怀.tres")
const MIAO_SHOU_CARD := preload("res://Cards/事件牌/妙手回春.tres")
const EXHAUSTED_CARD := preload("res://Cards/事件牌/精疲力尽.tres")
const FREE_PASSAGE_CARD := preload("res://Cards/事件牌/畅行无阻.tres")
const REST_CARD := preload("res://Cards/事件牌/倦艺休整.tres")

var _overlay: EventOverlay
var _player: PlayerClass
var _holder: PlayerClass
var _map: MAP
var _origin: MapSection
var _scenery: MapSection

var _async_done: bool = false
var _async_bool_result: bool = false

var _players_backup: Array[PlayerClass] = []
var _player_num_backup: int
var _player_index_backup: int
var _turn_backup: int
var _phase_backup: TurnManager.TurnPhase
var _game_on_backup: bool
var _modal_depth_backup: int
var _modal_resume_time_backup: float
var _modal_resume_phase_backup: TurnManager.TurnPhase
var _map_backup: MAP
var _turn_hud_backup: HUD
var _timer_was_stopped: bool
var _timer_time_left_backup: float
var _tree_paused_backup: bool
var _event_hud_backup: HUD
var _event_overlay_backup: Control
var _auto_resolve_backup: bool
var _choice_strategy_backup: Callable
var _event_status_backup: Dictionary
var _resource_hud_backup: HUD
var _event_deck_backup: Array[事件牌] = []
var _event_discard_backup: Array[事件牌] = []


func before_each() -> void:
	_backup_autoload_state()
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	TurnManager.players.clear()
	TurnManager.player_num = 0
	TurnManager.now_player_index = 0
	TurnManager.now_turn = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	TurnManager.modal_resolution_depth = 0
	TurnManager._modal_resume_time = 0.0
	TurnManager._modal_resume_phase = TurnManager.TurnPhase.BEGIN
	TurnManager.hud = null
	ResourceManager.hud = null
	ResourceManager.事件弃牌堆.clear()

	EventManager.reset_for_new_game()
	EventManager.auto_resolve_choices = false
	EventManager.choice_strategy = Callable()

	_build_runtime_fixture()
	_overlay = EVENT_OVERLAY_SCENE.instantiate() as EventOverlay
	add_child_autofree(_overlay)
	EventManager.bind_runtime(null, _overlay)
	await get_tree().process_frame
	TurnManager.turn_timer.start(6.0)


func after_each() -> void:
	TurnManager.turn_timer.stop()
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(_event_hud_backup, _event_overlay_backup)
	EventManager.auto_resolve_choices = _auto_resolve_backup
	EventManager.choice_strategy = _choice_strategy_backup
	EventManager._status_by_player = _event_status_backup.duplicate(true)
	ResourceManager.事件牌库.assign(_event_deck_backup)
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	ResourceManager.hud = _resource_hud_backup

	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = _player_num_backup
	TurnManager.now_player_index = _player_index_backup
	TurnManager.now_turn = _turn_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.GameOn = _game_on_backup
	TurnManager.modal_resolution_depth = _modal_depth_backup
	TurnManager._modal_resume_time = _modal_resume_time_backup
	TurnManager._modal_resume_phase = _modal_resume_phase_backup
	TurnManager.map = _map_backup
	TurnManager.hud = _turn_hud_backup
	if not _timer_was_stopped:
		TurnManager.turn_timer.start(maxf(_timer_time_left_backup, 0.05))
	get_tree().paused = _tree_paused_backup

	_player.free()
	_holder.free()
	_map.free()


func test_direct_you_mu_choice_closes_overlay_and_restores_action_timer() -> void:
	var card := YOU_MU_CARD as 事件牌
	_player.事件牌手牌.append(card)
	_player.current_energy = 4
	_async_done = false
	_run_direct_retained_use(card)

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	assert_true(_overlay.visible)
	var request := _overlay._active_request
	assert_eq(request.kind, EventChoiceRequest.ChoiceKind.格子)
	assert_true(request.options.has(_scenery))
	EventManager.submit_choice(request.request_id, _scenery)

	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_overlay.visible, "游目骋怀完成后事件遮罩必须关闭")
	assert_null(_overlay._active_request)
	assert_eq(_player.now_pos, _scenery.location_index)
	assert_eq(_player.current_energy, 9, "游目骋怀只执行牌面规定的 +5 精力")
	assert_false(_player.事件牌手牌.has(card))
	assert_true(ResourceManager.事件弃牌堆.has(card))
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_gt(TurnManager.turn_timer.time_left, 14.0)


func test_retained_event_menu_cancel_closes_overlay_without_consuming_card() -> void:
	var card := YOU_MU_CARD as 事件牌
	_player.事件牌手牌.append(card)
	_async_done = false
	_run_retained_menu()

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var request := _overlay._active_request
	assert_true(request.optional)
	assert_true(request.options.has(card))
	EventManager.submit_choice(request.request_id, null)

	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_overlay.visible, "放弃保留牌菜单后事件遮罩必须关闭")
	assert_null(_overlay._active_request)
	assert_true(_player.事件牌手牌.has(card), "放弃不得消耗保留事件牌")
	assert_true(ResourceManager.事件弃牌堆.is_empty())
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_gt(TurnManager.turn_timer.time_left, 14.0)


func test_miao_shou_accept_closes_overlay_and_releases_modal() -> void:
	var card := MIAO_SHOU_CARD as 事件牌
	_holder.事件牌手牌.append(card)
	_player.current_energy = 0
	TurnManager.now_phase = TurnManager.TurnPhase.END
	TurnManager.turn_timer.stop()
	_async_done = false
	_async_bool_result = false
	_run_revive()

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var request := _overlay._active_request
	assert_eq(request.requester, _holder)
	assert_true(request.optional)
	EventManager.submit_choice(request.request_id, true)

	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_true(_async_bool_result)
	assert_false(_overlay.visible, "妙手回春发动后响应遮罩必须关闭")
	assert_null(_overlay._active_request)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_true(TurnManager.turn_timer.is_stopped(), "回合末死亡响应不得启动 ACTION 计时")
	assert_eq(_player.current_energy, 3)
	assert_true(_player.alive)
	assert_false(_holder.事件牌手牌.has(card))
	assert_true(ResourceManager.事件弃牌堆.has(card))


func test_miao_shou_cancel_closes_overlay_and_releases_modal_without_consuming_card() -> void:
	var card := MIAO_SHOU_CARD as 事件牌
	_holder.事件牌手牌.append(card)
	_player.current_energy = 0
	TurnManager.now_phase = TurnManager.TurnPhase.END
	TurnManager.turn_timer.stop()
	_async_done = false
	_async_bool_result = true
	_run_revive()

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var request := _overlay._active_request
	EventManager.submit_choice(request.request_id, null)

	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_async_bool_result)
	assert_false(_overlay.visible, "放弃妙手回春后响应遮罩必须关闭")
	assert_null(_overlay._active_request)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_eq(_player.current_energy, 0)
	assert_true(_holder.事件牌手牌.has(card), "放弃响应不得消耗妙手回春")
	assert_true(ResourceManager.事件弃牌堆.is_empty())


func test_new_game_reset_closes_a_pending_event_overlay() -> void:
	var card := YOU_MU_CARD as 事件牌
	_player.事件牌手牌.append(card)
	_async_done = false
	_run_direct_retained_use(card)

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	assert_true(_overlay.visible)
	EventManager.reset_for_new_game()
	await get_tree().process_frame

	assert_false(_overlay.visible, "会话重置必须清除仍在等待选择的事件遮罩")
	assert_null(_overlay._active_request)


func test_regular_event_still_closes_through_the_shared_interaction_lifecycle() -> void:
	var card := EXHAUSTED_CARD as 事件牌
	_player.current_energy = 6
	_async_done = false
	_run_regular_event(card)

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var request := _overlay._active_request
	assert_eq(request.kind, EventChoiceRequest.ChoiceKind.确认)
	EventManager.submit_choice(request.request_id, true)

	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_overlay.visible)
	assert_null(_overlay._active_request)
	assert_eq(_player.current_energy, 3)
	assert_true(ResourceManager.事件弃牌堆.has(card))
	assert_eq(TurnManager.modal_resolution_depth, 0)


func test_multistep_regular_event_stays_open_until_its_last_choice() -> void:
	var card := REST_CARD as 事件牌
	_async_done = false
	_run_regular_event(card)

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var reveal_request_id := _overlay._active_request.request_id
	EventManager.submit_choice(reveal_request_id, true)
	assert_true(await _wait_until(
		func() -> bool:
			return _overlay._active_request != null and _overlay._active_request.request_id != reveal_request_id
	))
	assert_true(_overlay.visible, "中间选择完成后不得提前关闭多步事件")
	assert_eq(TurnManager.modal_resolution_depth, 1)
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_true(_overlay._active_request.prompt.begins_with("是否跳过"))

	EventManager.submit_choice(_overlay._active_request.request_id, false)
	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_overlay.visible)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)
	assert_gt(TurnManager.turn_timer.time_left, 14.0)


func test_retained_preview_only_releases_a_pause_it_owns() -> void:
	var card := YOU_MU_CARD as 事件牌
	_player.事件牌手牌.append(card)
	get_tree().paused = true

	_overlay.show_retained_card_detail(_player, card)
	assert_true(_overlay.visible)
	_overlay.close_retained_card_detail()

	assert_true(get_tree().paused, "保留牌详情不得解除其他系统持有的全局暂停")
	assert_false(_overlay.visible)
	get_tree().paused = false


func test_moving_retained_event_restores_the_paused_moving_timer() -> void:
	var card := FREE_PASSAGE_CARD as 事件牌
	_player.事件牌手牌.append(card)
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.turn_timer.start(6.0)
	_async_done = false

	_run_direct_retained_use(card)
	assert_true(await _wait_until(func() -> bool: return _async_done))

	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_false(TurnManager.turn_timer.is_stopped(), "移动阶段使用保留牌后必须恢复移动倒计时")
	assert_gt(TurnManager.turn_timer.time_left, 5.0)
	assert_lte(TurnManager.turn_timer.time_left, 6.0)


func test_revive_chain_stays_open_for_the_next_holder_and_closes_after_timeout() -> void:
	var first_card := MIAO_SHOU_CARD.duplicate(true) as 事件牌
	var second_card := MIAO_SHOU_CARD.duplicate(true) as 事件牌
	var second_holder := PlayerClass.new()
	second_holder.player_name = "第二持牌玩家"
	second_holder.map = _map
	autofree(second_holder)
	_holder.事件牌手牌.append(first_card)
	second_holder.事件牌手牌.append(second_card)
	_player.current_energy = 0
	TurnManager.players.assign([_player, _holder, second_holder])
	TurnManager.player_num = 3
	TurnManager.now_phase = TurnManager.TurnPhase.END
	TurnManager.turn_timer.stop()
	_async_done = false
	_async_bool_result = true
	_run_revive()

	assert_true(await _wait_until(func() -> bool: return _overlay._active_request != null))
	var first_request_id := _overlay._active_request.request_id
	assert_eq(_overlay._active_request.requester, _holder)
	EventManager.submit_choice(first_request_id, null)
	assert_true(await _wait_until(
		func() -> bool:
			return _overlay._active_request != null and _overlay._active_request.request_id != first_request_id
	))
	assert_true(_overlay.visible, "前一位放弃后必须继续显示下一位持有者的响应")
	assert_eq(_overlay._active_request.requester, second_holder)
	assert_eq(TurnManager.modal_resolution_depth, 1)

	EventManager._on_choice_timeout()
	assert_true(await _wait_until(func() -> bool: return _async_done))
	assert_false(_async_bool_result)
	assert_false(_overlay.visible)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_true(_holder.事件牌手牌.has(first_card))
	assert_true(second_holder.事件牌手牌.has(second_card))


func _backup_autoload_state() -> void:
	_players_backup.assign(TurnManager.players)
	_player_num_backup = TurnManager.player_num
	_player_index_backup = TurnManager.now_player_index
	_turn_backup = TurnManager.now_turn
	_phase_backup = TurnManager.now_phase
	_game_on_backup = TurnManager.GameOn
	_modal_depth_backup = TurnManager.modal_resolution_depth
	_modal_resume_time_backup = TurnManager._modal_resume_time
	_modal_resume_phase_backup = TurnManager._modal_resume_phase
	_map_backup = TurnManager.map
	_turn_hud_backup = TurnManager.hud
	_timer_was_stopped = TurnManager.turn_timer.is_stopped()
	_timer_time_left_backup = TurnManager.turn_timer.time_left
	_tree_paused_backup = get_tree().paused
	_event_hud_backup = EventManager.hud
	_event_overlay_backup = EventManager.event_overlay
	_auto_resolve_backup = EventManager.auto_resolve_choices
	_choice_strategy_backup = EventManager.choice_strategy
	_event_status_backup = EventManager._status_by_player.duplicate(true)
	_resource_hud_backup = ResourceManager.hud
	_event_deck_backup.assign(ResourceManager.事件牌库)
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)


func _build_runtime_fixture() -> void:
	_map = MAP.new()
	_origin = MapSection.new()
	_origin.section_name = "起点"
	_origin.type = MapSection.SectionType.一般
	_origin.location_index = Vector3i.ZERO
	_origin.is_occupied = true
	_map.add_child(_origin)
	_map.grid_map[_origin.location_index] = _origin

	_scenery = MapSection.new()
	_scenery.section_name = "测试风景"
	_scenery.type = MapSection.SectionType.风景
	_scenery.location_index = Vector3i(1, -1, 0)
	_map.add_child(_scenery)
	_map.grid_map[_scenery.location_index] = _scenery

	_player = PlayerClass.new()
	_player.player_name = "待复活玩家"
	_player.map = _map
	_player.now_pos = _origin.location_index
	_player.hud = null
	_holder = PlayerClass.new()
	_holder.player_name = "持牌玩家"
	_holder.map = _map
	_holder.now_pos = _origin.location_index
	_holder.hud = null
	TurnManager.map = _map
	TurnManager.players.assign([_player, _holder])
	TurnManager.player_num = 2


func _run_direct_retained_use(card: 事件牌) -> void:
	await EventManager.request_play_retained_event(_player, card)
	_async_done = true


func _run_retained_menu() -> void:
	await EventManager.open_retained_event_menu(_player)
	_async_done = true


func _run_revive() -> void:
	_async_bool_result = await EventManager.try_revive_player(_player)
	_async_done = true


func _run_regular_event(card: 事件牌) -> void:
	await EventManager.resolve_event(_player, card)
	_async_done = true


func _wait_until(predicate: Callable, max_frames: int = 30) -> bool:
	for _frame: int in max_frames:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())
