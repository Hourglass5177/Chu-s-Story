extends GutTest


class ProfessionProbeMap extends MAP:
	func _ready() -> void:
		pass

	func _show_reachable_areas() -> void:
		pass

	func _clear_all_highlights() -> void:
		pass


class ProfessionProbeHUD extends HUD:
	var shop_panel: 商店弹窗 = null
	var shop_open_count: int = 0
	var messages: Array[String] = []
	var camera_focus_targets: Array[PlayerClass] = []
	var leave_focus_count: int = 0

	func _ready() -> void:
		pass

	func _update_player_stats(_player: PlayerClass) -> void:
		pass

	func update_camera_view(_duration: float = 0.4):
		pass

	func update_camera_view_for_player(player: PlayerClass, _duration: float = 0.4) -> void:
		camera_focus_targets.append(player)

	func _leave_focus_at_current_camera() -> void:
		leave_focus_count += 1
		super._leave_focus_at_current_camera()

	func _update_button_states(_phase: TurnManager.TurnPhase) -> void:
		pass

	func _update_game_informs(message: String) -> void:
		messages.append(message)

	func open_shop_panel(player: PlayerClass):
		shop_open_count += 1
		if shop_panel != null:
			shop_panel.open_shop(player)


class ProfessionProbePlayer extends PlayerClass:
	func _ready() -> void:
		pass


var _event_deck_backup: Array[事件牌] = []
var _event_discard_backup: Array[事件牌] = []
var _food_deck_backup: Array[卡牌基类] = []
var _regional_decks_backup: Dictionary = {}
var _resource_hud_backup: HUD = null
var _event_hud_backup: HUD = null
var _event_overlay_backup: Control = null
var _turn_players_backup: Array[PlayerClass] = []
var _turn_game_on_backup: bool = false
var _turn_phase_backup: TurnManager.TurnPhase = TurnManager.TurnPhase.BEGIN
var _turn_number_backup: int = 0
var _turn_index_backup: int = 0
var _turn_next_index_backup: int = 0
var _turn_player_num_backup: int = 0
var _turn_modal_backup: int = 0
var _turn_epoch_backup: int = 0
var _turn_ending_backup: bool = false
var _turn_map_backup: MAP = null
var _turn_hud_backup: HUD = null
var _tree_paused_backup: bool = false
var _owned_nodes: Array[Node] = []


func before_each() -> void:
	_event_deck_backup.assign(ResourceManager.事件牌库)
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)
	_food_deck_backup.assign(ResourceManager.食物牌库)
	_regional_decks_backup = ResourceManager.地区非遗牌库.duplicate(true)
	_resource_hud_backup = ResourceManager.hud
	_event_hud_backup = EventManager.hud
	_event_overlay_backup = EventManager.event_overlay
	_turn_players_backup.assign(TurnManager.players)
	_turn_game_on_backup = TurnManager.GameOn
	_turn_phase_backup = TurnManager.now_phase
	_turn_number_backup = TurnManager.now_turn
	_turn_index_backup = TurnManager.now_player_index
	_turn_next_index_backup = TurnManager.next_player_index
	_turn_player_num_backup = TurnManager.player_num
	_turn_modal_backup = TurnManager.modal_resolution_depth
	_turn_epoch_backup = TurnManager._turn_epoch
	_turn_ending_backup = TurnManager._ending_turn
	_turn_map_backup = TurnManager.map
	_turn_hud_backup = TurnManager.hud
	_tree_paused_backup = get_tree().paused
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false
	TurnManager.invalidate_all_modals(&"profession_test_setup")
	TurnManager._ending_turn = false
	ResourceManager.hud = null
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	ProfessionManager.reset_for_new_game()


