extends GutTest

var _first: PlayerClass
var _second: PlayerClass
var _required_feiyi_backup: Dictionary
var _required_scenery_backup: Dictionary


func before_each() -> void:
	_required_feiyi_backup = AchievementManager._required_shennongjia_feiyi_paths.duplicate(true)
	_required_scenery_backup = AchievementManager._required_shennongjia_scenery_ids.duplicate(true)
	_first = PlayerClass.new()
	_first.player_name = "成就测试P1"
	_second = PlayerClass.new()
	_second.player_name = "成就测试P2"
	var players: Array[PlayerClass] = [_first, _second]
	AchievementManager.reset_for_new_game(players)


func after_each() -> void:
	AchievementManager._required_shennongjia_feiyi_paths = _required_feiyi_backup.duplicate(true)
	AchievementManager._required_shennongjia_scenery_ids = _required_scenery_backup.duplicate(true)
	AchievementManager.reset_for_new_game([])
	_first.free()
	_second.free()


func test_only_first_player_claims_lucky_achievement() -> void:
	_record_unique_events(_first, 5, "first")
	_record_unique_events(_second, 5, "second")
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_XING_YUN_ER), _first)
	assert_eq(AchievementManager.get_achievement_state(AchievementManager.ID_XING_YUN_ER), AchievementManager.AvailabilityState.CLAIMED)
	assert_eq(AchievementManager.get_achievement_score(_first), 3)
	assert_eq(AchievementManager.get_achievement_score(_second), 0)


func test_every_definition_is_globally_unique_and_repeat_evaluation_is_idempotent() -> void:
	var all_ids: Array[StringName] = [
		AchievementManager.ID_YOU_SHAN_WAN_SHUI,
		AchievementManager.ID_TAO_TIE,
		AchievementManager.ID_DA_WEI_DAI,
		AchievementManager.ID_YE_REN,
		AchievementManager.ID_CHAO_YUE_REN_LEI,
		AchievementManager.ID_XING_YUN_ER,
	]
	for achievement_id: StringName in all_ids:
		var players: Array[PlayerClass] = [_first, _second]
		AchievementManager.reset_for_new_game(players)
		assert_true(AchievementManager._try_claim(_first, achievement_id), str(achievement_id))
		assert_false(AchievementManager._try_claim(_first, achievement_id), "本人重复评估不得重复领取")
		assert_false(AchievementManager._try_claim(_second, achievement_id), "其他玩家不得领取已被占用成就")
		assert_eq(AchievementManager.get_achievement_owner(achievement_id), _first)


func test_upgrade_destroys_available_tao_tie_before_callbacks_and_blocks_reentry() -> void:
	var observation := {
		"destroyed_seen": false,
		"claimed_seen": false,
		"reentry_blocked": false,
	}
	var destroyed_callback := func(previous_owner: PlayerClass, destroyed: 成就牌, replacement: 成就牌) -> void:
		if destroyed.achievement_id != AchievementManager.ID_TAO_TIE:
			return
		observation["destroyed_seen"] = AchievementManager.get_achievement_state(destroyed.achievement_id) == AchievementManager.AvailabilityState.DESTROYED \
			and previous_owner == null \
			and replacement.achievement_id == AchievementManager.ID_DA_WEI_DAI
		observation["reentry_blocked"] = not AchievementManager._try_claim(_second, AchievementManager.ID_TAO_TIE)
	var claimed_callback := func(player: PlayerClass, card: 成就牌) -> void:
		if card.achievement_id == AchievementManager.ID_DA_WEI_DAI:
			observation["claimed_seen"] = player == _first \
				and AchievementManager.get_achievement_owner(card.achievement_id) == _first \
				and _first.current_score == 5
	AchievementManager.achievement_destroyed.connect(destroyed_callback, CONNECT_ONE_SHOT)
	AchievementManager.achievement_claimed.connect(claimed_callback, CONNECT_ONE_SHOT)

	assert_true(AchievementManager._try_claim(_first, AchievementManager.ID_DA_WEI_DAI))
	assert_true(observation["destroyed_seen"])
	assert_true(observation["claimed_seen"])
	assert_true(observation["reentry_blocked"])
	assert_eq(AchievementManager.get_achievement_score(_first), 5)


