extends GutTest

var _deck_backup: Array[事件牌]
var _discard_backup: Array[事件牌]
var _player: PlayerClass
var _section: MapSection
var _map: MAP

func before_each() -> void:
	_deck_backup = ResourceManager.事件牌库.duplicate()
	_discard_backup = ResourceManager.事件弃牌堆.duplicate()
	ResourceManager.事件牌库.assign([load("res://Cards/事件牌/精疲力尽.tres") as 事件牌])
	ResourceManager.事件弃牌堆.clear()
	_player = PlayerClass.new()
	_player.player_name = "测试玩家"
	_player.current_energy = 6
	_section = MapSection.new()
	_section.type = MapSection.SectionType.事件
	_section.location_index = Vector3i.ZERO
	_map = MAP.new()
	_map.add_child(_section)
	_map.grid_map[_section.location_index] = _section
	_player.map = _map
	_player.now_pos = _section.location_index
	_player.arrival_id = 1
	_player.last_normal_arrival_position = _section.location_index
	TurnManager.map = _map
	TurnManager.players.assign([_player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_turn = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	_player.last_action_arrival_position = _section.location_index
	_player.last_action_arrival_turn_epoch = TurnManager.get_turn_epoch()
	_player.last_action_arrival_session_generation = TurnManager.get_session_generation()
	EventManager.reset_for_new_game()
	EventManager.auto_resolve_choices = true
	EventManager.bind_runtime(null, null)

func after_each() -> void:
	ResourceManager.事件牌库.assign(_deck_backup)
	ResourceManager.事件弃牌堆.assign(_discard_backup)
	TurnManager.GameOn = false
	TurnManager.players.clear()
	TurnManager.map = null
	EventManager.reset_for_new_game()
	_player.free()
	_map.free()

func test_arrival_event_resolves_once_and_keeps_action_phase() -> void:
	await EventManager.trigger_arrival_event(_player, _section, 1)
	assert_eq(_player.current_energy, 3)
	assert_eq(_player.last_resolved_event_arrival_id, 1)
	assert_eq(ResourceManager.事件弃牌堆.size(), 1)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)
	assert_gt(TurnManager.turn_timer.time_left, 14.0)
	await EventManager.trigger_arrival_event(_player, _section, 1)
	assert_eq(_player.current_energy, 3, "相同到达标识不能重复触发")

func test_empty_event_deck_is_a_noop() -> void:
	ResourceManager.事件牌库.clear()
	_player.arrival_id = 2
	await EventManager.trigger_arrival_event(_player, _section, 2)
	assert_eq(_player.current_energy, 6)
	assert_eq(ResourceManager.事件弃牌堆.size(), 0)

func test_event_teleport_does_not_create_a_new_arrival_trigger() -> void:
	var destination := MapSection.new()
	destination.type = MapSection.SectionType.事件
	destination.location_index = Vector3i(1, -1, 0)
	_map.add_child(destination)
	_map.grid_map[destination.location_index] = destination
	_player.arrival_id = 7
	_player.last_resolved_event_arrival_id = 6
	_player.last_normal_arrival_position = _section.location_index
	_player.last_action_arrival_position = _section.location_index
	_player.last_action_arrival_turn_epoch = TurnManager.get_turn_epoch()
	_player.last_action_arrival_session_generation = TurnManager.get_session_generation()
	EventManager._teleport_player(_player, destination)
	assert_eq(_player.now_pos, destination.location_index)
	assert_eq(_player.arrival_id, 7, "事件传送不会伪造一次实际移动到达")
	await EventManager.trigger_arrival_event(_player, destination, _player.arrival_id)
	assert_eq(ResourceManager.事件弃牌堆.size(), 0, "传送目标不是普通移动的实际到达格，不能连锁触发")

func test_juan_yi_acceptance_closes_modal_before_ending_action() -> void:
	var card := load("res://Cards/事件牌/倦艺休整.tres") as 事件牌
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.prompt.begins_with("是否跳过"):
			return true
		return request.options[0]
	await EventManager.resolve_event(_player, card)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.END)
	assert_lt(TurnManager.turn_timer.time_left, 2.0, "跳过行动后不得误启15秒ACTION计时")

func test_juan_yi_refusal_keeps_action_and_resets_full_timer() -> void:
	var card := load("res://Cards/事件牌/倦艺休整.tres") as 事件牌
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.prompt.begins_with("是否跳过"):
			return false
		return request.options[0]
	await EventManager.resolve_event(_player, card)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)
	assert_gt(TurnManager.turn_timer.time_left, 14.0)

func test_ri_xing_qian_li_is_optional_and_no_selection_keeps_position() -> void:
	var destination := MapSection.new()
	destination.type = MapSection.SectionType.一般
	destination.location_index = Vector3i(1, -1, 0)
	_map.add_child(destination)
	_map.grid_map[destination.location_index] = destination
	var original_position := _player.now_pos
	var observed := {"grid_optional": false, "summary": ""}
	var capture_summary := func(_finished_player: PlayerClass, _card: 事件牌, event_summary: String) -> void:
		observed["summary"] = event_summary
	EventManager.event_finished.connect(capture_summary, CONNECT_ONE_SHOT)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.kind == EventChoiceRequest.ChoiceKind.格子:
			observed["grid_optional"] = request.optional
			return null
		return request.options[0]
	var card := load("res://Cards/事件牌/日行千里.tres") as 事件牌

	await EventManager.resolve_event(_player, card)

	assert_true(bool(observed["grid_optional"]))
	assert_eq(_player.now_pos, original_position, "日行千里未选择时不得默认传送")
	assert_true(String(observed["summary"]).ends_with("无事发生！"))