func after_each() -> void:
	get_tree().paused = false
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false
	TurnManager.invalidate_all_modals(&"profession_test_cleanup")
	EventManager.reset_for_new_game()
	ProfessionManager.reset_for_new_game()
	for index: int in range(_owned_nodes.size() - 1, -1, -1):
		var node: Node = _owned_nodes[index]
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
	ResourceManager.事件牌库.assign(_event_deck_backup)
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	ResourceManager.食物牌库.assign(_food_deck_backup)
	ResourceManager.地区非遗牌库 = _regional_decks_backup.duplicate(true)
	ResourceManager.hud = _resource_hud_backup
	EventManager.bind_runtime(_event_hud_backup, _event_overlay_backup)
	TurnManager.players.assign(_turn_players_backup)
	TurnManager.GameOn = _turn_game_on_backup
	TurnManager.now_phase = _turn_phase_backup
	TurnManager.now_turn = _turn_number_backup
	TurnManager.now_player_index = _turn_index_backup
	TurnManager.next_player_index = _turn_next_index_backup
	TurnManager.player_num = _turn_player_num_backup
	# 模态租约不能像旧裸计数一样只恢复 depth；测试退出时必须保持完整租约状态归零。
	TurnManager.modal_resolution_depth = 0
	TurnManager._turn_epoch = _turn_epoch_backup
	TurnManager._ending_turn = _turn_ending_backup
	TurnManager.map = _turn_map_backup
	TurnManager.hud = _turn_hud_backup
	get_tree().paused = _tree_paused_backup


func test_magic_blogger_event_arrival_draws_three_selects_one_and_restores_top_order() -> void:
	var player := _own(ProfessionProbePlayer.new()) as ProfessionProbePlayer
	player.player_name = "魔术事件测试"
	player.player_types = PlayerClass.PlayerCharacter.魔术博主
	player.current_energy = 6
	player.arrival_id = 1
	player.now_pos = Vector3i.ZERO
	player.last_normal_arrival_position = player.now_pos
	player.last_action_arrival_position = player.now_pos
	player.last_action_arrival_turn_epoch = TurnManager.get_turn_epoch()
	player.last_action_arrival_session_generation = TurnManager.get_session_generation()
	var event_section := _own(MapSection.new()) as MapSection
	event_section.type = MapSection.SectionType.事件
	event_section.location_index = player.now_pos

	var first := load("res://Cards/事件牌/精疲力尽.tres") as 事件牌
	var selected := load("res://Cards/事件牌/艺创增收.tres") as 事件牌
	var third := load("res://Cards/事件牌/文化新风.tres") as 事件牌
	ResourceManager.事件牌库.assign([third, selected, first])
	ResourceManager.事件弃牌堆.clear()
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	TurnManager.turn_timer.start(9.0)
	var request_count := {&"value": 0}
	var choose_second := func(request: ProfessionDrawRequest) -> void:
		request_count[&"value"] = int(request_count[&"value"]) + 1
		assert_eq(TurnManager.modal_resolution_depth, 1, "魔术择牌期间必须持有独立模态锁")
		assert_true(TurnManager.turn_timer.is_stopped(), "魔术择牌期间阶段计时必须暂停")
		assert_eq(request.deck_kind, &"event")
		assert_eq(request.cards, [first, selected, third])
		ProfessionManager.submit_draw_choice(request.request_id, selected, [third, first])
	ProfessionManager.draw_choice_requested.connect(choose_second, CONNECT_ONE_SHOT)

	await EventManager.trigger_arrival_event(player, event_section, player.arrival_id)

	assert_eq(request_count[&"value"], 1, "事件格实际抽牌入口必须触发魔术博主三选一")
	assert_true(ResourceManager.事件弃牌堆.has(selected), "选中的事件应照常公开并结算")
	assert_eq(ResourceManager.事件牌库.size(), 2)
	assert_eq(ResourceManager.事件牌库[-1], third, "回顶顺序第一张应成为下一张牌顶")
	assert_eq(ResourceManager.事件牌库[-2], first)
	assert_eq(player.current_money, 800, "应从新初始积分点500结算玩家选择的艺创增收，而非原牌顶")
	assert_eq(player.current_energy, 6)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_gt(TurnManager.turn_timer.time_left, 14.0, "事件完整结算后应恢复完整 ACTION 计时")