func test_wildman_cannot_auto_complete_when_either_dynamic_requirement_is_empty() -> void:
	var feiyi_backup := AchievementManager._required_shennongjia_feiyi_paths.duplicate(true)
	var scenery_backup := AchievementManager._required_shennongjia_scenery_ids.duplicate(true)
	AchievementManager._required_shennongjia_feiyi_paths.clear()
	AchievementManager.evaluate_collection_achievements(_first)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN))
	AchievementManager._required_shennongjia_feiyi_paths = feiyi_backup
	AchievementManager._required_shennongjia_scenery_ids.clear()
	AchievementManager.evaluate_collection_achievements(_first)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN))
	AchievementManager._required_shennongjia_scenery_ids = scenery_backup


func test_bottomless_stomach_destroys_tao_tie_wherever_it_is_owned() -> void:
	_record_food(_first, 6)
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_TAO_TIE), _first)
	assert_eq(AchievementManager.get_achievement_score(_first), 2)
	_record_food(_second, 12)
	assert_eq(AchievementManager.get_achievement_state(AchievementManager.ID_TAO_TIE), AchievementManager.AvailabilityState.DESTROYED)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_TAO_TIE))
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_DA_WEI_DAI), _second)
	assert_eq(AchievementManager.get_achievement_score(_first), 0)
	assert_eq(AchievementManager.get_achievement_score(_second), 5)


func test_bottomless_stomach_replaces_same_players_tao_tie_instead_of_stacking() -> void:
	_record_food(_first, 12)
	assert_eq(AchievementManager.get_achievement_state(AchievementManager.ID_TAO_TIE), AchievementManager.AvailabilityState.DESTROYED)
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_DA_WEI_DAI), _first)
	assert_eq(AchievementManager.get_achievement_score(_first), 5)


func test_reset_restores_global_pool_and_clears_progress() -> void:
	_record_food(_first, 6)
	var players: Array[PlayerClass] = [_first, _second]
	AchievementManager.reset_for_new_game(players)
	assert_eq(AchievementManager.get_achievement_state(AchievementManager.ID_TAO_TIE), AchievementManager.AvailabilityState.AVAILABLE)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_TAO_TIE))
	assert_eq(AchievementManager.get_owned_achievements(_first).size(), 0)
	assert_eq(AchievementManager.get_progress(_first, AchievementManager.ID_TAO_TIE)[&"current"], 0)


func test_scenery_check_ins_are_unique_by_location_and_claim_at_six() -> void:
	for index: int in 6:
		var section: MapSection = _make_scenery(Vector3i(index, -index, 0), MapSection.REGION.武汉)
		assert_true(AchievementManager.record_scenery_check_in(_first, section))
		assert_false(AchievementManager.record_scenery_check_in(_first, section))
		section.free()
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_YOU_SHAN_WAN_SHUI), _first)
	assert_eq(AchievementManager.get_achievement_score(_first), 5)


func test_each_public_event_resolution_is_counted_even_for_same_id() -> void:
	var event_card: 事件牌 = 事件牌.new()
	event_card.event_id = &"unique_reveal"
	AchievementManager.record_gameplay_event(_first, event_card)
	AchievementManager.record_gameplay_event(_first, event_card)
	assert_eq(AchievementManager.get_progress(_first, AchievementManager.ID_XING_YUN_ER)[&"current"], 2)


func test_reaching_twelve_energy_claims_once_and_never_revokes() -> void:
	AchievementManager.record_energy_reached(_first, 11)
	assert_eq(AchievementManager.get_achievement_score(_first), 0)
	AchievementManager.record_energy_reached(_first, 12)
	AchievementManager.record_energy_reached(_first, 3)
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_CHAO_YUE_REN_LEI), _first)
	assert_eq(AchievementManager.get_achievement_score(_first), 2)


func test_resource_manager_energy_signal_is_connected_once_at_startup() -> void:
	_first.current_energy = 11
	assert_true(ResourceManager.modify_energy(_first, 1, "成就信号测试"))
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_CHAO_YUE_REN_LEI), _first)
	var connections: Array[Dictionary] = ResourceManager.get_signal_connection_list(&"energy_changed")
	var achievement_connections: int = 0
	for connection: Dictionary in connections:
		if connection.get("callable") == AchievementManager._on_energy_changed:
			achievement_connections += 1
	assert_eq(achievement_connections, 1)


