extends Node

signal profession_changed(first_player: PlayerClass, second_player: PlayerClass)
signal skill_triggered(player: PlayerClass, profession_id: StringName, message: String)
signal skill_state_changed(player: PlayerClass)
signal draw_choice_requested(request: ProfessionDrawRequest)
signal draw_choice_resolved(request_id: int, result: ProfessionDrawResult, timed_out: bool)
signal section_choice_requested(request: ProfessionSectionChoiceRequest)
signal section_choice_resolved(request_id: int, section: MapSection, timed_out: bool)

const CHOICE_TIMEOUT_SECONDS: float = 15.0
const BASE_FOOD_USE_LIMIT: int = 1
const BASE_WORK_ENERGY_COST: int = 1

const FOOD_BLOGGER: int = PlayerClass.PlayerCharacter.美食博主
const MAGIC_BLOGGER: int = PlayerClass.PlayerCharacter.魔术博主
const ADVENTURE_BLOGGER: int = PlayerClass.PlayerCharacter.探险博主
const BUSINESS_BLOGGER: int = PlayerClass.PlayerCharacter.商业博主
const TRAVEL_BLOGGER: int = PlayerClass.PlayerCharacter.旅行博主
const LIFE_BLOGGER: int = PlayerClass.PlayerCharacter.生活博主

const DEFINITION_PATHS: Array[String] = [
	"res://Cards/职业/美食博主.tres",
	"res://Cards/职业/魔术博主.tres",
	"res://Cards/职业/探险博主.tres",
	"res://Cards/职业/商业博主.tres",
	"res://Cards/职业/旅行博主.tres",
	"res://Cards/职业/生活博主.tres",
]
const SCENERY_REWARD_SOURCES: Array[StringName] = [
	&"normal",
	&"you_mu_cheng_huai",
	&"chen_jin_ti_yan",
]

var _definitions_by_type: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _definition_order: Array[ProfessionDefinition] = []
var _registered_players: Array[PlayerClass] = []
var _blocked_turns_by_player: Dictionary = {}
var _starting_bonus_applied: Dictionary = {}
var _session_token: int = 0

var _request_sequence: int = 0
var _pending_draw_request: ProfessionDrawRequest = null
var _completed_draw_results: Dictionary = {}
var _draw_choice_waiting: bool = false
var _draw_choice_timer: Timer = null

var _pending_section_request: ProfessionSectionChoiceRequest = null
var _completed_section_results: Dictionary = {}
var _section_choice_waiting: bool = false
var _section_choice_timer: Timer = null


func _ready() -> void:
	_load_definitions()
	_ensure_choice_timers()


func reset_for_new_game(players: Array[PlayerClass] = []) -> void:
	_ensure_initialized()
	_session_token += 1
	_cancel_pending_choices()
	_blocked_turns_by_player.clear()
	_starting_bonus_applied.clear()
	_registered_players.clear()
	for player: PlayerClass in players:
		register_player(player)


func reset_session() -> void:
	reset_for_new_game([])


func register_player(player: PlayerClass) -> bool:
	if player == null or not is_instance_valid(player) or _registered_players.has(player):
		return false
	_registered_players.append(player)
	return true


## 只在首回合开始前调用一次；后续职业互换不会补发或扣回。
func apply_starting_bonuses() -> void:
	for player: PlayerClass in _registered_players:
		if player == null or _starting_bonus_applied.has(player):
			continue
		_starting_bonus_applied[player] = true
		var definition := get_definition(player)
		var bonus := maxi(definition.starting_money_bonus, 0) if definition != null else 0
		if bonus <= 0:
			continue
		ResourceManager.modify_money(player, bonus, "职业技能：开局奖励")


func get_registered_players() -> Array[PlayerClass]:
	var result: Array[PlayerClass] = []
	result.assign(_registered_players)
	return result


func get_all_definitions() -> Array[ProfessionDefinition]:
	_ensure_initialized()
	var result: Array[ProfessionDefinition] = []
	result.assign(_definition_order)
	return result


func get_definition(player: PlayerClass) -> ProfessionDefinition:
	if player == null or not is_instance_valid(player):
		return null
	return get_definition_by_type(int(player.player_types))


func get_definition_by_type(profession_type: int) -> ProfessionDefinition:
	_ensure_initialized()
	return _definitions_by_type.get(profession_type) as ProfessionDefinition


func get_definition_by_id(profession_id: StringName) -> ProfessionDefinition:
	_ensure_initialized()
	return _definitions_by_id.get(profession_id) as ProfessionDefinition