func test_magic_blogger_feiyi_draws_three_selects_one_and_restores_top_order() -> void:
	var player := _own(PlayerClass.new()) as PlayerClass
	player.player_name = "魔术非遗测试"
	player.player_types = PlayerClass.PlayerCharacter.魔术博主
	player.current_energy = 6
	var section := _own(MapSection.new()) as MapSection
	section.type = MapSection.SectionType.非遗
	section.region = MapSection.REGION.鄂州
	var first := _make_feiyi("第一张")
	var selected := _make_feiyi("第二张")
	var third := _make_feiyi("第三张")
	var deck: Array[非遗牌] = [third, selected, first]
	ResourceManager.地区非遗牌库[section.region] = deck
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	var choose_second := func(request: ProfessionDrawRequest) -> void:
		assert_eq(request.deck_kind, &"feiyi")
		assert_eq(request.cards, [first, selected, third])
		ProfessionManager.submit_draw_choice(request.request_id, selected, [third, first])
	ProfessionManager.draw_choice_requested.connect(choose_second, CONNECT_ONE_SHOT)

	var result: 非遗牌 = await ResourceManager.get_feiyi_with_profession(player, section)

	assert_eq(result, selected)
	assert_eq(player.非遗牌手牌, [selected])
	assert_eq(player.current_energy, 5, "三选一只支付一次正常收集消耗")
	var remaining: Array = ResourceManager.地区非遗牌库[section.region]
	assert_eq(remaining.size(), 2)
	assert_eq(remaining[-1], third, "自定义回顶顺序第一张应成为下一张牌顶")
	assert_eq(remaining[-2], first)


func test_magic_draw_panel_makes_the_time_limit_explicit() -> void:
	var panel := load("res://HUDs/职业抽牌弹窗.tscn").instantiate() as ProfessionDrawPanel
	add_child_autofree(panel)
	await get_tree().process_frame
	var player := _own(PlayerClass.new()) as PlayerClass
	player.player_name = "魔术测试"
	var card := 事件牌.new()
	card.card_name = "倒计时测试"
	var request := ProfessionDrawRequest.new(player, [card], &"event")
	request.request_id = 701
	request.timeout_seconds = 15.0

	panel._on_choice_requested(request)

	assert_eq(panel.context_label.text, player.player_name, "选牌弹窗标题只保留当前玩家，不显示默认选择规则")
	assert_eq(panel.countdown_label.text, "剩余 15 秒")
	assert_eq(ProfessionDrawPanel.format_countdown(4.2), "剩余 05 秒")
	var countdown_color := panel.countdown_label.get_theme_color("font_color")
	assert_gt(countdown_color.r + countdown_color.g, 1.5, "倒计时应使用醒目的暖金色，而不是融入棕色标题栏")
	panel.reset_panel()
	await get_tree().process_frame


func test_modal_blocks_both_legacy_and_direct_phase_requests() -> void:
	var player := _own(ProfessionProbePlayer.new()) as ProfessionProbePlayer
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.GameOn = true
	var modal_token := TurnManager.begin_modal_resolution()

	player.request_end_turn()
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.MOVING, "旧玩家入口不得绕过模态锁")
	TurnManager.next_phase.emit(TurnManager.TurnPhase.ACTION)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.MOVING, "直接发送阶段信号也必须经过最终模态校验")

	assert_true(TurnManager.end_modal_resolution(false, false, modal_token))


func test_stale_modal_token_cannot_release_a_new_modal() -> void:
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.END
	var stale_token := TurnManager.begin_modal_resolution()
	assert_true(TurnManager.end_modal_resolution(false, false, stale_token))
	var current_token := TurnManager.begin_modal_resolution()

	assert_ne(current_token, stale_token)
	assert_false(TurnManager.end_modal_resolution(false, false, stale_token), "旧协程不得释放后来创建的模态")
	assert_eq(TurnManager.modal_resolution_depth, 1)
	assert_true(TurnManager.end_modal_resolution(false, false, current_token))


