extends Node

signal achievement_claimed(player: PlayerClass, card: 成就牌)
signal achievement_destroyed(previous_owner: PlayerClass, card: 成就牌, replacement: 成就牌)
signal achievement_progress_changed(player: PlayerClass, achievement_id: StringName, current: int, target: int)

enum AvailabilityState {
	AVAILABLE,
	CLAIMED,
	DESTROYED,
}

const ACHIEVEMENT_DIR: String = "res://Cards/成就牌"
const MAP_SCENE_PATH: String = "res://地图/map.tscn"
const SHENNONGJIA_FEIYI_DIR: String = "res://Cards/非遗牌/神农架"

const ID_YOU_SHAN_WAN_SHUI: StringName = &"you_shan_wan_shui"
const ID_TAO_TIE: StringName = &"tao_tie"
const ID_DA_WEI_DAI: StringName = &"da_wei_dai"
const ID_YE_REN: StringName = &"ye_ren"
const ID_CHAO_YUE_REN_LEI: StringName = &"chao_yue_ren_lei"
const ID_XING_YUN_ER: StringName = &"xing_yun_er"

const PROGRESS_FOOD: StringName = &"food_consumed"
const PROGRESS_EVENTS: StringName = &"events_triggered"
const PROGRESS_MAX_ENERGY: StringName = &"max_energy_reached"
const PROGRESS_SCENERY: StringName = &"scenery_check_ins"
const PROGRESS_SHENNONGJIA_SCENERY: StringName = &"shennongjia_scenery_check_ins"

var _definitions: Dictionary[StringName, 成就牌] = {}
var _definition_order: Array[StringName] = []
var _states: Dictionary[StringName, AvailabilityState] = {}
var _owners: Dictionary[StringName, PlayerClass] = {}
var _registered_players: Array[PlayerClass] = []
var _owned_by_player: Dictionary[PlayerClass, Array] = {}
var _progress_by_player: Dictionary[PlayerClass, Dictionary] = {}
var _required_shennongjia_feiyi_paths: Dictionary[String, bool] = {}
var _required_shennongjia_scenery_ids: Dictionary[StringName, bool] = {}
var _collection_requirements_loaded: bool = false


func _ready() -> void:
	_load_definitions()
	_refresh_collection_requirements()
	reset_for_new_game([])
	_connect_gameplay_signals()


func reset_for_new_game(players: Array[PlayerClass] = []) -> void:
	if _definitions.is_empty():
		_load_definitions()
	if not _collection_requirements_loaded:
		_refresh_collection_requirements()
	_registered_players.clear()
	_owned_by_player.clear()
	_progress_by_player.clear()
	_owners.clear()
	_states.clear()
	for achievement_id: StringName in _definition_order:
		_states[achievement_id] = AvailabilityState.AVAILABLE
	for player: PlayerClass in players:
		_register_player(player)


func register_player(player: PlayerClass) -> bool:
	if player == null or _registered_players.has(player):
		return false
	_register_player(player)
	return true


func bind_map(map: MAP) -> void:
	if map == null:
		return
	var actual_ids: Dictionary[StringName, bool] = {}
	_collect_shennongjia_scenery_into(map, actual_ids)
	_required_shennongjia_scenery_ids = actual_ids
	for player: PlayerClass in _registered_players:
		evaluate_collection_achievements(player)


func get_all_achievements() -> Array[成就牌]:
	var result: Array[成就牌] = []
	for achievement_id: StringName in _definition_order:
		var card: 成就牌 = _definitions.get(achievement_id)
		if card != null:
			result.append(card)
	return result


func get_achievement(achievement_id: StringName) -> 成就牌:
	return _definitions.get(achievement_id)


func get_achievement_state(achievement_id: StringName) -> AvailabilityState:
	return _states.get(achievement_id, AvailabilityState.DESTROYED)


func get_achievement_owner(achievement_id: StringName) -> PlayerClass:
	return _owners.get(achievement_id)


func get_owned_achievements(player: PlayerClass) -> Array[成就牌]:
	var result: Array[成就牌] = []
	if not _owned_by_player.has(player):
		return result
	for value: Variant in _owned_by_player[player]:
		if value is 成就牌:
			result.append(value as 成就牌)
	return result


func get_achievement_score(player: PlayerClass) -> int:
	var total: int = 0
	for card: 成就牌 in get_owned_achievements(player):
		total += card.score_value
	return total


