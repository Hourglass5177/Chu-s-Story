extends GutTest

const TEST_PATH := "user://discovery-test.cfg"

var _original_path: String
var _original_discovered: Dictionary


func before_each() -> void:
	_original_path = DiscoveryManager._storage_path
	_original_discovered = DiscoveryManager._discovered.duplicate(true)
	_remove_test_file()
	DiscoveryManager.configure_storage_path(TEST_PATH)


func after_each() -> void:
	_remove_test_file()
	DiscoveryManager._storage_path = _original_path
	DiscoveryManager._test_storage_enabled = false
	DiscoveryManager._discovered = _original_discovered.duplicate(true)


func test_public_kinds_are_open_and_hidden_kinds_start_locked() -> void:
	for kind: StringName in [DiscoveryManager.KIND_FEIYI, DiscoveryManager.KIND_PROFESSION, DiscoveryManager.KIND_SCENERY]:
		var ids := DiscoveryManager.get_known_ids(kind)
		assert_gt(ids.size(), 0)
		assert_true(DiscoveryManager.is_discovered(kind, ids[0]))
		var progress := DiscoveryManager.get_discovery_progress(kind)
		assert_eq(progress.discovered, progress.total)
	for kind: StringName in [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT]:
		var ids := DiscoveryManager.get_known_ids(kind)
		assert_gt(ids.size(), 0)
		assert_false(DiscoveryManager.is_discovered(kind, ids[0]))


func test_discovery_is_idempotent_persistent_and_ignores_unknown_ids() -> void:
	var food_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD)[0]
	watch_signals(DiscoveryManager)
	assert_true(DiscoveryManager.record_discovery(DiscoveryManager.KIND_FOOD, food_id))
	assert_false(DiscoveryManager.record_discovery(DiscoveryManager.KIND_FOOD, food_id))
	assert_false(DiscoveryManager.record_discovery(DiscoveryManager.KIND_FOOD, &"not_a_real_food"))
	assert_signal_emit_count(DiscoveryManager, "discovery_recorded", 1)
	DiscoveryManager.configure_storage_path(TEST_PATH)
	assert_true(DiscoveryManager.is_discovered(DiscoveryManager.KIND_FOOD, food_id))


func test_corrupt_or_unknown_saved_values_fall_back_safely() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("这不是有效的 ConfigFile")
	file.close()
	assert_ne(DiscoveryManager.load_progress(), OK)
	assert_eq(DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_EVENT).discovered, 0)

	var config := ConfigFile.new()
	config.set_value("meta", "version", DiscoveryManager.SAVE_VERSION)
	config.set_value("discoveries", "event", PackedStringArray(["deleted_old_event"]))
	assert_eq(config.save(TEST_PATH), OK)
	assert_eq(DiscoveryManager.load_progress(), OK)
	assert_false(DiscoveryManager.is_discovered(DiscoveryManager.KIND_EVENT, &"deleted_old_event"))


func test_actual_resource_totals_are_dynamic_and_unique() -> void:
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FEIYI).size(), 87)
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD).size(), 60)
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_EVENT).size(), 40)
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_ACHIEVEMENT).size(), 6)
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_PROFESSION).size(), 6)
	assert_eq(DiscoveryManager.get_known_ids(DiscoveryManager.KIND_SCENERY).size(), 21)
	for kind: StringName in [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT]:
		var slot_ids := DiscoveryManager.get_known_ids(kind)
		var lexical_ids := slot_ids.duplicate()
		lexical_ids.sort()
		assert_ne(slot_ids, lexical_ids, "%s 的隐藏卡位不得使用可推断的拼音顺序" % kind)


func test_typed_gameplay_signals_unlock_event_and_achievement_once() -> void:
	await get_tree().process_frame
	var event_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_EVENT)[0]
	var event_card := 事件牌.new()
	event_card.event_id = event_id
	EventManager.event_revealed.emit(null, event_card)
	assert_true(DiscoveryManager.is_discovered(DiscoveryManager.KIND_EVENT, event_id))

	var achievement_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_ACHIEVEMENT)[0]
	var achievement_card := 成就牌.new()
	achievement_card.achievement_id = achievement_id
	AchievementManager.achievement_claimed.emit(null, achievement_card)
	assert_true(DiscoveryManager.is_discovered(DiscoveryManager.KIND_ACHIEVEMENT, achievement_id))


func test_food_unlocks_only_after_a_front_card_view_is_visible() -> void:
	var food_id := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD)[0]
	var card := 食物牌.new()
	card.food_id = food_id
	card.card_name = "测试食物"
	var view := FoodCardView.new()
	view.visible = false
	view.setup(card, null, "查看", true)
	add_child_autofree(view)
	await get_tree().process_frame
	assert_false(DiscoveryManager.is_discovered(DiscoveryManager.KIND_FOOD, food_id))
	view.visible = true
	await get_tree().process_frame
	assert_true(DiscoveryManager.is_discovered(DiscoveryManager.KIND_FOOD, food_id))
	var request_capture := {"card": null, "source": null}
	view.guide_requested.connect(func(selected_card: 食物牌, source: Control) -> void:
		request_capture.card = selected_card
		request_capture.source = source
	)
	view.icon.pressed.emit()
	assert_same(request_capture.card, card, "正面牌图应提供对应食物的图鉴入口")
	assert_same(request_capture.source, view.icon)


func _remove_test_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute)