## expected_profession 为 -1 时只检查当前职业存在且没有被封锁；传入职业枚举时还会核对职业身份。
func is_skill_enabled(player: PlayerClass, expected_profession: int = -1) -> bool:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null:
		return false
	if expected_profession >= 0 and int(player.player_types) != expected_profession:
		return false
	return get_blocked_turns(player) <= 0


## 当前触发回合计作第一个受影响回合；该玩家本回合结束时应立即调用
## on_player_turn_finished()，届时 4 会递减为 3。
func block_skill(player: PlayerClass, turns: int = 4) -> bool:
	if get_definition(player) == null or turns <= 0:
		return false
	var previous: int = get_blocked_turns(player)
	var next_value: int = maxi(previous, turns)
	if next_value == previous:
		return false
	_blocked_turns_by_player[player] = next_value
	skill_state_changed.emit(player)
	return true


func clear_skill_block(player: PlayerClass) -> bool:
	if player == null or not _blocked_turns_by_player.has(player):
		return false
	_blocked_turns_by_player.erase(player)
	skill_state_changed.emit(player)
	return true


func get_blocked_turns(player: PlayerClass) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	return maxi(int(_blocked_turns_by_player.get(player, 0)), 0)


func get_skill_blocked_turns(player: PlayerClass) -> int:
	return get_blocked_turns(player)


func on_player_turn_finished(player: PlayerClass) -> int:
	var remaining: int = get_blocked_turns(player)
	if remaining <= 0:
		return 0
	remaining -= 1
	if remaining <= 0:
		_blocked_turns_by_player.erase(player)
	else:
		_blocked_turns_by_player[player] = remaining
	skill_state_changed.emit(player)
	return remaining


func on_player_turn_ended(player: PlayerClass) -> int:
	return on_player_turn_finished(player)


func get_skill_state(player: PlayerClass) -> Dictionary:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null:
		return {}
	return {
		&"profession_id": definition.profession_id,
		&"profession_type": definition.profession_type,
		&"enabled": is_skill_enabled(player),
		&"blocked_turns": get_blocked_turns(player),
	}


func set_profession(player: PlayerClass, profession_type: int) -> bool:
	if player == null or get_definition_by_type(profession_type) == null:
		return false
	if int(player.player_types) == profession_type:
		return false
	player.player_types = profession_type as PlayerClass.PlayerCharacter
	player._init_character()
	profession_changed.emit(player, null)
	return true


## 职业身份互换为一个原子操作；技能封锁跟随玩家，不跟随职业。
func swap_professions(first_player: PlayerClass, second_player: PlayerClass) -> bool:
	if first_player == null or second_player == null or first_player == second_player:
		return false
	if get_definition(first_player) == null or get_definition(second_player) == null:
		return false
	var first_type: int = int(first_player.player_types)
	var second_type: int = int(second_player.player_types)
	if first_type == second_type:
		return false
	first_player.player_types = second_type as PlayerClass.PlayerCharacter
	second_player.player_types = first_type as PlayerClass.PlayerCharacter
	first_player._init_character()
	second_player._init_character()
	profession_changed.emit(first_player, second_player)
	return true


func get_food_use_limit(player: PlayerClass) -> int:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null or not is_skill_enabled(player):
		return BASE_FOOD_USE_LIMIT
	return maxi(definition.food_use_limit, BASE_FOOD_USE_LIMIT)


func get_draw_count(player: PlayerClass) -> int:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null or not is_skill_enabled(player):
		return 1
	return maxi(definition.draw_count, 1)


func can_reorder_draws(player: PlayerClass) -> bool:
	var definition: ProfessionDefinition = get_definition(player)
	return definition != null and definition.can_reorder_draws and is_skill_enabled(player)


func can_move_at_begin(player: PlayerClass) -> bool:
	var definition: ProfessionDefinition = get_definition(player)
	return definition != null and definition.can_move_at_begin and is_skill_enabled(player)


func can_move_at_end(player: PlayerClass) -> bool:
	var definition: ProfessionDefinition = get_definition(player)
	return definition != null and definition.can_move_at_end and is_skill_enabled(player)


func can_move_in_phase(player: PlayerClass, phase: TurnManager.TurnPhase) -> bool:
	match phase:
		TurnManager.TurnPhase.BEGIN:
			return can_move_at_begin(player)
		TurnManager.TurnPhase.END:
			return can_move_at_end(player)
		_:
			return false