func get_progress(player: PlayerClass, achievement_id: StringName) -> Dictionary:
	var card: 成就牌 = _definitions.get(achievement_id)
	if card == null or not _is_registered_player(player):
		return {}
	var progress: Dictionary = _progress_by_player[player]
	var current: int = 0
	var target: int = card.threshold
	var result: Dictionary = {}
	match achievement_id:
		ID_YOU_SHAN_WAN_SHUI:
			current = _get_id_set(progress, PROGRESS_SCENERY).size()
		ID_TAO_TIE, ID_DA_WEI_DAI:
			current = int(progress.get(PROGRESS_FOOD, 0))
		ID_CHAO_YUE_REN_LEI:
			current = int(progress.get(PROGRESS_MAX_ENERGY, 0))
		ID_XING_YUN_ER:
			current = int(progress.get(PROGRESS_EVENTS, 0))
		ID_YE_REN:
			var feiyi_current: int = _count_owned_required_shennongjia_feiyi(player)
			var feiyi_target: int = _required_shennongjia_feiyi_paths.size()
			var scenery_current: int = _count_required_scenery_check_ins(progress)
			var scenery_target: int = _required_shennongjia_scenery_ids.size()
			current = int(feiyi_target > 0 and feiyi_current >= feiyi_target) + int(scenery_target > 0 and scenery_current >= scenery_target)
			target = 2
			result[&"feiyi_current"] = feiyi_current
			result[&"feiyi_target"] = feiyi_target
			result[&"scenery_current"] = scenery_current
			result[&"scenery_target"] = scenery_target
		_:
			return {}
	result[&"current"] = current
	result[&"target"] = target
	result[&"state"] = get_achievement_state(achievement_id)
	result[&"owner"] = get_achievement_owner(achievement_id)
	result[&"completed"] = get_achievement_owner(achievement_id) == player
	return result


func record_food_consumed(player: PlayerClass, card: 食物牌) -> void:
	if not _is_registered_player(player) or card == null:
		return
	var progress: Dictionary = _progress_by_player[player]
	progress[PROGRESS_FOOD] = int(progress.get(PROGRESS_FOOD, 0)) + 1
	var count: int = int(progress[PROGRESS_FOOD])
	_emit_progress(player, ID_TAO_TIE, count)
	_emit_progress(player, ID_DA_WEI_DAI, count)
	if count >= _threshold_for(ID_TAO_TIE):
		_try_claim(player, ID_TAO_TIE)
	if count >= _threshold_for(ID_DA_WEI_DAI):
		_try_claim(player, ID_DA_WEI_DAI)


func record_scenery_check_in(player: PlayerClass, section: MapSection) -> bool:
	if not _is_registered_player(player) or section == null or section.type != MapSection.SectionType.风景:
		return false
	var progress: Dictionary = _progress_by_player[player]
	var scenery_ids: Dictionary = _get_id_set(progress, PROGRESS_SCENERY)
	var scenery_id: StringName = _section_id(section)
	if scenery_ids.has(scenery_id):
		return false
	scenery_ids[scenery_id] = true
	progress[PROGRESS_SCENERY] = scenery_ids
	if section.region == MapSection.REGION.神农架:
		var shennongjia_ids: Dictionary = _get_id_set(progress, PROGRESS_SHENNONGJIA_SCENERY)
		shennongjia_ids[scenery_id] = true
		progress[PROGRESS_SHENNONGJIA_SCENERY] = shennongjia_ids
	_emit_progress(player, ID_YOU_SHAN_WAN_SHUI, scenery_ids.size())
	if scenery_ids.size() >= _threshold_for(ID_YOU_SHAN_WAN_SHUI):
		_try_claim(player, ID_YOU_SHAN_WAN_SHUI)
	evaluate_collection_achievements(player)
	return true


func record_gameplay_event(player: PlayerClass, card: 事件牌) -> void:
	if not _is_registered_player(player) or card == null:
		return
	var progress: Dictionary = _progress_by_player[player]
	progress[PROGRESS_EVENTS] = int(progress.get(PROGRESS_EVENTS, 0)) + 1
	var count: int = int(progress[PROGRESS_EVENTS])
	_emit_progress(player, ID_XING_YUN_ER, count)
	if count >= _threshold_for(ID_XING_YUN_ER):
		_try_claim(player, ID_XING_YUN_ER)