func test_wildman_uses_actual_shennongjia_resources_and_scenery() -> void:
	for file_name: String in DirAccess.get_files_at(AchievementManager.SHENNONGJIA_FEIYI_DIR):
		if file_name.ends_with(".tres"):
			var card: 非遗牌 = ResourceLoader.load(AchievementManager.SHENNONGJIA_FEIYI_DIR.path_join(file_name)) as 非遗牌
			if card != null:
				_first.非遗牌手牌.append(card)
	AchievementManager.evaluate_collection_achievements(_first)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN))
	var packed_map: PackedScene = ResourceLoader.load(AchievementManager.MAP_SCENE_PATH) as PackedScene
	var map_root: Node = packed_map.instantiate()
	var shennongjia_scenery: Array[MapSection] = []
	_collect_shennongjia_scenery(map_root, shennongjia_scenery)
	assert_gt(shennongjia_scenery.size(), 0)
	for section: MapSection in shennongjia_scenery:
		AchievementManager.record_scenery_check_in(_first, section)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN), "未传承国家级牌不得完成收藏成就")
	var progress := AchievementManager.get_progress(_first, AchievementManager.ID_YE_REN)
	assert_lt(int(progress[&"feiyi_current"]), int(progress[&"feiyi_target"]))
	map_root.free()


func test_central_hand_transfer_signal_rechecks_wildman_without_manual_evaluation() -> void:
	var required_cards: Array[非遗牌] = []
	for file_name: String in DirAccess.get_files_at(AchievementManager.SHENNONGJIA_FEIYI_DIR):
		if file_name.ends_with(".tres"):
			var card := ResourceLoader.load(AchievementManager.SHENNONGJIA_FEIYI_DIR.path_join(file_name)) as 非遗牌
			if card != null and card.category != 非遗牌.CardCategory.国家级非遗:
				required_cards.append(card)
	assert_gt(required_cards.size(), 0)
	var final_card: 非遗牌 = required_cards.pop_back()
	AchievementManager._required_shennongjia_feiyi_paths = {final_card.resource_path: true}
	ResourceManager.add_feiyi_card(_second, final_card, false)
	var packed_map := ResourceLoader.load(AchievementManager.MAP_SCENE_PATH) as PackedScene
	var map_root: Node = packed_map.instantiate()
	var shennongjia_scenery: Array[MapSection] = []
	_collect_shennongjia_scenery(map_root, shennongjia_scenery)
	for section: MapSection in shennongjia_scenery:
		AchievementManager.record_scenery_check_in(_first, section)
	assert_null(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN))

	assert_true(ResourceManager.transfer_feiyi_card(_second, _first, final_card))
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_YE_REN), _first)
	map_root.free()


func test_unregistered_players_and_reserved_guardian_interface_have_no_side_effects() -> void:
	var outsider: PlayerClass = PlayerClass.new()
	var food: 食物牌 = 食物牌.new()
	AchievementManager.record_food_consumed(outsider, food)
	assert_true(AchievementManager.get_progress(outsider, AchievementManager.ID_TAO_TIE).is_empty())
	assert_false(AchievementManager.record_national_task_completed(outsider, &"future_task"))
	assert_eq(AchievementManager.get_all_achievements().size(), 6)
	outsider.free()


func test_player_can_be_registered_before_entering_scene_tree() -> void:
	var outsider: PlayerClass = PlayerClass.new()
	assert_true(AchievementManager.register_player(outsider))
	assert_false(AchievementManager.register_player(outsider))
	AchievementManager.record_energy_reached(outsider, 12)
	assert_eq(AchievementManager.get_achievement_owner(AchievementManager.ID_CHAO_YUE_REN_LEI), outsider)
	outsider.free()


func _record_food(player: PlayerClass, count: int) -> void:
	var food: 食物牌 = 食物牌.new()
	for _index: int in count:
		AchievementManager.record_food_consumed(player, food)


func _record_unique_events(player: PlayerClass, count: int, prefix: String) -> void:
	for index: int in count:
		var card: 事件牌 = 事件牌.new()
		card.event_id = StringName("%s_%d" % [prefix, index])
		AchievementManager.record_gameplay_event(player, card)


func _make_scenery(position: Vector3i, region: MapSection.REGION) -> MapSection:
	var section: MapSection = MapSection.new()
	section.location_index = position
	section.region = region
	section.type = MapSection.SectionType.风景
	return section


func _collect_shennongjia_scenery(node: Node, output: Array[MapSection]) -> void:
	if node is MapSection:
		var section: MapSection = node as MapSection
		if section.region == MapSection.REGION.神农架 and section.type == MapSection.SectionType.风景:
			output.append(section)
	for child: Node in node.get_children():
		_collect_shennongjia_scenery(child, output)