func get_work_energy_cost(player: PlayerClass) -> int:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null or not is_skill_enabled(player):
		return BASE_WORK_ENERGY_COST
	return maxi(definition.work_energy_cost, 0)


func adjust_market_buy_price(player: PlayerClass, base_price: int) -> int:
	var safe_base_price: int = maxi(base_price, 0)
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null or not is_skill_enabled(player):
		return safe_base_price
	return ceili(float(safe_base_price) * clampf(definition.market_buy_multiplier, 0.0, 1.0))


func get_market_buy_price(player: PlayerClass, base_price: int) -> int:
	return adjust_market_buy_price(player, base_price)


func get_food_shop_refresh_limit(player: PlayerClass) -> int:
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null or not is_skill_enabled(player):
		return 0
	return maxi(definition.food_shop_refreshes, 0)


func notify_skill_triggered(player: PlayerClass, message: String) -> bool:
	if not is_skill_enabled(player):
		return false
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null:
		return false
	skill_triggered.emit(player, definition.profession_id, message)
	return true


func get_scenery_arrival_money(player: PlayerClass) -> int:
	if not is_skill_enabled(player, TRAVEL_BLOGGER):
		return 0
	var definition: ProfessionDefinition = get_definition(player)
	return maxi(definition.scenery_arrival_money, 0) if definition != null else 0


func adjust_section_movement_cost(player: PlayerClass, section: MapSection, base_cost: int) -> int:
	var safe_cost := maxi(base_cost, 0)
	if section == null or section.type != MapSection.SectionType.风景:
		return safe_cost
	if not is_skill_enabled(player, TRAVEL_BLOGGER):
		return safe_cost
	var definition: ProfessionDefinition = get_definition(player)
	if definition == null:
		return safe_cost
	return maxi(safe_cost - maxi(definition.scenery_movement_discount, 0), 0)


func record_scenery_arrival(
	player: PlayerClass,
	section: MapSection,
	source: StringName = &"normal"
) -> bool:
	if section == null or section.type != MapSection.SectionType.风景:
		return false
	if not SCENERY_REWARD_SOURCES.has(source):
		return false
	var reward: int = get_scenery_arrival_money(player)
	if reward <= 0:
		return false
	if not ResourceManager.modify_money(player, reward, "职业技能：旅行博主"):
		return false
	notify_skill_triggered(player, "到达风景区，积分点 +%d" % reward)
	return true


func request_draw_choice(
	player: PlayerClass,
	cards: Array,
	deck_kind: StringName
) -> ProfessionDrawResult:
	_ensure_initialized()
	if not is_skill_enabled(player, MAGIC_BLOGGER) or cards.is_empty() or _draw_choice_waiting:
		return ProfessionDrawResult.new(null, [], true)
	var definition: ProfessionDefinition = get_definition(player)
	var request := ProfessionDrawRequest.new(
		player,
		cards,
		deck_kind,
		definition.skill_name,
		definition.description
	)
	request.timeout_seconds = CHOICE_TIMEOUT_SECONDS
	var request_session: int = _session_token
	var ticket := InteractionCoordinator.begin_interaction(&"profession_draw", request.timeout_seconds, _resolve_draw_timeout, TurnManager.ModalResumePolicy.NO_RESUME, false, {"request": request})
	if ticket == null:
		return ProfessionDrawResult.new(null, [], true)
	request.request_id = ticket.interaction_id
	_request_sequence = maxi(_request_sequence, request.request_id)
	_pending_draw_request = request
	_draw_choice_waiting = true
	draw_choice_requested.emit(request)
	var interaction_result: InteractionResult = await InteractionCoordinator.await_result(ticket)
	_draw_choice_waiting = false
	if request_session != _session_token:
		return ProfessionDrawResult.new(null, [], true)
	var result: ProfessionDrawResult = interaction_result.value as ProfessionDrawResult
	if _pending_draw_request == request:
		_pending_draw_request = null
	if result == null:
		result = ProfessionDrawResult.new(null, [], true)
	draw_choice_resolved.emit(request.request_id, result, interaction_result.timed_out)
	# 请求只服务于当前弹窗；结束后立即解除对玩家和展示牌的引用，避免异步栈
	# 在本局最后一次职业抽牌后延长 PlayerClass 的生命周期。
	request.player = null
	request.cards.clear()
	if not result.cancelled and result.selected_card != null:
		notify_skill_triggered(player, "调整牌堆")
	return result