func record_energy_reached(player: PlayerClass, current_energy: int = -1) -> void:
	if not _is_registered_player(player):
		return
	var energy: int = player.current_energy if current_energy < 0 else current_energy
	var progress: Dictionary = _progress_by_player[player]
	var previous_max: int = int(progress.get(PROGRESS_MAX_ENERGY, 0))
	if energy <= previous_max:
		return
	progress[PROGRESS_MAX_ENERGY] = energy
	_emit_progress(player, ID_CHAO_YUE_REN_LEI, energy)
	if energy >= _threshold_for(ID_CHAO_YUE_REN_LEI):
		_try_claim(player, ID_CHAO_YUE_REN_LEI)


func evaluate_player(player: PlayerClass) -> void:
	if not _is_registered_player(player):
		return
	record_energy_reached(player, player.current_energy)
	evaluate_collection_achievements(player)


func evaluate_collection_achievements(player: PlayerClass) -> void:
	if not _is_registered_player(player):
		return
	var progress: Dictionary = _progress_by_player[player]
	var feiyi_current: int = _count_owned_required_shennongjia_feiyi(player)
	var feiyi_target: int = _required_shennongjia_feiyi_paths.size()
	var scenery_current: int = _count_required_scenery_check_ins(progress)
	var scenery_target: int = _required_shennongjia_scenery_ids.size()
	var completed_parts: int = int(feiyi_target > 0 and feiyi_current >= feiyi_target) + int(scenery_target > 0 and scenery_current >= scenery_target)
	_emit_progress(player, ID_YE_REN, completed_parts, 2)
	if completed_parts == 2:
		_try_claim(player, ID_YE_REN)


func record_national_task_completed(_player: PlayerClass, _task_id: StringName) -> bool:
	return false


func _connect_gameplay_signals() -> void:
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	if resource_manager != null:
		_connect_signal_once(resource_manager, &"energy_changed", _on_energy_changed)
		_connect_signal_once(resource_manager, &"feiyi_hand_changed", _on_feiyi_hand_changed)
	var event_manager: Node = get_node_or_null("/root/EventManager")
	if event_manager != null:
		_connect_signal_once(event_manager, &"gameplay_event_triggered", _on_gameplay_event_triggered)


func _connect_signal_once(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _on_energy_changed(player: PlayerClass, _previous_energy: int, current_energy: int, _reason: String) -> void:
	record_energy_reached(player, current_energy)


func _on_feiyi_hand_changed(player: PlayerClass) -> void:
	evaluate_collection_achievements(player)


func _on_gameplay_event_triggered(player: PlayerClass, card: 事件牌) -> void:
	record_gameplay_event(player, card)


func _load_definitions() -> void:
	_definitions.clear()
	_definition_order.clear()
	var file_names: PackedStringArray = DirAccess.get_files_at(ACHIEVEMENT_DIR)
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".tres.remap"):
			continue
		var resource_path: String = ACHIEVEMENT_DIR.path_join(file_name.trim_suffix(".remap"))
		var card: 成就牌 = ResourceLoader.load(resource_path) as 成就牌
		if card == null:
			push_error("成就资源无法加载：%s" % resource_path)
			continue
		if card.achievement_id.is_empty():
			push_error("成就资源缺少稳定 ID：%s" % resource_path)
			continue
		if _definitions.has(card.achievement_id):
			push_error("成就 ID 重复：%s" % card.achievement_id)
			continue
		_definitions[card.achievement_id] = card
		_definition_order.append(card.achievement_id)


func _refresh_collection_requirements() -> void:
	_required_shennongjia_feiyi_paths.clear()
	for file_name: String in DirAccess.get_files_at(SHENNONGJIA_FEIYI_DIR):
		if not file_name.ends_with(".tres") and not file_name.ends_with(".tres.remap"):
			continue
		var resource_path: String = SHENNONGJIA_FEIYI_DIR.path_join(file_name.trim_suffix(".remap"))
		var card: 非遗牌 = ResourceLoader.load(resource_path) as 非遗牌
		if card != null and card.region == 非遗牌.REGION.神农架:
			_required_shennongjia_feiyi_paths[resource_path] = true
	_required_shennongjia_scenery_ids.clear()
	var packed_map: PackedScene = ResourceLoader.load(MAP_SCENE_PATH) as PackedScene
	if packed_map == null:
		_collection_requirements_loaded = true
		return
	var map_root: Node = packed_map.instantiate()
	_collect_shennongjia_scenery(map_root)
	map_root.free()
	_collection_requirements_loaded = true