func test_explorer_end_move_only_offers_empty_adjacent_sections_and_does_not_record_arrival() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	var occupied := fixture[&"occupied"] as MapSection
	player.is_working = true
	player.work_turns_left = 2
	player.current_work_index = 9
	var arrival_before: int = player.arrival_id
	var last_arrival_before: Vector3i = player.last_normal_arrival_position
	var choose_target := func(request: ProfessionSectionChoiceRequest) -> void:
		assert_eq(request.options, [target], "被占用的相邻格不得成为探险终点")
		assert_false(request.options.has(occupied))
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(choose_target, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().create_timer(0.4).timeout

	assert_eq(player.now_pos, target.location_index)
	assert_false(origin.is_occupied)
	assert_true(target.is_occupied)
	assert_eq(player.arrival_id, arrival_before, "END 邻格探索不构成普通到达")
	assert_eq(player.last_normal_arrival_position, last_arrival_before)
	assert_eq(int(target.grid_visit_history.get(player, 0)), 0, "不得增加访问历史或触发目标格")
	assert_false(player.is_working, "探险移动应立即结束连续打工")
	assert_eq(player.work_turns_left, 0)
	assert_eq(player.current_work_index, -1)
	assert_eq(TurnManager.modal_resolution_depth, 0)


func test_explorer_begin_and_end_each_activate_once_in_the_same_turn() -> void:
	var fixture := _make_explorer_fixture(TurnManager.TurnPhase.BEGIN)
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	var request_phases: Array[TurnManager.TurnPhase] = []
	var choose_by_phase := func(request: ProfessionSectionChoiceRequest) -> void:
		request_phases.append(TurnManager.now_phase)
		var destination := target if TurnManager.now_phase == TurnManager.TurnPhase.BEGIN else origin
		ProfessionManager.submit_section_choice(request.request_id, destination)
	ProfessionManager.section_choice_requested.connect(choose_by_phase)

	player._begin_profession_begin_move()
	await get_tree().create_timer(0.35).timeout
	player._begin_profession_begin_move()
	await get_tree().process_frame
	assert_eq(player.now_pos, target.location_index)
	assert_eq(player.arrival_id, 8, "BEGIN 探索应登记一次本回合 ACTION 到达")
	assert_true(player.has_current_action_arrival_at(target.location_index))

	TurnManager.now_phase = TurnManager.TurnPhase.END
	player._begin_profession_end_move()
	await get_tree().create_timer(0.35).timeout
	player._begin_profession_end_move()
	await get_tree().process_frame
	assert_eq(player.now_pos, origin.location_index)
	assert_eq(player.arrival_id, 8, "END 探索仍不得登记可延迟结算的到达")
	assert_eq(request_phases, [TurnManager.TurnPhase.BEGIN, TurnManager.TurnPhase.END])
	ProfessionManager.section_choice_requested.disconnect(choose_by_phase)


func test_explorer_begin_event_arrival_waits_until_action_and_resolves_once() -> void:
	var fixture := _make_explorer_fixture(TurnManager.TurnPhase.BEGIN)
	var player := fixture[&"player"] as ProfessionProbePlayer
	var target := fixture[&"target"] as MapSection
	player.current_energy = 6
	ResourceManager.事件牌库.assign([load("res://Cards/事件牌/精疲力尽.tres") as 事件牌])
	ResourceManager.事件弃牌堆.clear()
	EventManager.auto_resolve_choices = true
	var choose_target := func(request: ProfessionSectionChoiceRequest) -> void:
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(choose_target, CONNECT_ONE_SHOT)

	player._begin_profession_begin_move()
	await get_tree().create_timer(0.35).timeout
	assert_eq(player.now_pos, target.location_index)
	assert_eq(player.current_energy, 6, "BEGIN 移动完成时不得立即触发事件")
	assert_eq(ResourceManager.事件弃牌堆.size(), 0)
	assert_eq(int(target.grid_visit_history.get(player, 0)), 1, "BEGIN 实际到达应记录访问")

	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	assert_eq(ResourceManager.事件弃牌堆.size(), 0, "MOVING 仍不得提前触发")
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	await player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(player.current_energy, 3)
	assert_eq(ResourceManager.事件弃牌堆.size(), 1)
	assert_eq(player.last_resolved_event_arrival_id, player.arrival_id)
	await player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(ResourceManager.事件弃牌堆.size(), 1, "同一次 BEGIN 到达不得重复触发")


func test_normal_moving_overrides_explorer_begin_pending_destination() -> void:
	var fixture := _make_explorer_fixture(TurnManager.TurnPhase.BEGIN)
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	ResourceManager.事件牌库.assign([load("res://Cards/事件牌/精疲力尽.tres") as 事件牌])
	ResourceManager.事件弃牌堆.clear()
	EventManager.auto_resolve_choices = true
	var choose_target := func(request: ProfessionSectionChoiceRequest) -> void:
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(choose_target, CONNECT_ONE_SHOT)

	player._begin_profession_begin_move()
	await get_tree().create_timer(0.35).timeout
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	player.maxMove = 1
	assert_true(await player.move_along_path([origin.global_position], 0, origin.location_index))
	TurnManager.turn_timer.stop()
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	await player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(player.now_pos, origin.location_index)
	assert_eq(ResourceManager.事件弃牌堆.size(), 0, "ACTION 只能处理普通移动后的最终落点")


func test_explorer_end_destination_never_becomes_next_turn_pending_event() -> void:
	var fixture := _make_explorer_fixture(TurnManager.TurnPhase.END)
	var player := fixture[&"player"] as ProfessionProbePlayer
	var target := fixture[&"target"] as MapSection
	ResourceManager.事件牌库.assign([load("res://Cards/事件牌/精疲力尽.tres") as 事件牌])
	ResourceManager.事件弃牌堆.clear()
	EventManager.auto_resolve_choices = true
	var choose_target := func(request: ProfessionSectionChoiceRequest) -> void:
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(choose_target, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().create_timer(0.35).timeout
	TurnManager._turn_epoch += 1
	TurnManager.now_phase = TurnManager.TurnPhase.BEGIN
	player.reset_turn_usage_limits()
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	await player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(ResourceManager.事件弃牌堆.size(), 0, "END 落点不得在下一回合迟发事件")


func test_explorer_end_choice_timeout_keeps_position_and_work_state() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	player.is_working = true
	player.work_turns_left = 2
	var time_out_now := func(_request: ProfessionSectionChoiceRequest) -> void:
		ProfessionManager._on_section_choice_timeout()
	ProfessionManager.section_choice_requested.connect(time_out_now, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(player.now_pos, origin.location_index)
	assert_true(origin.is_occupied)
	assert_false(target.is_occupied)
	assert_true(player.is_working, "放弃可选移动不应凭空结束打工")
	assert_eq(player.work_turns_left, 2)
	assert_eq(TurnManager.modal_resolution_depth, 0)


func test_explorer_end_choice_starts_only_once_per_turn_epoch() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var request_count := {&"value": 0}
	var decline := func(_request: ProfessionSectionChoiceRequest) -> void:
		request_count[&"value"] = int(request_count[&"value"]) + 1
		ProfessionManager._on_section_choice_timeout()
	ProfessionManager.section_choice_requested.connect(decline)

	player._begin_profession_end_move()
	await get_tree().process_frame
	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(request_count[&"value"], 1, "同一个 END 被重复广播时不得重复开启探险技能")
	ProfessionManager.section_choice_requested.disconnect(decline)


func test_explorer_dedupe_includes_session_generation() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	player._profession_end_move_session_generation = TurnManager.get_session_generation() - 1
	player._profession_end_move_turn_epoch = TurnManager.get_turn_epoch()
	var request_count := {&"value": 0}
	var decline := func(_request: ProfessionSectionChoiceRequest) -> void:
		request_count[&"value"] = int(request_count[&"value"]) + 1
		ProfessionManager._on_section_choice_timeout()
	ProfessionManager.section_choice_requested.connect(decline, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(request_count[&"value"], 1, "跨局复用玩家节点时，同编号回合仍应重新获得职业机会")


func test_explorer_camera_restores_only_after_movement_and_binds_the_actor() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var target := fixture[&"target"] as MapSection
	var hud := fixture[&"hud"] as ProfessionProbeHUD
	var next_player := _own(PlayerClass.new()) as PlayerClass
	next_player.player_name = "下一玩家"
	next_player.player_index = 1
	TurnManager.players.assign([player, next_player])
	TurnManager.player_num = 2
	hud.is_focus_mode = true
	var camera := _own(Camera2D.new()) as Camera2D
	var viewport := _own(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(800, 500)
	hud.map_camera = camera
	hud.map_viewport = viewport
	hud.global_zoom = Vector2.ONE
	hud.map_zoom_factor = 2.0
	hud.global_pos = Vector2(1280.0, 800.0)
	hud._global_camera_position = Vector2(1280.0, 800.0)
	var displayed_center := Vector2(900.0, 600.0)
	camera.position = displayed_center
	camera.zoom = Vector2(2.0, 2.0)
	ProfessionManager.section_choice_resolved.connect(hud._on_profession_section_choice_resolved, CONNECT_ONE_SHOT)
	var choose_target := func(request: ProfessionSectionChoiceRequest) -> void:
		hud._on_profession_section_choice_requested(request)
		assert_false(hud.btn_view_toggle.disabled, "探险选点期间 ALT 必须保持可用")
		hud._on_view_toggle_pressed()
		assert_true(hud.is_focus_mode, "探险选点期间应能立即切换到追踪视角")
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(choose_target, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()

	assert_true(hud.is_focus_mode, "玩家手动切换的追踪视角必须在技能移动期间保持")
	assert_eq(hud.leave_focus_count, 1, "探险选点必须通过保留当前镜头中心的统一入口解除追踪")
	assert_eq(hud._global_camera_position, displayed_center, "进入探险选点不得跳向陈旧的全局中心或其他玩家")
	assert_eq(camera.position, displayed_center, "进入探险选点本身不得产生额外运镜")
	assert_false(hud.btn_view_toggle.disabled, "棋子技能移动期间 ALT 不得被锁定")
	assert_true(hud.camera_focus_targets.is_empty(), "选项确定不等于技能移动完成")
	await get_tree().create_timer(0.35).timeout
	assert_eq(player.now_pos, target.location_index)
	assert_true(hud.is_focus_mode)
	assert_false(hud.btn_view_toggle.disabled)
	assert_eq(hud.camera_focus_targets, [player], "技能结束时必须显式追踪发动者，而不是读取可变的下一玩家")
	assert_eq(TurnManager.now_player_index, 0, "技能完整结束前后都不得提前交接玩家")


func test_explorer_old_coroutine_cannot_move_after_turn_owner_changes() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	var next_player := _own(PlayerClass.new()) as PlayerClass
	next_player.player_index = 1
	next_player.onTurn = true
	TurnManager.players.assign([player, next_player])
	TurnManager.player_num = 2
	var invalidate_owner := func(request: ProfessionSectionChoiceRequest) -> void:
		TurnManager.now_player_index = 1
		player.onTurn = false
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(invalidate_owner, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(player.now_pos, origin.location_index)
	assert_true(origin.is_occupied)
	assert_false(target.is_occupied, "旧回合协程不得预占或移动到新回合中的目标格")
	assert_eq(TurnManager.modal_resolution_depth, 0)


func test_explorer_optional_choice_can_be_declined_immediately_from_action_button() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var target := fixture[&"target"] as MapSection
	var hud := fixture[&"hud"] as ProfessionProbeHUD
	var request_seen := {&"value": null}
	var decline_from_hud := func(request: ProfessionSectionChoiceRequest) -> void:
		request_seen[&"value"] = request
		hud._active_profession_map_request = request
		hud._on_btn_action_pressed()
	ProfessionManager.section_choice_requested.connect(decline_from_hud, CONNECT_ONE_SHOT)

	var selected := await ProfessionManager.request_section_choice(player, [target], "邻格探索", "请选择相邻格子")

	assert_not_null(request_seen[&"value"])
	assert_null(selected, "可选探险技能应能通过“不移动”立即放弃")


func test_explorer_failed_move_keeps_work_state_and_reports_no_move() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var origin := fixture[&"origin"] as MapSection
	var target := fixture[&"target"] as MapSection
	var hud := fixture[&"hud"] as ProfessionProbeHUD
	player.is_working = true
	player.work_turns_left = 2
	player.current_work_index = 9
	var invalidate_then_choose := func(request: ProfessionSectionChoiceRequest) -> void:
		target.is_occupied = true
		ProfessionManager.submit_section_choice(request.request_id, target)
	ProfessionManager.section_choice_requested.connect(invalidate_then_choose, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(player.now_pos, origin.location_index)
	assert_true(player.is_working, "实际移动失败不得结束打工")
	assert_eq(player.work_turns_left, 2)
	assert_eq(player.current_work_index, 9)
	assert_true(hud.messages.has("【邻格探索】未移动。"))


func test_explorer_respects_scenery_ban_when_building_end_options() -> void:
	var fixture := _make_explorer_fixture()
	var player := fixture[&"player"] as ProfessionProbePlayer
	var target := fixture[&"target"] as MapSection
	target.type = MapSection.SectionType.风景
	EventManager.add_status(player, &"scenery_banned", 1)
	var request_count := {&"value": 0}
	var count_request := func(_request: ProfessionSectionChoiceRequest) -> void:
		request_count[&"value"] = int(request_count[&"value"]) + 1
	ProfessionManager.section_choice_requested.connect(count_request, CONNECT_ONE_SHOT)

	player._begin_profession_end_move()
	await get_tree().process_frame

	assert_eq(request_count[&"value"], 0, "禁止景区期间风景格不是合法探险终点")
	assert_eq(TurnManager.modal_resolution_depth, 0)
	if ProfessionManager.section_choice_requested.is_connected(count_request):
		ProfessionManager.section_choice_requested.disconnect(count_request)


func test_business_shop_opens_once_per_real_arrival_and_refreshes_once_each_visit() -> void:
	var map := _own(ProfessionProbeMap.new()) as ProfessionProbeMap
	add_child(map)
	var origin_coord := Vector3i.ZERO
	var shop_coord := 常量.MOVE[0]
	var origin := _add_section(map, origin_coord, MapSection.SectionType.一般, Vector2.ZERO)
	var shop := _add_section(map, shop_coord, MapSection.SectionType.商店, Vector2(24.0, 0.0))
	origin.is_occupied = true
	var hud := _own(ProfessionProbeHUD.new()) as ProfessionProbeHUD
	hud.default_font = load("res://arts/像素字体.ttf") as FontFile
	hud.btn_action = Button.new()
	hud.btn_food = Button.new()
	hud.btn_end_turn = Button.new()
	hud.add_child(hud.btn_action)
	hud.add_child(hud.btn_food)
	hud.add_child(hud.btn_end_turn)
	var panel := load("res://HUDs/商店弹窗.tscn").instantiate() as 商店弹窗
	_owned_nodes.append(panel)
	add_child(panel)
	assert_eq(panel.btn_refresh.anchor_top, 0.0, "刷新按钮应位于标题横带，而不是弹窗底部")
	assert_eq(panel.btn_refresh.anchor_bottom, 0.0)
	assert_eq(panel.btn_refresh.offset_left, -600.0)
	assert_eq(panel.btn_refresh.offset_top, 88.0)
	assert_eq(panel.btn_refresh.offset_right, -370.0)
	assert_eq(panel.btn_refresh.offset_bottom, 160.0)
	var shop_title := panel.get_node("标题") as Label
	var product_row := panel.get_node("HBoxContainer") as HBoxContainer
	assert_eq(shop_title.mouse_filter, Control.MOUSE_FILTER_IGNORE, "标题透明区域不得拦截刷新按钮点击")
	assert_lt(panel.btn_refresh.position.y + panel.btn_refresh.size.y, product_row.position.y, "刷新按钮不得挤入商品区域")
	panel.hud = hud
	hud.shop_panel = panel
	var player := ProfessionProbePlayer.new()
	_add_score_badge(player)
	map.add_child(player)
	player.player_name = "商业商店测试"
	player.player_types = PlayerClass.PlayerCharacter.商业博主
	player.map = map
	player.hud = hud
	player.onTurn = true
	player.now_pos = origin_coord
	player.current_energy = 6
	player.maxMove = 4
	var foods: Array[卡牌基类] = []
	for index: int in 9:
		foods.append(_make_food("货架%d" % index))
	ResourceManager.食物牌库.assign(foods)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.GameOn = true

	assert_true(await player.move_along_path([shop.global_position], 0, shop_coord))
	TurnManager.turn_timer.stop()
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	player.execute_tile_action()
	assert_eq(hud.shop_open_count, 1)
	assert_true(panel.visible)
	assert_true(panel.btn_refresh.visible)
	assert_false(panel.btn_refresh.disabled)
	panel._on_refresh_pressed()
	assert_true(panel._refresh_used_this_visit)
	assert_true(panel.btn_refresh.disabled)
	var refreshed_cards: Array[食物牌] = panel.shop_foods.duplicate()
	var deck_size_after_refresh: int = ResourceManager.食物牌库.size()
	panel._on_refresh_pressed()
	assert_eq(panel.shop_foods, refreshed_cards, "同次访问第二次刷新必须无效")
	assert_eq(ResourceManager.食物牌库.size(), deck_size_after_refresh)
	panel._on_leave()
	assert_false(get_tree().paused)

	player.execute_tile_action()
	assert_eq(hud.shop_open_count, 1, "停留在同一次到达不得重新打开商店")
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	player.maxMove = 2
	assert_true(await player.move_along_path([origin.global_position], 0, origin_coord))
	TurnManager.turn_timer.stop()
	player.maxMove = 1
	assert_true(await player.move_along_path([shop.global_position], 0, shop_coord))
	TurnManager.turn_timer.stop()
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	player.execute_tile_action()
	assert_eq(hud.shop_open_count, 2, "离开后再次普通到达应获得新的商店访问")
	assert_false(panel._refresh_used_this_visit)
	assert_false(panel.btn_refresh.disabled, "新一次访问应恢复一次免费刷新")
	panel._on_leave()


func test_all_in_blocks_current_turn_and_next_three_then_restores_skill() -> void:
	var player := _own(PlayerClass.new()) as PlayerClass
	player.player_name = "孤注一掷测试"
	player.player_types = PlayerClass.PlayerCharacter.美食博主
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	var card := load("res://Cards/事件牌/孤注一掷.tres") as 事件牌

	await EventManager.resolve_event(player, card)

	assert_eq(ProfessionManager.get_blocked_turns(player), 4)
	assert_false(ProfessionManager.is_skill_enabled(player), "触发事件的当前回合立即被封锁")
	assert_eq(ProfessionManager.get_food_use_limit(player), 1)
	var expected_remaining: Array[int] = [3, 2, 1, 0]
	for expected: int in expected_remaining:
		TurnManager.now_phase = TurnManager.TurnPhase.END
		await TurnManager.now_turn_end()
		TurnManager.turn_timer.stop()
		assert_eq(ProfessionManager.get_blocked_turns(player), expected)
		assert_eq(ProfessionManager.is_skill_enabled(player), expected == 0)
	assert_true(ProfessionManager.is_skill_enabled(player))
	assert_eq(ProfessionManager.get_food_use_limit(player), 3)


func _make_explorer_fixture(phase: TurnManager.TurnPhase = TurnManager.TurnPhase.END) -> Dictionary:
	var map := _own(ProfessionProbeMap.new()) as ProfessionProbeMap
	add_child(map)
	var origin_coord := Vector3i.ZERO
	var target_coord := 常量.MOVE[0]
	var occupied_coord := 常量.MOVE[1]
	var origin := _add_section(map, origin_coord, MapSection.SectionType.打工, Vector2.ZERO)
	var target := _add_section(map, target_coord, MapSection.SectionType.事件, Vector2(20.0, 0.0))
	var occupied := _add_section(map, occupied_coord, MapSection.SectionType.风景, Vector2(-20.0, 0.0))
	origin.is_occupied = true
	occupied.is_occupied = true
	var hud := _own(ProfessionProbeHUD.new()) as ProfessionProbeHUD
	hud.default_font = load("res://arts/像素字体.ttf") as FontFile
	hud.btn_action = Button.new()
	hud.btn_food = Button.new()
	hud.btn_end_turn = Button.new()
	hud.btn_view_toggle = TextureButton.new()
	hud.current_status = Label.new()
	hud.information = Label.new()
	hud.add_child(hud.btn_action)
	hud.add_child(hud.btn_food)
	hud.add_child(hud.btn_end_turn)
	hud.add_child(hud.btn_view_toggle)
	hud.add_child(hud.current_status)
	hud.add_child(hud.information)
	hud.map = map
	var player := ProfessionProbePlayer.new()
	_add_score_badge(player)
	map.add_child(player)
	player.player_name = "探险测试"
	player.player_types = PlayerClass.PlayerCharacter.探险博主
	player.map = map
	player.hud = hud
	player.onTurn = true
	player.player_index = 0
	player.now_pos = origin_coord
	player.position = origin.position
	player.arrival_id = 7
	player.last_normal_arrival_position = origin_coord
	player.last_action_arrival_position = origin_coord
	player.last_action_arrival_turn_epoch = TurnManager.get_turn_epoch()
	player.last_action_arrival_session_generation = TurnManager.get_session_generation()
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = phase
	TurnManager.GameOn = true
	TurnManager.modal_resolution_depth = 0
	return {
		&"map": map,
		&"hud": hud,
		&"player": player,
		&"origin": origin,
		&"target": target,
		&"occupied": occupied,
	}


func _add_section(
	map: MAP,
	coordinate: Vector3i,
	section_type: MapSection.SectionType,
	world_position: Vector2
) -> MapSection:
	var section := MapSection.new()
	section.location_index = coordinate
	section.type = section_type
	section.position = world_position
	_owned_nodes.append(section)
	map.grid_map[coordinate] = section
	return section


func _add_score_badge(player: PlayerClass) -> void:
	var badge := Node2D.new()
	badge.name = "ScoreBadge"
	var label := Label.new()
	label.name = "Score"
	badge.add_child(label)
	player.add_child(badge)


func _make_feiyi(display_name: String) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.region = 非遗牌.REGION.鄂州
	card.category = 非遗牌.CardCategory.手工技艺
	return card


func _make_food(display_name: String) -> 食物牌:
	var card := 食物牌.new()
	card.card_name = display_name
	return card


func _own(node: Node) -> Node:
	_owned_nodes.append(node)
	return node