func _resolve_draw_timeout(ticket: InteractionTicket) -> ProfessionDrawResult:
	var request: ProfessionDrawRequest = ticket.metadata.get("request") as ProfessionDrawRequest if ticket != null else null
	if request == null or request.cards.is_empty():
		return ProfessionDrawResult.new(null, [], true)
	var selected_card = request.cards[0]
	var return_order: Array = request.cards.duplicate()
	return_order.remove_at(0)
	return ProfessionDrawResult.new(selected_card, return_order)

func _resolve_optional_section_timeout(_ticket: InteractionTicket):
	return null


func submit_draw_choice(
	request_id: int,
	selected_card,
	return_order: Array
) -> bool:
	if not _draw_choice_waiting or _pending_draw_request == null:
		return false
	if request_id != _pending_draw_request.request_id:
		return false
	if not _is_valid_draw_result(_pending_draw_request.cards, selected_card, return_order):
		return false
	return InteractionCoordinator.submit(request_id, ProfessionDrawResult.new(selected_card, return_order))

## 仅同步弹窗中的当前排列，供超时按玩家最后看到的第一张处理；不会提前提交选择。
func update_draw_choice_order(request_id: int, ordered_cards: Array) -> bool:
	if not _draw_choice_waiting or _pending_draw_request == null:
		return false
	if request_id != _pending_draw_request.request_id:
		return false
	var unmatched: Array = _pending_draw_request.cards.duplicate()
	if ordered_cards.size() != unmatched.size():
		return false
	for card in ordered_cards:
		var index: int = unmatched.find(card)
		if index < 0:
			return false
		unmatched.remove_at(index)
	_pending_draw_request.cards = ordered_cards.duplicate()
	InteractionCoordinator.update_preview(request_id, ordered_cards.duplicate())
	return true


func get_draw_choice_time_left(request_id: int = -1) -> float:
	if not _draw_choice_waiting or _pending_draw_request == null:
		return 0.0
	if request_id >= 0 and request_id != _pending_draw_request.request_id:
		return 0.0
	return InteractionCoordinator.get_time_left(request_id)


func get_pending_draw_request() -> ProfessionDrawRequest:
	return _pending_draw_request


func request_section_choice(
	player: PlayerClass,
	options: Array[MapSection],
	source_name: String,
	source_description: String
) -> MapSection:
	_ensure_initialized()
	if not is_skill_enabled(player, ADVENTURE_BLOGGER) or options.is_empty() or _section_choice_waiting:
		return null
	var legal_options: Array[MapSection] = []
	for section: MapSection in options:
		if section != null and not legal_options.has(section):
			legal_options.append(section)
	if legal_options.is_empty():
		return null
	var definition: ProfessionDefinition = get_definition(player)
	var request := ProfessionSectionChoiceRequest.new(
		player,
		legal_options,
		source_name if not source_name.is_empty() else definition.skill_name,
		source_description if not source_description.is_empty() else definition.description
	)
	request.timeout_seconds = CHOICE_TIMEOUT_SECONDS
	var request_session: int = _session_token
	var ticket := InteractionCoordinator.begin_interaction(&"profession_section", request.timeout_seconds, _resolve_optional_section_timeout, TurnManager.ModalResumePolicy.NO_RESUME, false, {"request": request})
	if ticket == null:
		return null
	request.request_id = ticket.interaction_id
	_request_sequence = maxi(_request_sequence, request.request_id)
	_pending_section_request = request
	_section_choice_waiting = true
	section_choice_requested.emit(request)
	var interaction_result: InteractionResult = await InteractionCoordinator.await_result(ticket)
	_section_choice_waiting = false
	if request_session != _session_token:
		return null
	var result: MapSection = interaction_result.value as MapSection
	if _pending_section_request == request:
		_pending_section_request = null
	section_choice_resolved.emit(request.request_id, result, interaction_result.timed_out)
	request.player = null
	request.options.clear()
	if result != null:
		notify_skill_triggered(player, "移动至相邻格子")
	return result


func submit_section_choice(request_id: int, section: MapSection) -> bool:
	if not _section_choice_waiting or _pending_section_request == null:
		return false
	if request_id != _pending_section_request.request_id:
		return false
	if section != null and not _pending_section_request.options.has(section):
		return false
	return InteractionCoordinator.submit(request_id, section)


func get_section_choice_time_left(request_id: int = -1) -> float:
	if not _section_choice_waiting or _pending_section_request == null:
		return 0.0
	if request_id >= 0 and request_id != _pending_section_request.request_id:
		return 0.0
	return InteractionCoordinator.get_time_left(request_id)


func get_pending_section_choice_request() -> ProfessionSectionChoiceRequest:
	return _pending_section_request