func _collect_shennongjia_scenery(node: Node) -> void:
	_collect_shennongjia_scenery_into(node, _required_shennongjia_scenery_ids)


func _collect_shennongjia_scenery_into(node: Node, target: Dictionary[StringName, bool]) -> void:
	if node is MapSection:
		var section: MapSection = node as MapSection
		if section.region == MapSection.REGION.神农架 and section.type == MapSection.SectionType.风景:
			target[_section_id(section)] = true
	for child: Node in node.get_children():
		_collect_shennongjia_scenery_into(child, target)


func _register_player(player: PlayerClass) -> void:
	if player == null or _registered_players.has(player):
		return
	_registered_players.append(player)
	_owned_by_player[player] = []
	_progress_by_player[player] = {
		PROGRESS_FOOD: 0,
		PROGRESS_EVENTS: 0,
		PROGRESS_MAX_ENERGY: 0,
		PROGRESS_SCENERY: {},
		PROGRESS_SHENNONGJIA_SCENERY: {},
	}


func _is_registered_player(player: PlayerClass) -> bool:
	return player != null and _registered_players.has(player) and is_instance_valid(player)


func _try_claim(player: PlayerClass, achievement_id: StringName) -> bool:
	if not _is_registered_player(player) or get_achievement_state(achievement_id) != AvailabilityState.AVAILABLE:
		return false
	var card: 成就牌 = _definitions.get(achievement_id)
	if card == null:
		return false
	var destroyed_card: 成就牌 = null
	var previous_owner: PlayerClass = null
	if not card.replaces_achievement_id.is_empty():
		destroyed_card = _definitions.get(card.replaces_achievement_id)
		if destroyed_card != null and get_achievement_state(card.replaces_achievement_id) != AvailabilityState.DESTROYED:
			previous_owner = _owners.get(card.replaces_achievement_id)
			if previous_owner != null and _owned_by_player.has(previous_owner):
				_owned_by_player[previous_owner].erase(destroyed_card)
			_states[card.replaces_achievement_id] = AvailabilityState.DESTROYED
			_owners.erase(card.replaces_achievement_id)
	_states[achievement_id] = AvailabilityState.CLAIMED
	_owners[achievement_id] = player
	_owned_by_player[player].append(card)
	if previous_owner != null and previous_owner != player and is_instance_valid(previous_owner):
		ResourceManager.calculate_victory_score(previous_owner)
	ResourceManager.calculate_victory_score(player)
	if destroyed_card != null:
		achievement_destroyed.emit(previous_owner, destroyed_card, card)
	achievement_claimed.emit(player, card)
	return true


func _threshold_for(achievement_id: StringName) -> int:
	var card: 成就牌 = _definitions.get(achievement_id)
	return card.threshold if card != null else 1 << 30


func _emit_progress(player: PlayerClass, achievement_id: StringName, current: int, target_override: int = -1) -> void:
	var target: int = target_override if target_override >= 0 else _threshold_for(achievement_id)
	achievement_progress_changed.emit(player, achievement_id, current, target)


func _get_id_set(progress: Dictionary, key: StringName) -> Dictionary:
	var value: Variant = progress.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _section_id(section: MapSection) -> StringName:
	return StringName("%d,%d,%d" % [section.location_index.x, section.location_index.y, section.location_index.z])


func _count_owned_required_shennongjia_feiyi(player: PlayerClass) -> int:
	var owned_paths: Dictionary[String, bool] = {}
	for card: 非遗牌 in ResourceManager.get_effective_feiyi_cards(player):
		if card != null and _required_shennongjia_feiyi_paths.has(card.resource_path):
			owned_paths[card.resource_path] = true
	return owned_paths.size()


func _count_required_scenery_check_ins(progress: Dictionary) -> int:
	var checked_ids: Dictionary = _get_id_set(progress, PROGRESS_SHENNONGJIA_SCENERY)
	var result: int = 0
	for scenery_id: StringName in _required_shennongjia_scenery_ids:
		if checked_ids.has(scenery_id):
			result += 1
	return result