func _load_definitions() -> void:
	_definitions_by_type.clear()
	_definitions_by_id.clear()
	_definition_order.clear()
	for resource_path: String in DEFINITION_PATHS:
		var definition: ProfessionDefinition = ResourceLoader.load(resource_path) as ProfessionDefinition
		if definition == null:
			push_error("职业资源无法加载：%s" % resource_path)
			continue
		if definition.profession_id.is_empty() or definition.profession_name.is_empty():
			push_error("职业资源缺少稳定 ID 或名称：%s" % resource_path)
			continue
		var profession_type: int = int(definition.profession_type)
		if _definitions_by_type.has(profession_type):
			push_error("职业类型重复：%s" % definition.profession_name)
			continue
		if _definitions_by_id.has(definition.profession_id):
			push_error("职业 ID 重复：%s" % definition.profession_id)
			continue
		_definitions_by_type[profession_type] = definition
		_definitions_by_id[definition.profession_id] = definition
		_definition_order.append(definition)


func _ensure_initialized() -> void:
	if _definition_order.is_empty():
		_load_definitions()
	_ensure_choice_timers()


func _ensure_choice_timers() -> void:
	if _draw_choice_timer == null:
		_draw_choice_timer = Timer.new()
		_draw_choice_timer.one_shot = true
		_draw_choice_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_draw_choice_timer)
		_draw_choice_timer.timeout.connect(_on_draw_choice_timeout)
	if _section_choice_timer == null:
		_section_choice_timer = Timer.new()
		_section_choice_timer.one_shot = true
		_section_choice_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_section_choice_timer)
		_section_choice_timer.timeout.connect(_on_section_choice_timeout)


func _is_valid_draw_result(cards: Array, selected_card, return_order: Array) -> bool:
	if selected_card == null or not cards.has(selected_card):
		return false
	if return_order.size() != cards.size() - 1:
		return false
	var unmatched: Array = cards.duplicate()
	unmatched.erase(selected_card)
	for card in return_order:
		var index: int = unmatched.find(card)
		if index < 0:
			return false
		unmatched.remove_at(index)
	return unmatched.is_empty()


func _resolve_draw_choice(result: ProfessionDrawResult, timed_out: bool) -> void:
	if not _draw_choice_waiting or _pending_draw_request == null:
		return
	if timed_out:
		InteractionCoordinator.resolve_timeout(_pending_draw_request.request_id)
	else:
		InteractionCoordinator.submit(_pending_draw_request.request_id, result)


func _on_draw_choice_timeout() -> void:
	if not _draw_choice_waiting or _pending_draw_request == null:
		return
	InteractionCoordinator.resolve_timeout(_pending_draw_request.request_id)


func _resolve_section_choice(section: MapSection, timed_out: bool) -> void:
	if not _section_choice_waiting or _pending_section_request == null:
		return
	if timed_out:
		InteractionCoordinator.resolve_timeout(_pending_section_request.request_id)
	else:
		InteractionCoordinator.submit(_pending_section_request.request_id, section)


func _on_section_choice_timeout() -> void:
	if _pending_section_request != null:
		InteractionCoordinator.resolve_timeout(_pending_section_request.request_id)


func _cancel_pending_choices() -> void:
	var cancelled_draw_request_id: int = -1
	var cancelled_section_request_id: int = -1
	if _draw_choice_waiting and _pending_draw_request != null:
		cancelled_draw_request_id = _pending_draw_request.request_id
		InteractionCoordinator.cancel(cancelled_draw_request_id, &"profession_reset")
	if _section_choice_waiting and _pending_section_request != null:
		cancelled_section_request_id = _pending_section_request.request_id
		InteractionCoordinator.cancel(cancelled_section_request_id, &"profession_reset")
	if _draw_choice_timer != null:
		_draw_choice_timer.stop()
	if _section_choice_timer != null:
		_section_choice_timer.stop()
	_draw_choice_waiting = false
	_section_choice_waiting = false
	_pending_draw_request = null
	_pending_section_request = null
	_completed_draw_results.clear()
	_completed_section_results.clear()
	# 取消必须先完成状态清理再通知 UI，避免信号回调重入并再次提交旧请求。
	if cancelled_draw_request_id >= 0:
		var cancelled_result := ProfessionDrawResult.new(null, [], true)
		draw_choice_resolved.emit(cancelled_draw_request_id, cancelled_result, false)
	if cancelled_section_request_id >= 0:
		section_choice_resolved.emit(cancelled_section_request_id, null, false)
